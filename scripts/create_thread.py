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
    "fp_depth_func",
    "mux",
    "mem_read",
    "mem_write",
    "fx_color_interpolate",
    "fx_texture_interpolate",
    "fp_to_fx2_23",
}


DEFAULT_LATENCIES = {
    "fp_add": 11,
    "fp_sub": 11,
    "fp_mul": 8,
    "fp_fma": 19,
    "fp_recip": 28,
    # fp_depth_func: input registers, lt/gt/eq, function select.
    "fp_depth_func": 3,
    "mux": 1,
    "mem_read": 1,
    "mem_write": 1,
    # Interpolator latencies follow their RTL pipeline depths.
    "fx_color_interpolate": 6,
    "fx_texture_interpolate": 6,
    # Xilinx conversion wrappers are 2-cycle latency.
    "fp_to_fx2_23": 2,
}

# Output bit-width for each op type (default 32 for fp ops).
_FX_OP_WIDTHS = {
    "fx_color_interpolate": 32,
    "fx_texture_interpolate": 48,
    "fp_to_fx2_23": 25,
}

# Leaf-signal type → bit width.
# Match the handwritten module: per-thread addresses are sized by
# THREAD_ADDR_W, not a hard-coded constant.
_LEAF_TYPE_WIDTHS = {
    "addr_t": "THREAD_ADDR_W",
    "uint8_t": 8,
    "color_argb_t": 32,
    "fx_texture": 18,
    "fx_2_23": 25,
    "depth_func_t": 3,
}

# Constant compare function for each fixed compare kind (depth_func_t mask of {gt, eq, lt}).
_CMP_KIND_FUNC = {
    "lt": "DEPTH_LESS",
    "le": "DEPTH_LEQUAL",
    "gt": "DEPTH_GREATER",
    "ge": "DEPTH_GEQUAL",
    "eq": "DEPTH_EQUAL",
    "ne": "DEPTH_NOTEQUAL",
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
        self.dependency_lead_cycles = {}
        self.node_names = {}
        self.expression_cache = {}
        self.counters = {k: 0 for k in SUPPORTED_OPS}
        self.global_valid_expr = "pipe_en"
        self.control_dependencies = []
        self.op_controls = {}

    @staticmethod
    def _sanitize_sv_name(name: str) -> str:
        return re.sub(r"[^0-9A-Za-z_]", "_", name)

    def _new_node(
        self,
        op_type,
        expr,
        op_symbol="",
        cmp_kind="",
        valid_expr="pipe_en",
    ):
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
        _FP_BINARY = {"fp_add", "fp_sub", "fp_mul"}
        if op_type not in _FP_BINARY:
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

    def add_fma_operation(self, a, b, c, expr, op_type="fp_fma"):
        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(a),
        )
        cache_key = (op_type, expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node(op_type, expr, valid_expr=valid_expr)
        self._add_edges(node_id, (a, b, c), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_texture_interpolation_operation(self, inputs, expr):
        if len(inputs) != 6:
            raise ValueError("Texture interpolation expects three colors and weights")
        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            *(self._input_valid_expr(sig) for sig in inputs),
        )
        cache_key = ("fx_texture_interpolate", expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node("fx_texture_interpolate", expr, valid_expr=valid_expr)
        self._add_edges(node_id, tuple(inputs), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_color_interpolation_operation(self, inputs, expr):
        if len(inputs) != 6:
            raise ValueError("Color interpolation expects three colors and weights")
        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            *(self._input_valid_expr(sig) for sig in inputs),
        )
        cache_key = ("fx_color_interpolate", expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node("fx_color_interpolate", expr, valid_expr=valid_expr)
        self._add_edges(node_id, tuple(inputs), tuple(self.control_dependencies))
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_unary_operation(self, op_type, src, expr):
        if op_type not in (
            "fp_recip",
            "fp_to_fx2_23",
        ):
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

    def add_compare_operation(self, cmp_kind, left, right, expr, func=None):
        """Compare left against right. cmp_kind "func" takes the function from the func operand
        (a depth_func_t signal, the third input edge); the other kinds use a constant function."""
        if cmp_kind not in ("lt", "le", "gt", "ge", "eq", "ne", "func"):
            raise ValueError(f"Unsupported compare kind: {cmp_kind}")
        if (cmp_kind == "func") != (func is not None):
            raise ValueError("A func operand is required exactly for cmp_kind 'func'")

        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(left),
        )
        cache_key = ("fp_depth_func", cmp_kind, expr, valid_expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node(
            "fp_depth_func", expr, cmp_kind=cmp_kind, valid_expr=valid_expr
        )
        operands = (left, right) if func is None else (left, right, func)
        self._add_edges(node_id, operands, tuple(self.control_dependencies))
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

    def add_memory_read_operation(self, addr, expr, after=None, lead_cycles=0):
        valid_expr = self._merge_valid_expr(
            self.global_valid_expr,
            self._input_valid_expr(addr),
        )
        if lead_cycles < 0:
            raise ValueError("Memory read lead_cycles must be non-negative")

        cache_key = ("mem_read", expr, valid_expr, lead_cycles)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        node_id = self._new_node("mem_read", expr, valid_expr=valid_expr)
        inputs = [addr]
        # Optional sequencing edge: force this memory read to happen after a
        # specific signal-producing operation without changing read semantics.
        if isinstance(after, (Signal, PredicateSignal)) and after.hw_id:
            inputs.append(after)
            self.dependency_lead_cycles[(after.hw_id, node_id)] = lead_cycles
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
                lead_cycles = self.dependency_lead_cycles.get((pred, node), 0)
                ready_time = max(
                    ready_time,
                    start_times[pred] + pred_info.latency - lead_cycles,
                )
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
        if isinstance(sig, (Signal, PredicateSignal)) and getattr(sig, "sv_ref", None):
            return sig.sv_ref
        if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id:
            return wire_name_by_node[sig.hw_id]
        if isinstance(sig, (Signal, PredicateSignal)):
            return sig.expr
        return str(sig)

    def _unit_out_wire_name(self, op_type, unit_name):
        if op_type in ("fp_depth_func", "mem_write"):
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

        if op_type == "fp_depth_func":
            for sig in inputs:
                if isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id:
                    return sig
            return inputs[0] if inputs else None

        if (
            op_type
            in (
                "fp_fma",
                "fx_texture_interpolate",
                "fx_color_interpolate",
            )
            and produced_inputs
        ):
            return produced_inputs[-1]

        if op_type in (
            "fp_add",
            "fp_sub",
            "fp_mul",
            "fp_recip",
            "mux",
            "fp_to_fx2_23",
        ):
            if produced_inputs:
                return produced_inputs[-1]

        if op_type == "mem_write":
            if len(inputs) > 1:
                return inputs[1]
            return inputs[0] if inputs else None

        return inputs[0] if inputs else None

    def _op_out_width(self, op_type):
        """Return the output bit-width for a given op type."""
        if op_type in ("fp_depth_func", "mem_write"):
            return 1
        return _FX_OP_WIDTHS.get(op_type, 32)

    def _leaf_axis_base(self, sig):
        raw = getattr(sig, "expr", str(sig))
        return self._sanitize_sv_name(raw)

    def _leaf_struct_field(self, sig):
        raw = getattr(sig, "expr", str(sig))
        # Keep generator leaf names stable while mapping to compact struct fields.
        m_tex = re.fullmatch(r"v([0-2])_texture_([uv])", raw)
        if m_tex:
            return f"v{m_tex.group(1)}_{m_tex.group(2)}"
        return self._sanitize_sv_name(raw)

    def _leaf_data_ref(self, sig):
        # sv_ref carries a pre-formed SV expression (e.g. for zero-latency
        # type conversions like uint8→Q8.8) and is used verbatim as the wire.
        if getattr(sig, "sv_ref", None):
            return sig.sv_ref
        if getattr(sig, "type", "") == "addr_t":
            return "thread_data_buf.addr[THREAD_ADDR_W-1:0]"
        return f"thread_data_buf.{self._leaf_struct_field(sig)}"

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
            width = self._op_out_width(info.op_type)
            lines.append(f"logic [{width-1}:0] {wire};")
            if info.op_type == "fp_depth_func":
                lines.append(f"logic {wire}_valid;")
            if info.op_type == "mem_write":
                lines.append(f"logic {node}_fire;")
        lines.append("")

        lines.append("// ---- Selected outputs ----")
        output_aliases = {
            "u": "texcoord_u",
            "v": "texcoord_v",
            "texcoord_u": "texcoord_u",
            "texcoord_v": "texcoord_v",
            "color": "color",
            "comp_z": "comp_z",
            "addr": "addr",
            "tex_id": "tex_id",
            "texture_mode_u": "texture_mode_u",
            "texture_mode_v": "texture_mode_v",
            "texture_function": "texture_function",
            "sfactor_op": "sfactor_op",
            "dfactor_op": "dfactor_op",
        }
        selected_output_order = (
            "texcoord_u",
            "texcoord_v",
            "addr",
            "tex_id",
            "texture_mode_u",
            "texture_mode_v",
            "texture_function",
            "sfactor_op",
            "dfactor_op",
            "color",
            "comp_z",
        )
        selected_node_by_name = {}
        for node, raw_name in self.node_names.items():
            out_name = output_aliases.get(raw_name)
            if out_name is not None and out_name not in selected_node_by_name:
                selected_node_by_name[out_name] = node

        selected_outputs = []
        for name in selected_output_order:
            if name in selected_node_by_name:
                selected_outputs.append((selected_node_by_name[name], name, None))
            elif name == "addr":
                selected_outputs.append(
                    (
                        None,
                        name,
                        (
                            "THREAD_ADDR_W",
                            "thread_data_buf.addr[THREAD_ADDR_W-1:0]",
                            0,
                        ),
                    )
                )
            elif name == "tex_id":
                selected_outputs.append((None, name, (8, "thread_data_buf.tex_id", 0)))
            elif name == "texture_mode_u":
                selected_outputs.append(
                    (None, name, (1, "thread_data_buf.texture_mode_u", 0))
                )
            elif name == "texture_mode_v":
                selected_outputs.append(
                    (None, name, (1, "thread_data_buf.texture_mode_v", 0))
                )
            elif name == "texture_function":
                selected_outputs.append(
                    (None, name, (3, "thread_data_buf.texture_function", 0))
                )
            elif name in ("sfactor_op", "dfactor_op"):
                selected_outputs.append(
                    (None, name, ("$bits(blend_op_t)", f"thread_data_buf.{name}", 0))
                )

        if selected_outputs:
            for item in selected_outputs:
                node, out_name, meta = item
                if node is not None:
                    src_wire = wire_name_by_node[node]
                    width = self._op_out_width(self.ops[node].op_type)
                    if width == 1:
                        lines.append(f"logic {out_name}_tdata;")
                    else:
                        lines.append(f"logic [{width-1}:0] {out_name}_tdata;")
                    lines.append(f"assign {out_name}_tdata = {src_wire};")
                else:
                    width, src_ref, stage = meta
                    if width == 1:
                        lines.append(f"logic {out_name}_tdata;")
                    else:
                        if isinstance(width, str):
                            lines.append(f"logic [{width}-1:0] {out_name}_tdata;")
                        else:
                            lines.append(f"logic [{width-1}:0] {out_name}_tdata;")
                    lines.append(f"assign {out_name}_tdata = {src_ref};")
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
            if isinstance(sig, Signal) and getattr(sig, "sv_ref", None) is not None:
                t = getattr(sig, "type", "")
                if t in _LEAF_TYPE_WIDTHS:
                    return _LEAF_TYPE_WIDTHS[t]
            if isinstance(sig, Signal) and sig.hw_id:
                return self._op_out_width(self.ops[sig.hw_id].op_type)
            if isinstance(sig, Signal):
                t = getattr(sig, "type", "")
                if t in _LEAF_TYPE_WIDTHS:
                    return _LEAF_TYPE_WIDTHS[t]
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
        leaf_ready_assigns = []
        seen_leaf_ready = set()
        leaf_ready_keys = set()
        consumer_fire_nodes = {
            node
            for node in sorted_ops
            if self.ops[node].op_type in ("fp_depth_func", "mem_read", "mux")
            and len(self.op_inputs[node]) > 0
        }

        def _declare_buffer_signal(name, width):
            if isinstance(width, str):
                if name not in align_decls_seen:
                    align_decls_seen.add(name)
                    align_decls.append(f"logic [{width}-1:0] {name};")
                return
            if width == 1:
                if name not in align_decls_seen:
                    align_decls_seen.add(name)
                    align_decls.append(f"logic {name};")
            else:
                if name not in align_decls_seen:
                    align_decls_seen.add(name)
                    align_decls.append(f"logic [{width-1}:0] {name};")

        # Recorded here and emitted merged (see _merged_delay_lines) once all are known.
        align_delays = []

        def _emit_delay_align(src_ref, dst_ref, width, stages, end_stage):
            _declare_buffer_signal(dst_ref, width)
            align_delays.append(
                (
                    src_ref,
                    dst_ref,
                    width,
                    end_stage - stages,
                    stages,
                    "1'b1",
                    f"u_{dst_ref}_data_delay",
                )
            )

        # Track alignment delays to find max alignment depth
        alignment_delays = {}
        # For leaf sources, allow emitting incremental delay chains from an
        # already-aligned tap to reduce delay_pipe storage.
        leaf_align_by_src = {}

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
                    delay_src_ref = src_ref
                    delay_stages = extra_delay

                    # If this is a leaf input and we already created a shorter
                    # alignment for the same source, chain from it.
                    if not (isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id):
                        leaf_key = (src_ref, width, src_tag)
                        prior = leaf_align_by_src.get(leaf_key, [])
                        best = None
                        for dly, aligned_ref in prior:
                            if dly < extra_delay and (best is None or dly > best[0]):
                                best = (dly, aligned_ref)
                        if best is not None:
                            delay_src_ref = best[1]
                            delay_stages = extra_delay - best[0]

                    buf_name = f"align_{src_tag}_to_{dst}_i{idx}_d{extra_delay}"
                    input_ref_by_edge[(dst, idx)] = buf_name
                    input_valid_ref_by_edge[(dst, idx)] = f"{buf_name}_valid"
                    _declare_buffer_signal(buf_name, width)
                    _emit_delay_align(
                        delay_src_ref, buf_name, width, delay_stages, dst_start
                    )
                    alignment_delays[buf_name] = extra_delay

                    if not (isinstance(sig, (Signal, PredicateSignal)) and sig.hw_id):
                        leaf_key = (src_ref, width, src_tag)
                        leaf_align_by_src.setdefault(leaf_key, []).append(
                            (extra_delay, buf_name)
                        )
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

        # Note: consumer fire wiring will be generated later after valid_pipe updates.
        # valid_pipe is declared in rtl/thread.sv outside this autogenerated block.

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
        # mem_read/mem_write fire on their start stage; others use start+1.
        valid_ref_by_node = {
            node: (
                f"valid_pipe[{start_times[node]}]"
                if self.ops[node].op_type in ("mem_read", "mem_write")
                else f"valid_pipe[{start_times[node] + 1}]"
            )
            for node in sorted_ops
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
            lines.extend(self._merged_delay_lines(align_delays, "align"))
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
                lines.append("    .aclk(clk), .aclken(pipe_en_internal),")
                lines.append(f"    // .valid_in({valid_in}),")
                lines.append("    .valid_in(),")
                lines.append(f"    .a({a}), .b({b}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_sub":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                lines.append(f"fp_sub #(.LATENCY({info.latency})) u_{unit} (")
                lines.append("    .aclk(clk), .aclken(pipe_en_internal),")
                lines.append(f"    // .valid_in({valid_in}),")
                lines.append("    .valid_in(),")
                lines.append(f"    .a({a}), .b({b}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_mul":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                lines.append(f"fp_mul #(.LATENCY({info.latency})) u_{unit} (")
                lines.append("    .aclk(clk), .aclken(pipe_en_internal),")
                lines.append(f"    // .valid_in({valid_in}),")
                lines.append("    .valid_in(),")
                lines.append(f"    .a({a}), .b({b}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_fma":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                c = input_ref_by_edge[(node, 2)]
                lines.append(f"fp_fma #(.LATENCY({info.latency})) u_{unit} (")
                lines.append("    .aclk(clk), .aclken(pipe_en_internal),")
                lines.append(f"    // .valid_in({valid_in}),")
                lines.append("    .valid_in(),")
                lines.append(f"    .a({a}), .b({b}), .c({c}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_recip":
                a = input_ref_by_edge[(node, 0)]
                lines.append(f"fp_recip #(.LATENCY({info.latency})) u_{unit} (")
                lines.append("    .aclk(clk), .aclken(pipe_en_internal),")
                lines.append(f"    // .valid_in({valid_in}),")
                lines.append("    .valid_in(),")
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
                    lines.append("assign z_rd_en = pipe_en_internal;")
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
                    lines.append(
                        f"assign {node}_fire = valid_pipe[{start_times[node]}];"
                    )
                    if control_terms:
                        lines.append(
                            f"assign {out_wire}[0] = {' && '.join(control_terms)};"
                        )
                        wr_en_expr = f"{node}_fire && {out_wire}[0]"
                    else:
                        lines.append(f"assign {out_wire}[0] = 1'b1;")
                        wr_en_expr = f"{node}_fire"
                    lines.append(f"assign z_wr_en = {wr_en_expr} && pipe_en_internal;")
                    lines.append(f"assign z_wr_addr = {addr};")
                    lines.append(f"assign z_wr_data = {data};")
            elif info.op_type == "fp_depth_func":
                a = input_ref_by_edge[(node, 0)]
                b = input_ref_by_edge[(node, 1)]
                # Every compare kind uses fp_depth_func: "func" takes the per-token function from its
                # third input, the fixed kinds a constant one.
                if info.cmp_kind == "func":
                    func = f"depth_func_t'({input_ref_by_edge[(node, 2)]})"
                else:
                    func = _CMP_KIND_FUNC[info.cmp_kind]
                lines.append(f"fp_depth_func u_{unit} (")
                lines.append("    .aclk(clk),")
                lines.append("    .aclken(pipe_en_internal),")
                lines.append(f"    .s_axis_a({a}),")
                lines.append(f"    .s_axis_b({b}),")
                lines.append(f"    .func({func}),")
                lines.append(f"    .m_axis_res({out_wire}[0])")
                lines.append(");")
            elif info.op_type == "fx_texture_interpolate":
                colors = [input_ref_by_edge[(node, i)] for i in (0, 2, 4)]
                weights = [input_ref_by_edge[(node, i)] for i in (1, 3, 5)]
                lines.append(f"fx_texture_interpolator u_{unit} (")
                lines.append("    .clk(clk), .clken(pipe_en_internal),")
                lines.append(f"    .coord0({colors[0]}), .weight0({weights[0]}),")
                lines.append(f"    .coord1({colors[1]}), .weight1({weights[1]}),")
                lines.append(f"    .coord2({colors[2]}), .weight2({weights[2]}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fx_color_interpolate":
                colors = [input_ref_by_edge[(node, i)] for i in (0, 2, 4)]
                weights = [input_ref_by_edge[(node, i)] for i in (1, 3, 5)]
                lines.append(f"fx_color_interpolator u_{unit} (")
                lines.append("    .clk(clk), .clken(pipe_en_internal),")
                lines.append(f"    .color0({colors[0]}), .weight0({weights[0]}),")
                lines.append(f"    .color1({colors[1]}), .weight1({weights[1]}),")
                lines.append(f"    .color2({colors[2]}), .weight2({weights[2]}),")
                lines.append(f"    .result({out_wire})")
                lines.append(");")
            elif info.op_type == "fp_to_fx2_23":
                a = input_ref_by_edge[(node, 0)]
                lines.append(f"fp_to_fx2_23 #(.LATENCY({info.latency})) u_{unit} (")
                lines.append("    .aclk(clk), .aclken(pipe_en_internal),")
                lines.append(f"    .s_axis_a_tvalid({valid_in}),")
                lines.append(f"    .s_axis_a_tdata({a}),")
                lines.append("    .m_axis_result_tvalid(),")
                lines.append(f"    .m_axis_result_tdata({out_wire})")
                lines.append(");")
        lines.append("")

        # ---- Output skid buffer ----
        lines.append("// ---- Output skid buffer ----")
        # Collect selected output names and widths in order. Metadata fields are
        # ingress token values and therefore must be treated as stage 0 sources,
        # so they receive the same final-stage delay as the handwritten RTL.
        out_fields = []
        for item in selected_outputs:
            node, out_name, meta = item
            if node is not None:
                width = self._op_out_width(self.ops[node].op_type)
                stage = start_times[node] + self.ops[node].latency
                out_fields.append((out_name, width, stage, f"{out_name}_tdata"))
            else:
                width, _, stage = meta
                if isinstance(width, str):
                    width_value = width
                else:
                    width_value = width
                out_fields.append((out_name, width_value, stage, f"{out_name}_tdata"))

        if out_fields:
            final_out_stage = max(stage for _, _, stage, _ in out_fields)
            bits_terms = " + ".join(
                f"$bits({name}_tdata)" for name, _, _, _ in out_fields
            )
            lines.append(f"localparam int OUTBUNDLEWIDTH = {bits_terms};")
            lines.append("logic [OUTBUNDLEWIDTH-1:0] output_bundle_tdata;")
            lines.append("logic output_bundle_tvalid;")
            lines.append("(*max_fanout = 250*) logic output_bundle_s_axis_tready;")
            lines.append("logic [OUTBUNDLEWIDTH-1:0] output_bundle_buf_tdata;")
            lines.append("logic output_bundle_buf_tvalid;")
            lines.append("logic output_bundle_buf_tready;")
            lines.append("")
            bundle_data_refs = []
            bundle_delays = []
            for out_name, width, stage, src_ref in out_fields:
                delay_to_final = final_out_stage - stage
                if delay_to_final > 0:
                    aligned_name = f"{out_name}_bundle_tdata"
                    reset_signal = "rst_reg" if out_name == "comp_z" else "1'b1"
                    if width == 1:
                        lines.append(f"logic {aligned_name};")
                    else:
                        if isinstance(width, str):
                            lines.append(f"logic [{width}-1:0] {aligned_name};")
                        else:
                            lines.append(f"logic [{width-1}:0] {aligned_name};")
                    bundle_delays.append(
                        (
                            src_ref,
                            aligned_name,
                            width,
                            stage,
                            delay_to_final,
                            reset_signal,
                            f"u_align_{out_name}_to_output_bundle_d{delay_to_final}",
                        )
                    )
                    bundle_data_refs.append(aligned_name)
                else:
                    bundle_data_refs.append(src_ref)

            if bundle_delays:
                lines.extend(self._merged_delay_lines(bundle_delays, "bundle"))
                lines.append("")

            pack_fields = ", ".join(bundle_data_refs)
            lines.append(f"assign output_bundle_tdata = {{{pack_fields}}};")
            lines.append(
                f"assign output_bundle_tvalid = valid_pipe[{final_out_stage}];"
            )
            lines.append("")
            lines.append("axis_skid_buffer #(")
            lines.append("    .WIDTH(OUTBUNDLEWIDTH)")
            lines.append(") u_output_bundle_skid (")
            lines.append("    .aclk(clk), .aresetn(rst_reg),")
            lines.append("    .s_axis_tdata(output_bundle_tdata),")
            lines.append("    .s_axis_tvalid(output_bundle_tvalid),")
            lines.append("    .s_axis_tready(output_bundle_s_axis_tready),")
            lines.append("    .m_axis_tdata(output_bundle_buf_tdata),")
            lines.append("    .m_axis_tvalid(output_bundle_buf_tvalid),")
            lines.append("    .m_axis_tready(output_bundle_buf_tready)")
            lines.append(");")
            lines.append("")
            lines.append("// Pipeline control: clken = output skid can accept")
            lines.append("assign pipe_en_internal = output_bundle_s_axis_tready;")
            lines.append("assign input_bundle_m_axis_tready = pipe_en_internal;")
            lines.append("assign ready_out = input_bundle_s_axis_tready;")
        lines.append("")

        Path(output_path).write_text("\n".join(lines) + "\n", encoding="utf-8")

    @staticmethod
    def _merged_delay_lines(delays, prefix):
        """Emit delay_pipes for (src, dst, width, start, stages, reset, instance) records.

        A source already delayed by the same depth reuses that delay's output. Delays from the
        same start stage to the same end stage, with the same reset, share one wide delay_pipe.
        """
        lines = []
        dst_by_source = {}
        groups = {}
        for src, dst, width, start, stages, reset, instance in delays:
            key = (src, stages, reset)
            if key in dst_by_source:
                lines.append(f"assign {dst} = {dst_by_source[key]};")
                continue
            dst_by_source[key] = dst
            groups.setdefault((start, stages, reset), []).append(
                (src, dst, width, instance)
            )

        for (start, stages, reset), members in groups.items():
            if len(members) == 1:
                src, dst, width, instance = members[0]
                lines.append(
                    f"delay_pipe #(.WIDTH({width}), .STAGES({stages})) {instance} (.clk(clk), .rst_n({reset}), .clken(pipe_en_internal), .data_in({src}), .data_out({dst}));"
                )
                continue
            numeric = sum(width for _, _, width, _ in members if isinstance(width, int))
            symbolic = [width for _, _, width, _ in members if not isinstance(width, int)]
            width = " + ".join(symbolic + ([str(numeric)] if numeric else []))
            bus = f"{prefix}_s{start}_d{stages}" + ("" if reset == "1'b1" else "_rst")
            sources = ", ".join(src for src, _, _, _ in members)
            dsts = ", ".join(dst for _, dst, _, _ in members)
            lines.append(f"logic [{width}-1:0] {bus}_in, {bus}_out;")
            lines.append(f"assign {bus}_in = {{{sources}}};")
            lines.append(
                f"delay_pipe #(.WIDTH({width}), .STAGES({stages})) u_{bus} (.clk(clk), .rst_n({reset}), .clken(pipe_en_internal), .data_in({bus}_in), .data_out({bus}_out));"
            )
            lines.append(f"assign {{{dsts}}} = {bus}_out;")
        return lines

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
        sv_ref=None,
    ):
        self.dag = dag
        self.hw_id = hw_id
        self.type = type
        self.valid_expr = valid_expr
        self.sv_ref = sv_ref  # optional pre-formed SV wire expression
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
        if not isinstance(other, Signal):
            raise TypeError("Binary operations require Signal operands")
        if self.dag is not other.dag:
            raise ValueError("Signals must belong to the same DAG")
        a_type = getattr(self, "type", "float_t")
        b_type = getattr(other, "type", "float_t")
        if a_type != b_type:
            raise TypeError(f"Unsupported mul type combination: {a_type} * {b_type}")
        op, res_type = "fp_mul", a_type
        expr = f"({self.expr} * {other.expr})"
        node_id = self.dag.add_binary_operation(op, self, other, expr, "*")
        return Signal(
            self.dag,
            hw_id=node_id,
            expr=expr,
            type=res_type,
            valid_expr=self.dag.ops[node_id].valid_expr,
        )

    def as_fx2_23(self):
        """Convert fp32 bits to Q2.23 fixed point using Xilinx wrapper."""
        if self.type != "float_t":
            raise TypeError("as_fx2_23 is only supported for float_t signals")
        expr = f"fp_to_fx2_23({self.expr})"
        node_id = self.dag.add_unary_operation("fp_to_fx2_23", self, expr)
        return Signal(
            self.dag,
            hw_id=node_id,
            expr=expr,
            type="fx_2_23",
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
    def texture_interpolate(color0, weight0, color1, weight1, color2, weight2):
        colors = (color0, color1, color2)
        weights = (weight0, weight1, weight2)
        inputs = (color0, weight0, color1, weight1, color2, weight2)
        if any(not isinstance(sig, Signal) for sig in inputs):
            raise TypeError("texture_interpolate expects Signal operands")
        if any(sig.dag is not color0.dag for sig in inputs):
            raise ValueError("texture_interpolate signals must belong to the same DAG")
        if any(sig.type != "fx_texture" for sig in colors):
            raise TypeError("texture interpolation colors must be fx_texture")
        if any(sig.type != "fx_2_23" for sig in weights):
            raise TypeError("texture interpolation weights must be fx_2_23")

        expr = (
            f"texture_interpolate({color0.expr}, {weight0.expr}, "
            f"{color1.expr}, {weight1.expr}, {color2.expr}, {weight2.expr})"
        )
        node_id = color0.dag.add_texture_interpolation_operation(inputs, expr)
        return Signal(
            color0.dag,
            hw_id=node_id,
            expr=expr,
            type="fx_texture_accum",
            valid_expr=color0.dag.ops[node_id].valid_expr,
        )

    @staticmethod
    def color_interpolate(color0, weight0, color1, weight1, color2, weight2):
        colors = (color0, color1, color2)
        weights = (weight0, weight1, weight2)
        inputs = (color0, weight0, color1, weight1, color2, weight2)
        if any(not isinstance(sig, Signal) for sig in inputs):
            raise TypeError("color_interpolate expects Signal operands")
        if any(sig.dag is not color0.dag for sig in inputs):
            raise ValueError("color_interpolate signals must belong to the same DAG")
        if any(sig.type != "color_argb_t" for sig in colors):
            raise TypeError("color interpolation inputs must be packed color_argb_t")
        if any(sig.type != "fx_2_23" for sig in weights):
            raise TypeError("color interpolation weights must be fx_2_23")

        expr = (
            f"color_interpolate({color0.expr}, {weight0.expr}, "
            f"{color1.expr}, {weight1.expr}, {color2.expr}, {weight2.expr})"
        )
        node_id = color0.dag.add_color_interpolation_operation(inputs, expr)
        return Signal(
            color0.dag,
            hw_id=node_id,
            expr=expr,
            type="color_argb_t",
            valid_expr=color0.dag.ops[node_id].valid_expr,
        )

    @staticmethod
    def fma(a, b, c):
        if (
            not isinstance(a, Signal)
            or not isinstance(b, Signal)
            or not isinstance(c, Signal)
        ):
            raise TypeError("fma requires Signal operands")
        if a.dag is not b.dag or a.dag is not c.dag:
            raise ValueError("fma signals must belong to the same DAG")

        if a.type != b.type or a.type != c.type:
            raise TypeError("fma requires matching signal types")

        op_type = "fp_fma"

        expr = f"fma({a.expr}, {b.expr}, {c.expr})"
        node_id = a.dag.add_fma_operation(a, b, c, expr, op_type=op_type)
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
    def depth_compare(a, b, func):
        """a <func> b, with func a per-token depth_func_t signal (programmable depth test)."""
        a._check_binary(b)
        if not isinstance(func, Signal) or func.type != "depth_func_t":
            raise TypeError("depth_compare expects a depth_func_t function signal")
        if func.dag is not a.dag:
            raise ValueError("depth_compare signals must belong to the same DAG")
        expr = f"depth_compare({a.expr}, {b.expr}, {func.expr})"
        node_id = a.dag.add_compare_operation("func", a, b, expr, func=func)
        return PredicateSignal(
            a.dag,
            hw_id=node_id,
            expr=expr,
            valid_expr=a.dag.ops[node_id].valid_expr,
        )

    @staticmethod
    def mem_read(addr, after=None, lead_cycles=0):
        if not isinstance(addr, Signal):
            raise TypeError("mem_read requires a Signal address operand")
        expr = f"mem_read({addr.expr})"
        node_id = addr.dag.add_memory_read_operation(
            addr, expr, after=after, lead_cycles=lead_cycles
        )
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
    latencies = {
        "fp_add": 11,
        "fp_sub": 11,
        "fp_mul": 8,
        "fp_fma": 16,
        "fp_recip": 29,
        "fp_depth_func": 3,
        "fp_to_fx2_23": 3,
        "mem_read": 3,
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
    # Texture channels arrive as the narrower upstream fixed-point format.
    v0_texture_u = Signal(dag, name="v0_texture_u", type="fx_texture")
    v1_texture_u = Signal(dag, name="v1_texture_u", type="fx_texture")
    v2_texture_u = Signal(dag, name="v2_texture_u", type="fx_texture")
    v0_texture_v = Signal(dag, name="v0_texture_v", type="fx_texture")
    v1_texture_v = Signal(dag, name="v1_texture_v", type="fx_texture")
    v2_texture_v = Signal(dag, name="v2_texture_v", type="fx_texture")
    # Packed ARGB colors map directly onto thread_data_in_t.v*_color.
    v0_color = Signal(dag, name="v0_color", type="color_argb_t")
    v1_color = Signal(dag, name="v1_color", type="color_argb_t")
    v2_color = Signal(dag, name="v2_color", type="color_argb_t")

    inv_area = Signal(dag, name="inv_area")
    # Per-triangle depth test function (depth_func_t).
    depth_func = Signal(dag, name="depth_func", type="depth_func_t")

    # Arithmetic path
    iw0 = e0 * inv_area
    iw1 = e1 * inv_area
    iw2 = e2 * inv_area

    def interpolate(a, b, c, x, y, z):
        op1 = a * x
        op2 = Signal.fma(b, y, op1)
        return Signal.fma(c, z, op2)

    invW = interpolate(v0_w, v1_w, v2_w, iw0, iw1, iw2)
    w = 1 / invW

    t0_fp = w * (v0_w * iw0)
    t1_fp = w * (v1_w * iw1)
    t2_fp = w * (v2_w * iw2)

    t0 = t0_fp.as_fx2_23()
    t1 = t1_fp.as_fx2_23()
    t2 = t2_fp.as_fx2_23()

    # Interpolate u, v
    u = Signal.texture_interpolate(v0_texture_u, t0, v1_texture_u, t1, v2_texture_u, t2)
    v = Signal.texture_interpolate(v0_texture_v, t0, v1_texture_v, t1, v2_texture_v, t2)

    # Interpolate all four packed color channels in one fixed-latency unit.
    color = Signal.color_interpolate(v0_color, t0, v1_color, t1, v2_color, t2)

    z = interpolate(v0_z, v1_z, v2_z, iw0, iw1, iw2)
    current_z = Signal.mem_read(addr, after=z, lead_cycles=1)
    # Depth test qualifier is computed, but pipeline is not fail-fast gated.
    # Decision whether to use outputs is made at the end of the pipeline.
    comp_z = Signal.depth_compare(z, current_z, depth_func)

    # Fail-fast behavior: if condition is false for a token,
    # all later operations in the graph are discarded for that token.
    # dag.discard_if_false(comp_z)

    # Write the passing depth value back after the compare result is available.
    dag.control_dependencies = [comp_z]
    write_done = Signal.mem_write(addr, z)
    dag.control_dependencies = []

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

    # texcoord_over_w_u = interpolate(
    #     v0_texture_u_over_w, v1_texture_u_over_w, v2_texture_u_over_w, iw0, iw1, iw2
    # )
    # texcoord_over_w_v = interpolate(
    #     v0_texture_v_over_w, v1_texture_v_over_w, v2_texture_v_over_w, iw0, iw1, iw2
    # )

    # texcoord_u = texcoord_over_w_u * w
    # texcoord_v = texcoord_over_w_v * w

    # Optional naming for generated register labels
    auto_name_signals(locals())

    print("\n--- Running thread pipeline scheduler (II=1) ---")
    result = dag.schedule(ii=1)
    dag.print_schedule(result)

    out_svh = (
        Path(__file__).resolve().parent.parent
        / "rtl"
        / "generated"
        / "thread_pipeline_autogen.svh"
    )
    dag.dump_thread_pipeline(result, out_svh)

    print(f"\nGenerated: {out_svh}")
    print(f"Final signal expr: {z.expr}")
