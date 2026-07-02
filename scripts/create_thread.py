from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

SUPPORTED_OPS = {
    "fp_add",
    "fp_sub",
    "fp_mul",
    "fp_fma",
    "fp_recip",
    "fp_cmp",
    "mux",
    "mem_read",
    "mem_write",
}


DEFAULT_LATENCIES = {
    "fp_add": 8,
    "fp_sub": 8,
    "fp_mul": 5,
    "fp_fma": 9,
    "fp_recip": 22,
    "fp_cmp": 1,
    "mux": 1,
    "mem_read": 1,
    "mem_write": 1,
}


@dataclass(frozen=True)
class OpInfo:
    op_type: str
    latency: int
    expr: str
    op_symbol: str = ""
    cmp_kind: str = ""
    valid_expr: str = "pipe_en"


class HardwareDAG:
    """
    Thread-pipeline DAG builder.

    Design assumptions for this generator:
    - II = 1 for the thread pipeline.
    - No temporary register pooling/reuse.
    - Every operation maps to its own hardware instance.
    - Supported arithmetic ops: add, sub, mul, recip.
    - Supported control op: compare, plus select (if/else mux).
    - Supported memory ops: read and write.
    """

    def __init__(self, latencies=None):
        self.latencies = dict(DEFAULT_LATENCIES)
        if latencies:
            self.latencies.update(latencies)

        missing = SUPPORTED_OPS - set(self.latencies.keys())
        if missing:
            missing_str = ", ".join(sorted(missing))
            raise ValueError(f"Missing latencies for: {missing_str}")

        self.ops = {}
        self.op_inputs = {}
        self.dependencies = []
        self.node_names = {}
        self.expression_cache = {}
        self.counters = {k: 0 for k in SUPPORTED_OPS}
        self.global_valid_expr = "pipe_en"
        self.control_dependencies = []
        self.op_controls = {}

    @staticmethod
    def _sanitize_sv_name(name: str) -> str:
        return re.sub(r"[^0-9A-Za-z_]", "_", name)

    def _new_node(self, op_type, expr, op_symbol="", cmp_kind="", valid_expr="pipe_en"):
        self.counters[op_type] += 1
        node_id = f"{op_type}_{self.counters[op_type]}"
        self.ops[node_id] = OpInfo(
            op_type=op_type,
            latency=self.latencies[op_type],
            expr=expr,
            op_symbol=op_symbol,
            cmp_kind=cmp_kind,
            valid_expr=valid_expr,
        )
        return node_id

    @staticmethod
    def _strip_outer_parens(expr):
        s = expr.strip()
        while s.startswith("(") and s.endswith(")"):
            depth = 0
            balanced = True
            for i, ch in enumerate(s):
                if ch == "(":
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth < 0:
                        balanced = False
                        break
                if depth == 0 and i != len(s) - 1:
                    balanced = False
                    break
            if not balanced or depth != 0:
                break
            s = s[1:-1].strip()
        return s

    @classmethod
    def _split_and_terms(cls, expr):
        s = cls._strip_outer_parens(str(expr).strip())
        if not s:
            return []

        terms = []
        depth = 0
        start = 0
        i = 0
        while i < len(s):
            ch = s[i]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
            elif ch == "&" and i + 1 < len(s) and s[i + 1] == "&" and depth == 0:
                part = s[start:i].strip()
                if part:
                    terms.extend(cls._split_and_terms(part))
                start = i + 2
                i += 1
            i += 1

        tail = s[start:].strip()
        if tail:
            terms.append(cls._strip_outer_parens(tail))

        return [t for t in terms if t]

    @classmethod
    def _merge_valid_expr(cls, *exprs):
        uniq = []
        seen = set()
        for expr in exprs:
            if expr is None:
                continue
            for txt in cls._split_and_terms(expr):
                if not txt or txt == "1'b1":
                    continue
                if txt not in seen:
                    seen.add(txt)
                    uniq.append(txt)

        if not uniq:
            return "pipe_en"
        if "pipe_en" not in seen:
            uniq.insert(0, "pipe_en")
        return " && ".join(f"({t})" for t in uniq)

    def _input_valid_expr(self, sig):
        if isinstance(sig, PredicateSignal):
            return sig.valid_expr
        if isinstance(sig, Signal):
            return sig.valid_expr
        return "pipe_en"

    def discard_if_false(self, predicate):
        if isinstance(predicate, PredicateSignal):
            self.global_valid_expr = self._merge_valid_expr(
                self.global_valid_expr,
                predicate.valid_expr,
                predicate.expr,
            )
            self.control_dependencies = [predicate]
            return
        raise TypeError("discard_if_false expects a PredicateSignal")

    def _add_edges(self, node_id, inputs, control_inputs=()):
        self.op_inputs[node_id] = tuple(inputs)
        self.op_controls[node_id] = tuple(control_inputs)
        for sig in inputs:
            if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id:
                self.dependencies.append((sig.hw_id, node_id))
        for sig in control_inputs:
            if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id:
                self.dependencies.append((sig.hw_id, node_id))

    def add_binary_operation(self, op_type, left, right, expr, op_symbol=""):
        if op_type not in ("fp_add", "fp_sub", "fp_mul"):
            raise ValueError(f"Unsupported binary op type: {op_type}")

        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(left),
        )
        cache_key = (op_type, expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node(
            op_type, expr, op_symbol=op_symbol, valid_expr=valid_expr
        )
        self._add_edges(node_id, (left, right), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_fma_operation(self, a, b, c, expr):
        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(a),
        )
        cache_key = ("fp_fma", expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node("fp_fma", expr, valid_expr=valid_expr)
        self._add_edges(node_id, (a, b, c), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_unary_operation(self, op_type, src, expr):
        if op_type != "fp_recip":
            raise ValueError(f"Unsupported unary op type: {op_type}")

        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(src),
        )
        cache_key = (op_type, expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node(op_type, expr, valid_expr=valid_expr)
        self._add_edges(node_id, (src,), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_compare_operation(self, cmp_kind, left, right, expr):
        if cmp_kind not in ("lt", "le", "gt", "ge", "eq", "ne"):
            raise ValueError(f"Unsupported compare kind: {cmp_kind}")

        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(left),
        )
        cache_key = ("fp_cmp", cmp_kind, expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node(
            "fp_cmp", expr, cmp_kind=cmp_kind, valid_expr=valid_expr
        )
        self._add_edges(node_id, (left, right), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_select_operation(self, pred, when_true, when_false, expr):
        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(pred),
        )
        cache_key = ("mux", expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node("mux", expr, valid_expr=valid_expr)
        self._add_edges(
            node_id, (pred, when_true, when_false), tuple(self.control_dependencies)
        )
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_memory_read_operation(self, addr, expr, after=None):
        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(addr),
        )
        cache_key = ("mem_read", expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node("mem_read", expr, valid_expr=valid_expr)
        inputs = [addr]
        # Optional sequencing edge: force this memory read to happen after a
        # specific signal-producing operation without changing read semantics.
        if isinstance(after, (Signal, PredicateSignal)) and after.hw_id:
            inputs.append(after)
        self._add_edges(node_id, tuple(inputs), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_memory_write_operation(self, addr, data, expr):
        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(data),
        )
        cache_key = ("mem_write", expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node("mem_write", expr, valid_expr=valid_expr)
        self._add_edges(node_id, (addr, data), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def _topological_order(self):
        incoming_count = {node: 0 for node in self.ops}
        outgoing = {node: [] for node in self.ops}

        for src, dst in self.dependencies:
            incoming_count[dst] += 1
            outgoing[src].append(dst)

        ready = sorted(node for node, count in incoming_count.items() if count == 0)
        order = []

        while ready:
            node = ready.pop(0)
            order.append(node)
            for nxt in outgoing[node]:
                incoming_count[nxt] -= 1
                if incoming_count[nxt] == 0:
                    ready.append(nxt)
                    ready.sort()

        if len(order) != len(self.ops):
            raise RuntimeError(
                "Cycle detected in DAG; hardware pipeline graph must be acyclic."
            )
        return order

    def _consumer_map(self):
        consumers = {node: [] for node in self.ops}
        for src, dst in self.dependencies:
            consumers[src].append(dst)
        return consumers

    def schedule(self, ii=1):
        if ii != 1:
            raise ValueError("This script models a strict II=1 thread pipeline.")

        order = self._topological_order()

        start_times = {}
        for node in order:
            preds = [src for src, dst in self.dependencies if dst == node]
            if not preds:
                start_times[node] = 0
                continue

            ready_time = 0
            for pred in preds:
                pred_info = self.ops[pred]
                ready_time = max(ready_time, start_times[pred] + pred_info.latency)
            start_times[node] = ready_time

        sorted_ops = sorted(order, key=lambda nid: (start_times[nid], nid))

        unit_count = {k: 0 for k in SUPPORTED_OPS}
        unit_by_node = {}
        for node in sorted_ops:
            op_type = self.ops[node].op_type
            unit_count[op_type] += 1
            unit_by_node[node] = f"{op_type}_{unit_count[op_type]}"

        return {
            "start_times": start_times,
            "sorted_ops": sorted_ops,
            "unit_by_node": unit_by_node,
            "consumers": self._consumer_map(),
            "latency": max(
                (start_times[node] + self.ops[node].latency for node in self.ops),
                default=0,
            ),
        }

    def _signal_ref(self, sig, wire_name_by_node):
        if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id:
            return wire_name_by_node[sig.hw_id]
        if isinstance(sig, (Signal, PredicateSignal)):
            return sig.expr
        return str(sig)

    def _unit_out_wire_name(self, op_type, unit_name):
        if op_type in ("fp_cmp", "mem_write"):
            return f"{unit_name}_pred"
        if op_type == "fp_recip":
            return f"{unit_name}_out"
        if op_type == "mem_read":
            return f"{unit_name}_rdata"
        if op_type == "mux":
            return f"{unit_name}_out"
        return f"{unit_name}_res"

    def _select_valid_driver_signal(self, op_type, inputs):
        produced_inputs = [
            sig
            for sig in inputs
            if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id
        ]

        if op_type == "fp_cmp":
            for sig in inputs:
                if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id:
                    return sig
            return inputs[0] if inputs else None

        if op_type == "fp_fma" and produced_inputs:
            return produced_inputs[-1]

        if op_type in ("fp_add", "fp_sub", "fp_mul", "fp_recip", "mux"):
            if produced_inputs:
                return produced_inputs[-1]

        if op_type == "mem_write":
            if len(inputs) > 1:
                return inputs[1]
            return inputs[0] if inputs else None

        return inputs[0] if inputs else None

    def _leaf_axis_base(self, sig):
        raw = getattr(sig, "expr", str(sig))
        return self._sanitize_sv_name(raw)

    def _leaf_data_ref(self, sig):
        return f"s_axis_{self._leaf_axis_base(sig)}_tdata"

    def _leaf_valid_ref(self, sig):
        return f"s_axis_{self._leaf_axis_base(sig)}_tvalid"

    def _leaf_ready_ref(self, sig):
        return f"s_axis_{self._leaf_axis_base(sig)}_tready"

    def dump_thread_pipeline(self, schedule_result, output_path):
        start_times = schedule_result["start_times"]
        sorted_ops = schedule_result["sorted_ops"]
        unit_by_node = schedule_result["unit_by_node"]

        wire_name_by_node = {
            node: self._unit_out_wire_name(self.ops[node].op_type, unit_by_node[node])
            for node in sorted_ops
        }
        valid_name_by_node = {
            node: f"valid_pipe[{start_times[node] + self.ops[node].latency}]"
            for node in sorted_ops
        }

        lines = []
        lines.append("// AUTO-GENERATED FROM scripts/create_thread.py")
        lines.append("// Thread pipeline autogen block")
        lines.append("")

        lines.append("// ---- Unit output wires ----")
        for node in sorted_ops:
            info = self.ops[node]
            wire = wire_name_by_node[node]
            width = 1 if info.op_type in ("fp_cmp", "mem_write") else 32
            lines.append(f"logic [{width-1}:0] {wire};")
            if info.op_type == "fp_cmp":
                lines.append(f"logic {wire}_valid;")
        lines.append("")

        for node in sorted_ops:
            if self.ops[node].op_type == "fp_cmp":
                valid_name_by_node[node] = f"{wire_name_by_node[node]}_valid"

        lines.append("// ---- Selected outputs ----")
        selected_output_names = ("texcoord_u", "texcoord_v", "comp_z")
        selected_nodes = {
            node: name
            for node, name in self.node_names.items()
            if name in selected_output_names
        }
        if selected_nodes:
            for node in sorted(selected_nodes, key=lambda n: (start_times[n], n)):
                out_name = selected_nodes[node]
                src_wire = wire_name_by_node[node]
                width = 1 if self.ops[node].op_type in ("fp_cmp", "mem_write") else 32
                if self.ops[node].op_type == "fp_cmp":
                    src_valid = valid_name_by_node[node]
                else:
                    src_valid = (
                        f"valid_pipe[{start_times[node] + self.ops[node].latency + 1}]"
                    )
                if width == 1:
                    lines.append(f"logic {out_name}_tdata;")
                else:
                    lines.append(f"logic [{width-1}:0] {out_name}_tdata;")
                lines.append(f"logic {out_name}_tvalid;")
                lines.append(f"assign {out_name}_tdata = {src_wire};")
                lines.append(f"assign {out_name}_tvalid = {src_valid};")
        else:
            lines.append("// None")
        lines.append("")

        lines.append("// ---- Unit input ready wires ----")
        lines.append("// None (non-blocking FP modules use aclken/valid_in)")
        lines.append("")

        lines.append("// ---- Unit mapping summary ----")
        for node in sorted_ops:
            info = self.ops[node]
            start_t = start_times[node]
            end_t = start_t + info.latency
            unit = unit_by_node[node]
            out_wire = wire_name_by_node[node]
            lines.append(
                f"// {node:<16} -> {unit:<16}  out={out_wire:<18}  start={start_t:>3}  end={end_t:>3}  valid={info.valid_expr}  expr={info.expr}"
            )
        lines.append("")

        def _signal_width(sig):
            if isinstance(sig, PredicateSignal):
                return 1
            if isinstance(sig, Signal) and sig.hw_id:
                prod_info = self.ops[sig.hw_id]
                return 1 if prod_info.op_type in ("fp_cmp", "mem_write") else 32
            if isinstance(sig, Signal) and getattr(sig, "type", "") == "addr_t":
                return 14
            return 32

        def _leaf_name(sig):
            raw = getattr(sig, "expr", str(sig))
            return self._sanitize_sv_name(raw)

        # Align any late-consumed input with delay pipes.
        # Internal AXIS skid buffers are not used in this architecture.
        input_ref_by_edge = {}
        input_valid_ref_by_edge = {}
        valid_ref_by_node = {}
        control_gate_ref_by_node = {}
        align_decls = []
        align_decls_seen = set()
        align_skeletons = []
        leaf_ready_assigns = []
        seen_leaf_ready = set()
        leaf_ready_keys = set()
        consumer_fire_nodes = {
            node
            for node in sorted_ops
            if self.ops[node].op_type in ("fp_cmp", "mem_read", "mem_write", "mux")
            and len(self.op_inputs[node]) > 0
        }

        def _declare_buffer_signal(name, width):
            if width == 1:
                if name not in align_decls_seen:
                    align_decls_seen.add(name)
                    align_decls.append(f"logic {name};")
            else:
                if name not in align_decls_seen:
                    align_decls_seen.add(name)
                    align_decls.append(f"logic [{width-1}:0] {name};")

        def _emit_delay_align(src_ref, dst_ref, width, stages):
            _declare_buffer_signal(dst_ref, width)
            align_skeletons.append(
                f"delay_pipe #(.WIDTH({width}), .STAGES({stages})) u_{dst_ref}_data_delay (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in({src_ref}), .data_out({dst_ref}));"
            )

        # Calculate max pipeline depth for master valid pipeline
        max_depth = 0
        for node in sorted_ops:
            stage = start_times[node] + self.ops[node].latency + 1
            max_depth = max(max_depth, stage)

        # Track alignment delays to find max alignment depth
        alignment_delays = {}

        for dst in sorted_ops:
            dst_start = start_times[dst]
            inputs = self.op_inputs[dst]

            for idx, sig in enumerate(inputs):
                width = _signal_width(sig)

                if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id:
                    src = sig.hw_id
                    src_ready = start_times[src] + self.ops[src].latency
                    extra_delay = dst_start - src_ready
                    src_ref = wire_name_by_node[src]
                    src_valid_ref = valid_name_by_node[src]
                    src_tag = src
                else:
                    # Leaf inputs are available at the buffered ingress token stage.
                    # delay_pipe STAGES(N) implements exactly N registered cycles,
                    # so leaf alignment should match the destination start stage.
                    extra_delay = dst_start
                    src_ref = self._leaf_data_ref(sig)
                    src_valid_ref = f"valid_pipe[{dst_start + 1}]"
                    src_tag = _leaf_name(sig)
                    leaf_ready_keys.add(self._leaf_axis_base(sig))

                if extra_delay > 0:
                    buf_name = f"align_{src_tag}_to_{dst}_i{idx}_d{extra_delay}"
                    input_ref_by_edge[(dst, idx)] = buf_name
                    input_valid_ref_by_edge[(dst, idx)] = f"{buf_name}_valid"
                    _declare_buffer_signal(buf_name, width)
                    _emit_delay_align(src_ref, buf_name, width, extra_delay)
                    alignment_delays[buf_name] = extra_delay
                else:
                    input_ref_by_edge[(dst, idx)] = src_ref
                    input_valid_ref_by_edge[(dst, idx)] = src_valid_ref

        for dst in sorted_ops:
            inputs = self.op_inputs[dst]
            if not inputs:
                valid_ref_by_node[dst] = "valid_pipe[0]"
                control_gate_ref_by_node[dst] = "1'b1"
                continue

            # Fixed-latency token model: the unit fires from its own start-cycle tap.
            valid_ref_by_node[dst] = f"valid_pipe[{start_times[dst] + 1}]"
            control_gate_ref_by_node[dst] = "1'b1"

        # Note: consumer fire wiring will be generated later after valid_pipe updates

        lines.append("// ---- Master valid pipeline ----")
        lines.append(f"logic [{max_depth}:0] valid_pipe;")
        lines.append("assign valid_pipe[0] = input_bundle_buf_tvalid;")
        lines.append("always_ff @(posedge clk) begin")
        lines.append("  if (~rst_n)")
        lines.append(f"    valid_pipe[{max_depth}:1] <= '0;")
        lines.append("  else if (pipe_en_internal)")
        lines.append(f"    valid_pipe[{max_depth}:1] <= valid_pipe[{max_depth-1}:0];")
        lines.append("end")
        lines.append("")

        # Update alignment valid references to tap valid_pipe
        for align_name, delay in alignment_delays.items():
            input_valid_ref_by_edge_updates = {
                k: v
                for k, v in input_valid_ref_by_edge.items()
                if v == f"{align_name}_valid"
            }
            for key in input_valid_ref_by_edge_updates:
                input_valid_ref_by_edge[key] = f"valid_pipe[{delay + 1}]"

        # Recompute valid_ref_by_node as pure stage taps for fixed-latency units.
        valid_ref_by_node = {
            node: f"valid_pipe[{start_times[node] + 1}]" for node in sorted_ops
        }

        lines.append("// ---- Non-AXIS consumer fire wiring ----")
        for node in sorted_ops:
            if node in consumer_fire_nodes:
                lines.append(f"logic {node}_fire;")
        for node in sorted_ops:
            if node in consumer_fire_nodes:
                lines.append(f"assign {node}_fire = {valid_ref_by_node[node]};")
        lines.append("")

        lines.append("// ---- Delay alignment for late-consumed inputs ----")

        if align_decls:
            lines.extend(align_decls)
            lines.append("")
            lines.extend(align_skeletons)
        else:
            lines.append("// None")
        lines.append("")

        lines.append("// Leaf ready signals not used (internal distribution only)")
        lines.append("")

        lines.append("// ---- Unit output ready wiring ----")
        lines.append("// None (non-blocking FP modules have no AXIS output ready)")
        lines.append("")

        lines.append("// ---- Unit instantiation skeletons ----")
        lines.append("// NOTE: Non-blocking FP modules with aclken(pipe_en_internal)")
        lines.append("// NOTE: Valid is propagated explicitly via valid_pipe")
        for node in sorted_ops:
            info = self.ops[node]
            unit = unit_by_node[node]
            out_wire = wire_name_by_node[node]
            valid_in = valid_ref_by_node[node]
            control_gate = control_gate_ref_by_node.get(node, "1'b1")
            inputs = self.op_inputs[node]

            if info.op_type == "fp_add":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                lines.append(f"fp_add #(.LATENCY({info.latency})) u_{unit} (")
                lines.append(
                    "    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),"
                )
                lines.append(f"    .valid_in({valid_in}),")
                lines.append(f"    .a({a}), .b({b}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_sub":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                lines.append(f"fp_sub #(.LATENCY({info.latency})) u_{unit} (")
                lines.append(
                    "    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),"
                )
                lines.append(f"    .valid_in({valid_in}),")
                lines.append(f"    .a({a}), .b({b}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_mul":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                lines.append(f"fp_mul #(.LATENCY({info.latency})) u_{unit} (")
                lines.append(
                    "    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),"
                )
                lines.append(f"    .valid_in({valid_in}),")
                lines.append(f"    .a({a}), .b({b}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_fma":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                c = input_ref_by_edge[(node, 2)]
                lines.append(f"fp_fma #(.LATENCY({info.latency})) u_{unit} (")
                lines.append(
                    "    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),"
                )
                lines.append(f"    .valid_in({valid_in}),")
                lines.append(f"    .a({a}), .b({b}), .c({c}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_recip":
                a = input_ref_by_edge[(node, 0)]
                lines.append(f"fp_recip #(.LATENCY({info.latency})) u_{unit} (")
                lines.append(
                    "    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),"
                )
                lines.append(f"    .valid_in({valid_in}),")
                lines.append(f"    .a({a}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type in ("mux", "mem_read", "mem_write"):
                if info.op_type == "mux":
                    s = input_ref_by_edge[(node, 0)]
                    t = input_ref_by_edge[(node, 1)]
                    f = input_ref_by_edge[(node, 2)]
                    lines.append(f"assign {out_wire} = ({s}) ? ({t}) : ({f});")
                elif info.op_type == "mem_read":
                    addr = input_ref_by_edge[(node, 0)]
                    lines.append(f"assign z_rd_en = {node}_fire;")
                    lines.append(f"assign z_rd_addr = {addr};")
                    lines.append(f"assign {out_wire} = z_rd_data;")
                else:
                    addr = input_ref_by_edge[(node, 0)]
                    data = input_ref_by_edge[(node, 1)]
                    control_terms = []
                    for control_sig in self.op_controls.get(node, ()):
                        if (
                            isinstance(control_sig, (Signal, PredicateSignal))
                            and control_sig.hw_id
                        ):
                            control_wire = wire_name_by_node[control_sig.hw_id]
                            control_terms.append(f"({control_wire}[0])")
                    if control_terms:
                        wr_en_expr = f"{node}_fire && " + " && ".join(control_terms)
                    else:
                        wr_en_expr = f"{node}_fire"
                    lines.append(f"assign z_wr_en = {wr_en_expr};")
                    lines.append(f"assign z_wr_addr = {addr};")
                    lines.append(f"assign z_wr_data = {data};")
            elif info.op_type == "fp_cmp":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                if info.cmp_kind == "le":
                    lines.append(f"fp_cmp_le u_{unit} (")
                    lines.append("    .aclk(clk),")
                    lines.append("    .aclken(pipe_en_internal),")
                    lines.append(f"    .s_axis_a({a}),")
                    lines.append("    .s_axis_a_valid(),")
                    lines.append(f"    .s_axis_b({b}),")
                    lines.append("    .s_axis_b_valid(),")
                    lines.append(f"    .m_axis_res({out_wire}[0]),")
                    lines.append("    .m_axis_tvalid()")
                    lines.append(");")
                else:
                    cmp_map = {
                        "lt": "3'd0",
                        "le": "3'd1",
                        "gt": "3'd2",
                        "ge": "3'd3",
                        "eq": "3'd4",
                        "ne": "3'd5",
                    }
                    cmp_op = cmp_map.get(info.cmp_kind, "3'd1")
                    lines.append(f"fp_cmp #(.LATENCY(1)) u_{unit} (")
                    lines.append(
                        "    .aclk(clk), .aresetn(rst_n), .aclken(pipe_en_internal),"
                    )
                    lines.append(f"    .cmp_op({cmp_op}),")
                    lines.append(f"    .valid_in({valid_in}),")
                    lines.append(f"    .a({a}), .b({b}),")
                    lines.append(f"    .result({out_wire}[0])")
                    lines.append(");")
        lines.append("")

        # ---- Output skid buffer ----
        lines.append("// ---- Output skid buffer ----")
        # Collect selected output names and widths in order
        out_fields = []
        for node in sorted(selected_nodes, key=lambda n: (start_times[n], n)):
            out_name = selected_nodes[node]
            width = 1 if self.ops[node].op_type in ("fp_cmp", "mem_write") else 32
            if self.ops[node].op_type == "fp_cmp":
                stage = start_times[node] + self.ops[node].latency
            else:
                stage = start_times[node] + self.ops[node].latency + 1
            out_fields.append((out_name, width, stage))

        if out_fields:
            final_out_stage = max(stage for _, _, stage in out_fields)
            total_out_width = sum(w for _, w, _ in out_fields)
            lines.append(f"localparam int OUTBUNDLEWIDTH = {total_out_width};")
            lines.append("logic [OUTBUNDLEWIDTH-1:0] output_bundle_tdata;")
            lines.append("logic output_bundle_tvalid;")
            lines.append("logic output_bundle_s_axis_tready;")
            lines.append("logic [OUTBUNDLEWIDTH-1:0] output_bundle_buf_tdata;")
            lines.append("logic output_bundle_buf_tvalid;")
            lines.append("logic output_bundle_buf_tready;")
            lines.append("")
            bundle_data_refs = []
            for out_name, width, stage in out_fields:
                delay_to_final = final_out_stage - stage
                if delay_to_final > 0:
                    aligned_name = f"{out_name}_bundle_tdata"
                    if width == 1:
                        lines.append(f"logic {aligned_name};")
                    else:
                        lines.append(f"logic [{width-1}:0] {aligned_name};")
                    lines.append(
                        f"delay_pipe #(.WIDTH({width}), .STAGES({delay_to_final})) u_align_{out_name}_to_output_bundle_d{delay_to_final} (.clk(clk), .rst_n(rst_n), .clken(pipe_en_internal), .data_in({out_name}_tdata), .data_out({aligned_name}));"
                    )
                    bundle_data_refs.append(aligned_name)
                else:
                    bundle_data_refs.append(f"{out_name}_tdata")

            if any(final_out_stage - stage > 0 for _, _, stage in out_fields):
                lines.append("")

            pack_fields = ", ".join(bundle_data_refs)
            lines.append(f"assign output_bundle_tdata = {{{pack_fields}}};")
            lines.append(
                f"assign output_bundle_tvalid = valid_pipe[{final_out_stage}];"
            )
            lines.append("")
            lines.append("axis_skid_buffer #(")
            lines.append("    .WIDTH (OUTBUNDLEWIDTH),")
            lines.append("    .STAGES(1)")
            lines.append(") u_output_bundle_skid (")
            lines.append("    .aclk(clk), .aresetn(rst_n),")
            lines.append("    .s_axis_tdata(output_bundle_tdata),")
            lines.append("    .s_axis_tvalid(output_bundle_tvalid),")
            lines.append("    .s_axis_tready(output_bundle_s_axis_tready),")
            lines.append("    .m_axis_tdata(output_bundle_buf_tdata),")
            lines.append("    .m_axis_tvalid(output_bundle_buf_tvalid),")
            lines.append("    .m_axis_tready(output_bundle_buf_tready)")
            lines.append(");")
            lines.append("")
            # Unpack buf_tdata back to individual outputs
            unpack_fields = ", ".join(
                f"m_axis_{name}_tdata" for name, _, _ in out_fields
            )
            lines.append(f"assign {{{unpack_fields}}} = output_bundle_buf_tdata;")
            for out_name, _, _ in out_fields:
                lines.append(
                    f"assign m_axis_{out_name}_tvalid = output_bundle_buf_tvalid;"
                )
            tready_terms = " && ".join(
                f"m_axis_{name}_tready" for name, _, _ in out_fields
            )
            lines.append(f"assign output_bundle_buf_tready = {tready_terms};")
            lines.append("")
            lines.append("// Pipeline control: clken = output skid can accept")
            lines.append("assign pipe_en_internal = output_bundle_s_axis_tready;")
            lines.append("assign input_bundle_m_axis_tready = pipe_en_internal;")
            lines.append("assign ready_out = input_bundle_s_axis_tready;")
        lines.append("")

        Path(output_path).write_text("\n".join(lines) + "\n", encoding="utf-8")

    def dump_flowchart(self, schedule_result, output_path):
        sorted_ops = schedule_result["sorted_ops"]
        unit_by_node = schedule_result["unit_by_node"]

        def op_symbol(info):
            if info.op_type == "fp_add":
                return "+"
            if info.op_type == "fp_sub":
                return "-"
            if info.op_type == "fp_mul":
                return "x"
            if info.op_type == "fp_fma":
                return "FMA\\na*b+c"
            if info.op_type == "fp_recip":
                return "1/x"
            if info.op_type == "fp_cmp":
                return f"CMP\\n{info.cmp_kind}"
            if info.op_type == "mux":
                return "MUX\\n?:"
            if info.op_type == "mem_read":
                return "MEM_RD"
            if info.op_type == "mem_write":
                return "MEM_WR"
            return info.op_type

        def op_node_decl(node, info, unit):
            label = f"{op_symbol(info)}\\n{unit}".replace('"', "'")
            if info.op_type in ("fp_add", "fp_sub", "fp_mul", "fp_recip"):
                return f'    {node}(("{label}"))'
            if info.op_type == "fp_fma":
                return f'    {node}[["{label}"]]'
            if info.op_type == "fp_cmp":
                return f'    {node}{{"{label}"}}'
            if info.op_type == "mux":
                return f'    {node}[/"{label}"/]'
            if info.op_type == "mem_read":
                return f'    {node}[["{label}"]]'
            if info.op_type == "mem_write":
                return f'    {node}{{"{label}"}}'
            return f'    {node}["{label}"]'

        lines = ["flowchart LR"]
        for node in sorted_ops:
            info = self.ops[node]
            unit = unit_by_node[node]
            lines.append(op_node_decl(node, info, unit))

        seen_leaf = set()
        for node in sorted_ops:
            for sig in self.op_inputs[node]:
                if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id:
                    lines.append(f"    {sig.hw_id} --> {node}")
                else:
                    leaf = getattr(sig, "expr", str(sig))
                    leaf_id = "L_" + re.sub(r"[^0-9A-Za-z_]", "_", leaf)
                    if leaf_id not in seen_leaf:
                        lines.append(f'    {leaf_id}(["{leaf}"])')
                        seen_leaf.add(leaf_id)
                    lines.append(f"    {leaf_id} --> {node}")

        Path(output_path).write_text("\n".join(lines) + "\n", encoding="utf-8")

    def print_schedule(self, schedule_result):
        start_times = schedule_result["start_times"]
        sorted_ops = schedule_result["sorted_ops"]
        unit_by_node = schedule_result["unit_by_node"]

        print(f"Pipeline latency: {schedule_result['latency']} cycles")
        print("II constraint: 1")
        print("Temp register pooling: disabled")
        print("")
        print(
            f"{'Operation ID':<18} | {'Unit':<14} | {'Start':>5} | {'End':>5} | {'Expr'}"
        )
        print("-" * 110)

        for node in sorted_ops:
            info = self.ops[node]
            start_t = start_times[node]
            end_t = start_t + info.latency
            print(
                f"{node:<18} | {unit_by_node[node]:<14} | {start_t:>5} | {end_t:>5} | {info.expr}"
            )


class PredicateSignal:
    def __init__(self, dag, hw_id=None, expr=None, valid_expr="pipe_en"):
        self.dag = dag
        self.hw_id = hw_id
        self.expr = expr if expr is not None else f"pred_{hw_id}"
        self.valid_expr = valid_expr

    def __bool__(self):
        raise TypeError(
            "Hardware predicate cannot be used as Python bool. Use cond.select(a, b)."
        )

    def as_valid_expr(self):
        return self.dag._merge_valid_expr(self.valid_expr, self.expr)

    def select(self, when_true, when_false):
        if when_true.dag is not self.dag or when_false.dag is not self.dag:
            raise ValueError("All signals in select must belong to the same DAG")
        if when_true.type != when_false.type:
            raise TypeError("select branches must have matching signal types")

        expr = f"({self.expr} ? {when_true.expr} : {when_false.expr})"
        node_id = self.dag.add_select_operation(self, when_true, when_false, expr)
        return Signal(
            self.dag,
            hw_id=node_id,
            expr=expr,
            type=when_true.type,
            valid_expr=self.dag.ops[node_id].valid_expr,
        )


class Signal:
    def __init__(
        self,
        dag,
        name=None,
        hw_id=None,
        expr=None,
        type="float_t",
        valid_expr="pipe_en",
    ):
        self.dag = dag
        self.hw_id = hw_id
        self.type = type
        self.valid_expr = valid_expr
        self._name = None
        if name is not None:
            self.expr = name
        elif expr is not None:
            self.expr = expr
        else:
            self.expr = f"node_{hw_id}"
        self.name = name

    @property
    def name(self):
        return self._name

    @name.setter
    def name(self, value):
        self._name = value
        if value and self.dag and self.hw_id:
            self.dag.node_names[self.hw_id] = value

    def __repr__(self):
        return f"Signal(expr={self.expr!r}, hw_id={self.hw_id!r}, type={self.type!r})"

    def _check_binary(self, other):
        if not isinstance(other, Signal):
            raise TypeError("Binary operations require Signal operands")
        if self.type != other.type:
            raise TypeError("Binary operations require matching signal types")
        if self.dag is not other.dag:
            raise ValueError("Signals must belong to the same DAG")

    def __add__(self, other):
        self._check_binary(other)
        expr = f"({self.expr} + {other.expr})"
        node_id = self.dag.add_binary_operation("fp_add", self, other, expr, "+")
        return Signal(
            self.dag,
            hw_id=node_id,
            expr=expr,
            type=self.type,
            valid_expr=self.dag.ops[node_id].valid_expr,
        )

    def __sub__(self, other):
        self._check_binary(other)
        expr = f"({self.expr} - {other.expr})"
        node_id = self.dag.add_binary_operation("fp_sub", self, other, expr, "-")
        return Signal(
            self.dag,
            hw_id=node_id,
            expr=expr,
            type=self.type,
            valid_expr=self.dag.ops[node_id].valid_expr,
        )

    def __mul__(self, other):
        self._check_binary(other)
        expr = f"({self.expr} * {other.expr})"
        node_id = self.dag.add_binary_operation("fp_mul", self, other, expr, "*")
        return Signal(
            self.dag,
            hw_id=node_id,
            expr=expr,
            type=self.type,
            valid_expr=self.dag.ops[node_id].valid_expr,
        )

    def __rtruediv__(self, other):
        if self.type != "float_t":
            raise TypeError("Reciprocal is only supported for float_t signals")
        if other != 1:
            raise NotImplementedError("Only 1 / Signal is supported")
        expr = f"(1 / {self.expr})"
        node_id = self.dag.add_unary_operation("fp_recip", self, expr)
        return Signal(
            self.dag,
            hw_id=node_id,
            expr=expr,
            type=self.type,
            valid_expr=self.dag.ops[node_id].valid_expr,
        )

    @staticmethod
    def fma(a, b, c):
        if (
            not isinstance(a, Signal)
            or not isinstance(b, Signal)
            or not isinstance(c, Signal)
        ):
            raise TypeError("fma requires Signal operands")
        if a.type != b.type or a.type != c.type:
            raise TypeError("fma requires matching signal types")
        if a.dag is not b.dag or a.dag is not c.dag:
            raise ValueError("fma signals must belong to the same DAG")

        expr = f"fma({a.expr}, {b.expr}, {c.expr})"
        node_id = a.dag.add_fma_operation(a, b, c, expr)
        return Signal(
            a.dag,
            hw_id=node_id,
            expr=expr,
            type=a.type,
            valid_expr=a.dag.ops[node_id].valid_expr,
        )

    def _cmp(self, other, kind, symbol):
        self._check_binary(other)
        expr = f"({self.expr} {symbol} {other.expr})"
        node_id = self.dag.add_compare_operation(kind, self, other, expr)
        return PredicateSignal(
            self.dag,
            hw_id=node_id,
            expr=expr,
            valid_expr=self.dag.ops[node_id].valid_expr,
        )

    @staticmethod
    def mem_read(addr, after=None):
        if not isinstance(addr, Signal):
            raise TypeError("mem_read requires a Signal address operand")
        expr = f"mem_read({addr.expr})"
        node_id = addr.dag.add_memory_read_operation(addr, expr, after=after)
        return Signal(
            addr.dag,
            hw_id=node_id,
            expr=expr,
            type="float_t",
            valid_expr=addr.dag.ops[node_id].valid_expr,
        )

    @staticmethod
    def mem_write(addr, data):
        if not isinstance(addr, Signal) or not isinstance(data, Signal):
            raise TypeError("mem_write requires Signal operands")
        if addr.dag is not data.dag:
            raise ValueError("mem_write signals must belong to the same DAG")
        expr = f"mem_write({addr.expr}, {data.expr})"
        node_id = addr.dag.add_memory_write_operation(addr, data, expr)
        return Signal(
            addr.dag,
            hw_id=node_id,
            expr=expr,
            type="event_t",
            valid_expr=addr.dag.ops[node_id].valid_expr,
        )

    def with_valid(self, condition):
        if isinstance(condition, PredicateSignal):
            cond_expr = condition.as_valid_expr()
        elif isinstance(condition, Signal):
            cond_expr = self.dag._merge_valid_expr(condition.valid_expr, condition.expr)
        else:
            cond_expr = str(condition)

        merged = self.dag._merge_valid_expr(self.valid_expr, cond_expr)
        return Signal(
            self.dag,
            hw_id=self.hw_id,
            expr=self.expr,
            type=self.type,
            valid_expr=merged,
        )

    def __lt__(self, other):
        return self._cmp(other, "lt", "<")

    def __le__(self, other):
        return self._cmp(other, "le", "<=")

    def __gt__(self, other):
        return self._cmp(other, "gt", ">")

    def __ge__(self, other):
        return self._cmp(other, "ge", ">=")

    def __eq__(self, other):
        return self._cmp(other, "eq", "==")

    def __ne__(self, other):
        return self._cmp(other, "ne", "!=")


def auto_name_signals(namespace):
    named_signals = {}
    for var_name, value in namespace.items():
        if isinstance(value, Signal) and value.hw_id:
            value.name = var_name
            named_signals[var_name] = value
        elif isinstance(value, PredicateSignal) and value.hw_id:
            value.dag.node_names[value.hw_id] = var_name
            named_signals[var_name] = value
    return named_signals


if __name__ == "__main__":
    GENERATE_FLOWCHART = True
    GENERATE_WRAPPER_MODULES = False

    latencies = {
        "fp_add": 7,
        "fp_sub": 7,
        "fp_mul": 5,
        "fp_fma": 13,
        "fp_recip": 22,
        "fp_cmp": 1,
        "mem_read": 1,
        "mem_write": 1,
    }

    dag = HardwareDAG(latencies=latencies)

    # Thread-pipeline inputs
    e0 = Signal(dag, name="e0")
    e1 = Signal(dag, name="e1")
    e2 = Signal(dag, name="e2")
    addr = Signal(dag, name="addr", type="addr_t")
    v0_z = Signal(dag, name="v0_z")
    v1_z = Signal(dag, name="v1_z")
    v2_z = Signal(dag, name="v2_z")
    v0_w = Signal(dag, name="v0_w")
    v1_w = Signal(dag, name="v1_w")
    v2_w = Signal(dag, name="v2_w")
    # v0_normal_over_w_x = Signal(dag, name="v0_normal_over_w_x")
    # v1_normal_over_w_x = Signal(dag, name="v1_normal_over_w_x")
    # v2_normal_over_w_x = Signal(dag, name="v2_normal_over_w_x")
    # v0_normal_over_w_y = Signal(dag, name="v0_normal_over_w_y")
    # v1_normal_over_w_y = Signal(dag, name="v1_normal_over_w_y")
    # v2_normal_over_w_y = Signal(dag, name="v2_normal_over_w_y")
    # v0_normal_over_w_z = Signal(dag, name="v0_normal_over_w_z")
    # v1_normal_over_w_z = Signal(dag, name="v1_normal_over_w_z")
    # v2_normal_over_w_z = Signal(dag, name="v2_normal_over_w_z")
    v0_texture_u_over_w = Signal(dag, name="v0_texture_u_over_w")
    v1_texture_u_over_w = Signal(dag, name="v1_texture_u_over_w")
    v2_texture_u_over_w = Signal(dag, name="v2_texture_u_over_w")
    v0_texture_v_over_w = Signal(dag, name="v0_texture_v_over_w")
    v1_texture_v_over_w = Signal(dag, name="v1_texture_v_over_w")
    v2_texture_v_over_w = Signal(dag, name="v2_texture_v_over_w")

    inv_area = Signal(dag, name="inv_area")

    # Arithmetic path
    iw0 = e0 * inv_area
    iw1 = e1 * inv_area
    iw2 = e2 * inv_area

    def interpolate(a, b, c, x, y, z):
        op1 = a * x
        op2 = Signal.fma(b, y, op1)
        result = Signal.fma(c, z, op2)
        return result

    z = interpolate(v0_z, v1_z, v2_z, iw0, iw1, iw2)
    current_z = Signal.mem_read(addr, after=z)
    # Depth test qualifier is computed, but pipeline is not fail-fast gated.
    # Decision whether to use outputs is made at the end of the pipeline.
    comp_z = z <= current_z

    # Fail-fast behavior: if condition is false for a token,
    # all later operations in the graph are discarded for that token.
    # dag.discard_if_false(comp_z)

    # Write the passing depth value back after the compare result is available.
    dag.control_dependencies = [comp_z]
    write_done = Signal.mem_write(addr, z)
    dag.control_dependencies = []
    invW = interpolate(v0_w, v1_w, v2_w, iw0, iw1, iw2)
    w = 1 / invW

    # We don't Do normals (for now at leeast) on the raster step
    # normal_over_w_x = interpolate(
    #     v0_normal_over_w_x, v1_normal_over_w_x, v2_normal_over_w_x, iw0, iw1, iw2
    # )
    # normal_over_w_y = interpolate(
    #     v0_normal_over_w_y, v1_normal_over_w_y, v2_normal_over_w_y, iw0, iw1, iw2
    # )
    # normal_over_w_z = interpolate(
    #     v0_normal_over_w_z, v1_normal_over_w_z, v2_normal_over_w_z, iw0, iw1, iw2
    # )

    texcoord_over_w_u = interpolate(
        v0_texture_u_over_w, v1_texture_u_over_w, v2_texture_u_over_w, iw0, iw1, iw2
    )
    texcoord_over_w_v = interpolate(
        v0_texture_v_over_w, v1_texture_v_over_w, v2_texture_v_over_w, iw0, iw1, iw2
    )

    texcoord_u = texcoord_over_w_u * w
    texcoord_v = texcoord_over_w_v * w

    # Optional naming for generated register labels
    auto_name_signals(locals())

    print("\n--- Running thread pipeline scheduler (II=1) ---")
    result = dag.schedule(ii=1)
    dag.print_schedule(result)

    out_svh = Path(__file__).with_name("thread_pipeline_autogen.svh")
    out_flow = Path(__file__).with_name("thread_pipeline_flowchart.mmd")
    dag.dump_thread_pipeline(result, out_svh)
    if GENERATE_FLOWCHART:
        dag.dump_flowchart(result, out_flow)

    print(f"\nGenerated: {out_svh}")
    if GENERATE_FLOWCHART:
        print(f"Generated: {out_flow}")
    print(f"Final signal expr: {z.expr}")
