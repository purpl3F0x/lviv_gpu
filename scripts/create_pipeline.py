import heapq
import re
from datetime import datetime, timedelta
from pathlib import Path

from ortools.sat.python import cp_model


class HardwareDAG:
    def __init__(self, latencies, use_separate_add_sub=False, drop_named_signals=None):
        """
        Initialize the DAG.

        Args:
            latencies: Dictionary of operation latencies
            use_separate_add_sub: If True, use separate fp_add and fp_sub units.
                                 If False (default), use unified fp_add_sub with toggle.
            drop_named_signals: List/set of signal names to drop (use temp regs instead of
                              named regs). If None (default), keep all named signals.
        """
        self.ops = {}
        self.dependencies = []
        self.latencies = latencies
        self.node_names = {}
        self.use_separate_add_sub = use_separate_add_sub
        self.drop_named_signals = (
            set(drop_named_signals) if drop_named_signals else set()
        )
        self.counters = {
            "fp_add_sub": 0,
            "fp_add": 0,
            "fp_sub": 0,
            "fp_mul": 0,
            "int16_add_sub": 0,
            "int16_mul": 0,
            "fp_recip": 0,
            "fp32_to_int16": 0,
            "tri_bb_min_max": 0,
            "fp_min_2": 0,
            "fp_max_2": 0,
            "fp_add_half_fast": 0,
        }
        # Add a cache to remember already generated expressions
        self.expression_cache = {}
        self.op_inputs = {}

    # Binary operations (Add, Sub, Mult)
    def add_operation(self, op_type, left_node, right_node, expr, op_symbol=None):
        # Check if this exact mathematical expression already exists in hardware
        cache_key = (op_type, expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        self.counters[op_type] += 1
        node_id = f"{op_type}_{self.counters[op_type]}"
        # Store the expression alongside the hardware type, latency, and operator kind.
        self.ops[node_id] = (op_type, self.latencies[op_type], expr, op_symbol)
        self.op_inputs[node_id] = (left_node, right_node)

        if left_node.hw_id:
            self.dependencies.append((left_node.hw_id, node_id))
        if right_node.hw_id:
            self.dependencies.append((right_node.hw_id, node_id))

        # Cache the resulting hardware node for future reuse
        self.expression_cache[cache_key] = node_id
        return node_id

    # Unary operations (Reciprocal, Floor, Ceil)
    def add_unary_operation(self, op_type, node, expr):
        # Check if this exact mathematical expression already exists in hardware
        cache_key = (op_type, expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        self.counters[op_type] += 1
        node_id = f"{op_type}_{self.counters[op_type]}"
        self.ops[node_id] = (op_type, self.latencies[op_type], expr)
        self.op_inputs[node_id] = (node,)

        if node.hw_id:
            self.dependencies.append((node.hw_id, node_id))

        # Cache the resulting hardware node for future reuse
        self.expression_cache[cache_key] = node_id
        return node_id

    # Ternary operations (e.g., MIN_MAX_3)
    def add_ternary_operation(self, op_type, left_node, mid_node, right_node, expr):
        # Check if this exact mathematical expression already exists in hardware
        cache_key = (op_type, expr)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        self.counters[op_type] += 1
        node_id = f"{op_type}_{self.counters[op_type]}"
        # Store the expression alongside the operation type and latency
        self.ops[node_id] = (op_type, self.latencies[op_type], expr)
        self.op_inputs[node_id] = (left_node, mid_node, right_node)

        if left_node.hw_id:
            self.dependencies.append((left_node.hw_id, node_id))
        if mid_node.hw_id:
            self.dependencies.append((mid_node.hw_id, node_id))
        if right_node.hw_id:
            self.dependencies.append((right_node.hw_id, node_id))

        # Cache the resulting hardware node for future reuse
        self.expression_cache[cache_key] = node_id
        return node_id

    def add_tri_bb_min_max_operation(
        self, left_node, mid_node, right_node, expr_key, min_expr, max_expr
    ):
        # Check if this exact input triple already exists in hardware
        cache_key = ("tri_bb_min_max", expr_key)
        if cache_key in self.expression_cache:
            return self.expression_cache[cache_key]

        self.counters["tri_bb_min_max"] += 1
        node_id = f"tri_bb_min_max{self.counters['tri_bb_min_max']}"
        # Store both outputs on the same hardware node.
        self.ops[node_id] = (
            "tri_bb_min_max",
            self.latencies.get("tri_bb_min_max", 5),
            min_expr,
            max_expr,
        )
        self.op_inputs[node_id] = (left_node, mid_node, right_node)

        if left_node.hw_id:
            self.dependencies.append((left_node.hw_id, node_id))
        if mid_node.hw_id:
            self.dependencies.append((mid_node.hw_id, node_id))
        if right_node.hw_id:
            self.dependencies.append((right_node.hw_id, node_id))

        self.expression_cache[cache_key] = node_id
        return node_id

    def add_fast_half_add_to_rounded_operation(self, node, expr):
        return self.add_unary_operation("fp_add_half_fast", node, expr)

    @staticmethod
    def _sanitize_sv_name(name):
        return re.sub(r"[^0-9A-Za-z_]", "_", name)

    @staticmethod
    def _leaf_expr_to_rtl(expr):
        leaf_map = {
            "v0.x": "v0_reg.x",
            "v0.y": "v0_reg.y",
            "v1.x": "v1_reg.x",
            "v1.y": "v1_reg.y",
            "v2.x": "v2_reg.x",
            "v2.y": "v2_reg.y",
            "binMinX": "binMinX",
            "binMaxX": "binMaxX",
            "binMinY": "binMinY",
            "binMaxY": "binMaxY",
        }
        return leaf_map.get(expr, expr)

    def _assign_unit_indices(self, sorted_ops, start_times, hw_limits):
        """Assign each op to a concrete hardware instance index."""
        op_unit_idx = {}
        unit_heaps = {}
        unit_count = {}

        for op in sorted_ops:
            hw_type = self.ops[op][0]
            if hw_type not in hw_limits:
                continue

            start_t = start_times[op]
            end_t = start_t + self.ops[op][1]
            limit = hw_limits.get(hw_type, 1)

            heap = unit_heaps.setdefault(hw_type, [])
            created = unit_count.get(hw_type, 0)

            inst_idx = None
            if heap and heap[0][0] <= start_t:
                _, inst_idx = heapq.heappop(heap)

            if inst_idx is None:
                if created < limit:
                    created += 1
                    unit_count[hw_type] = created
                    inst_idx = created
                else:
                    _, inst_idx = heapq.heappop(heap)

            heapq.heappush(heap, (end_t, inst_idx))
            op_unit_idx[op] = inst_idx

        return op_unit_idx, unit_count

    @staticmethod
    def _consumer_input_port(hw_type, input_idx):
        port_map = {
            "fp_add_sub": ["a", "b"],
            "fp_add": ["a", "b"],
            "fp_sub": ["a", "b"],
            "fp_mul": ["a", "b"],
            "fp_recip": ["in"],
            "fp32_to_int16": ["in"],
            "tri_bb_min_max": ["a", "b", "c"],
            "fp_min_2": ["a", "b"],
            "fp_max_2": ["a", "b"],
            "fp_add_half_fast": ["in"],
            "int16_add_sub": ["a", "b"],
        }
        ports = port_map.get(hw_type, [])
        if 0 <= input_idx < len(ports):
            return ports[input_idx]
        return None

    def _build_preferred_temp_binding(
        self,
        sorted_ops,
        start_times,
        hw_limits,
        consumers,
    ):
        """
        Build preferred register names for nodes that can directly target
        a single consumer unit input register.
        """
        op_unit_idx, _ = self._assign_unit_indices(sorted_ops, start_times, hw_limits)
        preferred_reg_by_node = {}

        for node_id in self.ops:
            node_name = self.node_names.get(node_id, "")

            should_use_temp = False
            if not node_name:
                should_use_temp = True
            elif " / " in node_name:
                parts = [s.strip() for s in node_name.split(" / ")]
                should_use_temp = any(part in self.drop_named_signals for part in parts)
            elif node_name in self.drop_named_signals:
                should_use_temp = True

            if not should_use_temp:
                continue

            # tri_bb_min_max has two logical outputs; keep pooled temps for safety.
            if self.ops[node_id][0] == "tri_bb_min_max":
                continue

            node_consumers = consumers.get(node_id, [])
            if len(node_consumers) != 1:
                continue

            consumer = node_consumers[0]
            consumer_hw = self.ops[consumer][0]
            if consumer_hw not in hw_limits:
                continue

            inputs = self.op_inputs.get(consumer, tuple())
            input_idx = None
            for idx, sig in enumerate(inputs):
                if isinstance(sig, Signal) and sig.hw_id == node_id:
                    input_idx = idx
                    break

            if input_idx is None:
                continue

            port = self._consumer_input_port(consumer_hw, input_idx)
            inst_idx = op_unit_idx.get(consumer)
            if not port or inst_idx is None:
                continue

            preferred = f"{consumer_hw}_{inst_idx}_{port}_src_reg"
            preferred_reg_by_node[node_id] = preferred

        return preferred_reg_by_node

    def dump_raster_frontend_blocks(
        self,
        start_times,
        hw_limits,
        temp_register_by_node,
        output_path,
        op_unit_idx=None,
        unit_count=None,
    ):
        sorted_ops = sorted(self.ops.keys(), key=lambda x: start_times[x])

        if op_unit_idx is None or unit_count is None:
            op_unit_idx, unit_count = self._assign_unit_indices(
                sorted_ops, start_times, hw_limits
            )

        # Register names: named signals keep names (unless in drop_named_signals list),
        # unnamed signals use allocated tmp regs.
        reg_name_by_node = {}
        tri_reg_pair_by_node = {}
        reg_width_by_name = {}
        for op in sorted_ops:
            op_type = self.ops[op][0]
            node_name = self.node_names.get(op, "")

            # Check if this signal (or any part of it) should be dropped
            should_drop = False
            if " / " in node_name:
                # Multi-output signal: drop if ANY part is in drop_named_signals
                parts = [s.strip() for s in node_name.split(" / ")]
                should_drop = any(part in self.drop_named_signals for part in parts)
            elif node_name and node_name in self.drop_named_signals:
                should_drop = True

            if should_drop:
                node_name = ""

            if " / " in node_name and not should_drop:
                a, b = node_name.split(" / ", 1)
                a_reg = f"{self._sanitize_sv_name(a.strip())}_reg"
                b_reg = f"{self._sanitize_sv_name(b.strip())}_reg"
                tri_reg_pair_by_node[op] = (a_reg, b_reg)
                reg_name_by_node[op] = a_reg
                reg_width_by_name[a_reg] = 32
                reg_width_by_name[b_reg] = 32
            elif node_name:
                reg_name_by_node[op] = (
                    f"{self._sanitize_sv_name(node_name.strip())}_reg"
                )
                reg_width_by_name[reg_name_by_node[op]] = (
                    16
                    if op_type in ("fp32_to_int16", "int16_add_sub", "int16_mul")
                    else 32
                )
            else:
                reg_name_by_node[op] = temp_register_by_node.get(
                    op, f"{self._sanitize_sv_name(op)}_reg"
                )
                reg_width_by_name[reg_name_by_node[op]] = (
                    16 if reg_name_by_node[op].startswith("stmp") else 32
                )
                # For dropped tri_bb_min_max, also record the max output temp register
                if op_type == "tri_bb_min_max":
                    max_reg = temp_register_by_node.get(
                        f"{op}__max_out", f"{self._sanitize_sv_name(op)}_max_reg"
                    )
                    tri_reg_pair_by_node[op] = (reg_name_by_node[op], max_reg)
                    reg_width_by_name[max_reg] = (
                        16 if max_reg.startswith("stmp") else 32
                    )

        temp_regs = sorted(
            {
                reg_name_by_node[op]
                for op in sorted_ops
                if (
                    self.node_names.get(op, "") in self.drop_named_signals
                    or op not in self.node_names
                )
                and (
                    reg_name_by_node[op].startswith("tmp")
                    or reg_name_by_node[op].startswith("stmp")
                )
            }
        )

        def signal_to_rtl(signal_obj):
            if signal_obj.hw_id:
                prod = signal_obj.hw_id
                if self.ops.get(prod, (None,))[0] == "tri_bb_min_max":
                    pair = tri_reg_pair_by_node.get(prod)
                    if pair:
                        if signal_obj.expr.startswith("ceil("):
                            return pair[1]
                        return pair[0]
                return reg_name_by_node[prod]
            return self._leaf_expr_to_rtl(signal_obj.expr)

        launch_by_cycle = {}
        latch_by_cycle = {}

        for op in sorted_ops:
            hw_type, lat = self.ops[op][0], self.ops[op][1]
            if hw_type not in hw_limits:
                continue
            start_t = start_times[op]
            launch_by_cycle.setdefault(start_t, []).append(op)
            latch_by_cycle.setdefault(start_t + lat, []).append(op)

        lines = []
        lines.append("// AUTO-GENERATED FROM scripts/create_pipeline.py")
        lines.append(
            "// Paste sections into raster_frontend.sv (instantiations + CALC FSMs)."
        )
        lines.append("")

        lines.append("// Pipelined registers generated by schedule (named + temp)")
        for reg in sorted(reg_width_by_name.keys()):
            w = reg_width_by_name[reg]
            lines.append(f"logic [{w-1}:0] {reg};")
        lines.append("")

        lines.append(
            "// ---------------- Unit Declarations + Instantiations ----------------"
        )
        for hw_type in sorted(unit_count.keys()):
            count = unit_count[hw_type]
            for idx in range(1, count + 1):
                if hw_type == "fp_add_sub":
                    base = f"fp_add_sub_{idx}"
                    lines.append(f"logic [31:0] {base}_a, {base}_b, {base}_res;")
                    lines.append(f"logic {base}_op, {base}_valid_in;")
                    lines.append(
                        f"fp_add_sub #(.LATENCY({self.latencies[hw_type]})) u_{base} ("
                    )
                    lines.append("    .aclk    (clk),")
                    lines.append("    .aresetn (rst_n),")
                    lines.append("    .aclken  (1'b1),")
                    lines.append(f"    .op_sub  ({base}_op),")
                    lines.append(f"    .valid_in({base}_valid_in),")
                    lines.append(f"    .a       ({base}_a),")
                    lines.append(f"    .b       ({base}_b),")
                    lines.append(f"    .result  ({base}_res)")
                    lines.append(");")
                elif hw_type == "fp_add":
                    base = f"fp_add_{idx}"
                    lines.append(f"logic [31:0] {base}_a, {base}_b, {base}_res;")
                    lines.append(f"logic {base}_valid_in;")
                    lines.append(
                        f"fp_add #(.LATENCY({self.latencies[hw_type]})) u_{base} ("
                    )
                    lines.append("    .aclk    (clk),")
                    lines.append("    .aresetn (rst_n),")
                    lines.append("    .aclken  (1'b1),")
                    lines.append(f"    .valid_in({base}_valid_in),")
                    lines.append(f"    .a       ({base}_a),")
                    lines.append(f"    .b       ({base}_b),")
                    lines.append(f"    .result  ({base}_res)")
                    lines.append(");")
                elif hw_type == "fp_sub":
                    base = f"fp_sub_{idx}"
                    lines.append(f"logic [31:0] {base}_a, {base}_b, {base}_res;")
                    lines.append(f"logic {base}_valid_in;")
                    lines.append(
                        f"fp_sub #(.LATENCY({self.latencies[hw_type]})) u_{base} ("
                    )
                    lines.append("    .aclk    (clk),")
                    lines.append("    .aresetn (rst_n),")
                    lines.append("    .aclken  (1'b1),")
                    lines.append(f"    .valid_in({base}_valid_in),")
                    lines.append(f"    .a       ({base}_a),")
                    lines.append(f"    .b       ({base}_b),")
                    lines.append(f"    .result  ({base}_res)")
                    lines.append(");")
                elif hw_type == "fp_mul":
                    base = f"fp_mul_{idx}"
                    lines.append(f"logic [31:0] {base}_a, {base}_b, {base}_res;")
                    lines.append(f"logic {base}_valid_in;")
                    lines.append(
                        f"fp_mul #(.LATENCY({self.latencies[hw_type]})) u_{base} ("
                    )
                    lines.append("    .aclk    (clk),")
                    lines.append("    .aresetn (rst_n),")
                    lines.append("    .aclken  (1'b1),")
                    lines.append(f"    .valid_in({base}_valid_in),")
                    lines.append(f"    .a       ({base}_a),")
                    lines.append(f"    .b       ({base}_b),")
                    lines.append(f"    .result  ({base}_res)")
                    lines.append(");")
                elif hw_type == "fp_recip":
                    base = f"fp_recip_{idx}"
                    lines.append(f"logic [31:0] {base}_in, {base}_out;")
                    lines.append(f"logic {base}_valid_in;")
                    lines.append(
                        f"fp_recip #(.LATENCY({self.latencies[hw_type]})) u_{base} ("
                    )
                    lines.append("    .aclk    (clk),")
                    lines.append("    .aresetn (rst_n),")
                    lines.append("    .aclken  (1'b1),")
                    lines.append(f"    .valid_in({base}_valid_in),")
                    lines.append(f"    .a       ({base}_in),")
                    lines.append(f"    .result  ({base}_out)")
                    lines.append(");")
                elif hw_type == "tri_bb_min_max":
                    base = f"tri_bb_min_max_{idx}"
                    lines.append(f"logic [31:0] {base}_a, {base}_b, {base}_c;")
                    lines.append(f"logic [31:0] {base}_min, {base}_max;")
                    lines.append(f"logic {base}_valid_in, {base}_valid_out;")
                    lines.append(f"tri_bb_min_max u_{base} (")
                    lines.append("    .clk        (clk),")
                    lines.append("    .rst_n      (rst_n),")
                    lines.append(f"    .valid_in   ({base}_valid_in),")
                    lines.append(f"    .f_a        ({base}_a),")
                    lines.append(f"    .f_b        ({base}_b),")
                    lines.append(f"    .f_c        ({base}_c),")
                    lines.append(f"    .valid_out  ({base}_valid_out),")
                    lines.append(f"    .f_min_floor({base}_min),")
                    lines.append(f"    .f_max_ceil ({base}_max)")
                    lines.append(");")
                elif hw_type == "fp_min_2":
                    base = f"fp_min_2_{idx}"
                    lines.append(f"logic [31:0] {base}_a, {base}_b, {base}_res;")
                    lines.append(f"logic {base}_valid_in, {base}_valid_out;")
                    lines.append(f"fp_min_2 u_{base} (")
                    lines.append("    .clk      (clk),")
                    lines.append("    .rst_n    (rst_n),")
                    lines.append(f"    .valid_in ({base}_valid_in),")
                    lines.append(f"    .f_a      ({base}_a),")
                    lines.append(f"    .f_b      ({base}_b),")
                    lines.append(f"    .valid_out({base}_valid_out),")
                    lines.append(f"    .f_min    ({base}_res)")
                    lines.append(");")
                elif hw_type == "fp_max_2":
                    base = f"fp_max_2_{idx}"
                    lines.append(f"logic [31:0] {base}_a, {base}_b, {base}_res;")
                    lines.append(f"logic {base}_valid_in, {base}_valid_out;")
                    lines.append(f"fp_max_2 u_{base} (")
                    lines.append("    .clk      (clk),")
                    lines.append("    .rst_n    (rst_n),")
                    lines.append(f"    .valid_in ({base}_valid_in),")
                    lines.append(f"    .f_a      ({base}_a),")
                    lines.append(f"    .f_b      ({base}_b),")
                    lines.append(f"    .valid_out({base}_valid_out),")
                    lines.append(f"    .f_max    ({base}_res)")
                    lines.append(");")
                elif hw_type == "fp_add_half_fast":
                    base = f"fp_add_half_fast_{idx}"
                    lines.append(f"logic [31:0] {base}_in, {base}_out;")
                    lines.append(f"logic {base}_valid_in, {base}_valid_out;")
                    lines.append(f"fp_add_half_fast u_{base} (")
                    lines.append("    .clk      (clk),")
                    lines.append("    .rst_n    (rst_n),")
                    lines.append(f"    .valid_in ({base}_valid_in),")
                    lines.append(f"    .f_in     ({base}_in),")
                    lines.append(f"    .valid_out({base}_valid_out),")
                    lines.append(f"    .f_out    ({base}_out)")
                    lines.append(");")
                elif hw_type == "fp32_to_int16":
                    base = f"fp32_to_int16_{idx}"
                    lines.append(f"logic [31:0] {base}_in;")
                    lines.append(f"logic [15:0] {base}_out;")
                    lines.append(f"logic {base}_valid_in;")
                    lines.append(
                        f"fp32_to_int16 #(.LATENCY({self.latencies[hw_type]})) u_{base} ("
                    )
                    lines.append("    .aclk    (clk),")
                    lines.append("    .aresetn (rst_n),")
                    lines.append("    .aclken  (1'b1),")
                    lines.append(f"    .valid_in({base}_valid_in),")
                    lines.append(f"    .a       ({base}_in),")
                    lines.append(f"    .result  ({base}_out)")
                    lines.append(");")
                elif hw_type == "int16_add_sub":
                    base = f"int16_sub_{idx}"
                    lines.append(f"logic [15:0] {base}_a, {base}_b, {base}_res;")
                    lines.append(f"int16_sub u_{base} (")
                    lines.append("    .clken(1'b1),")
                    lines.append(f"    .a    ({base}_a),")
                    lines.append(f"    .b    ({base}_b),")
                    lines.append(f"    .s    ({base}_res)")
                    lines.append(");")
                lines.append("")

        lines.append("// ---------------- Sequential Latch FSM ----------------")
        lines.append("always_ff @(posedge clk) begin")
        lines.append("  if (!rst_n) begin")
        for reg in sorted(reg_width_by_name.keys()):
            w = reg_width_by_name[reg]
            lines.append(f"    {reg} <= {w}'b0;")
        lines.append("  end else if (state == ST_CALC) begin")
        lines.append("    case (cycle_cnt)")
        for cycle in sorted(latch_by_cycle.keys()):
            lines.append(f"      8'd{cycle}: begin")
            for op in latch_by_cycle[cycle]:
                hw_type = self.ops[op][0]
                inst = op_unit_idx[op]
                if hw_type == "fp_add_sub":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp_add_sub_{inst}_res;"
                    )
                elif hw_type == "fp_add":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp_add_{inst}_res;"
                    )
                elif hw_type == "fp_sub":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp_sub_{inst}_res;"
                    )
                elif hw_type == "fp_mul":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp_mul_{inst}_res;"
                    )
                elif hw_type == "fp_recip":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp_recip_{inst}_out;"
                    )
                elif hw_type == "tri_bb_min_max":
                    min_reg, max_reg = tri_reg_pair_by_node[op]
                    lines.append(f"        {min_reg} <= tri_bb_min_max_{inst}_min;")
                    lines.append(f"        {max_reg} <= tri_bb_min_max_{inst}_max;")
                elif hw_type == "fp_min_2":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp_min_2_{inst}_res;"
                    )
                elif hw_type == "fp_max_2":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp_max_2_{inst}_res;"
                    )
                elif hw_type == "fp_add_half_fast":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp_add_half_fast_{inst}_out;"
                    )
                elif hw_type == "fp32_to_int16":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= fp32_to_int16_{inst}_out;"
                    )
                elif hw_type == "int16_add_sub":
                    lines.append(
                        f"        {reg_name_by_node[op]} <= int16_sub_{inst}_res;"
                    )
            lines.append("      end")
        lines.append("      default: ;")
        lines.append("    endcase")
        lines.append("  end")
        lines.append("end")
        lines.append("")

        lines.append("// ---------------- Combinational Launch FSM ----------------")
        lines.append("always_comb begin")
        for hw_type in sorted(unit_count.keys()):
            for idx in range(1, unit_count[hw_type] + 1):
                if hw_type == "fp_add_sub":
                    lines.append(f"  fp_add_sub_{idx}_a = 32'b0;")
                    lines.append(f"  fp_add_sub_{idx}_b = 32'b0;")
                    lines.append(f"  fp_add_sub_{idx}_op = 1'b0;")
                    lines.append(f"  fp_add_sub_{idx}_valid_in = 1'b0;")
                elif hw_type == "fp_add":
                    lines.append(f"  fp_add_{idx}_a = 32'b0;")
                    lines.append(f"  fp_add_{idx}_b = 32'b0;")
                    lines.append(f"  fp_add_{idx}_valid_in = 1'b0;")
                elif hw_type == "fp_sub":
                    lines.append(f"  fp_sub_{idx}_a = 32'b0;")
                    lines.append(f"  fp_sub_{idx}_b = 32'b0;")
                    lines.append(f"  fp_sub_{idx}_valid_in = 1'b0;")
                elif hw_type == "fp_mul":
                    lines.append(f"  fp_mul_{idx}_a = 32'b0;")
                    lines.append(f"  fp_mul_{idx}_b = 32'b0;")
                    lines.append(f"  fp_mul_{idx}_valid_in = 1'b0;")
                elif hw_type == "fp_recip":
                    lines.append(f"  fp_recip_{idx}_in = 32'b0;")
                    lines.append(f"  fp_recip_{idx}_valid_in = 1'b0;")
                elif hw_type == "tri_bb_min_max":
                    lines.append(f"  tri_bb_min_max_{idx}_a = 32'b0;")
                    lines.append(f"  tri_bb_min_max_{idx}_b = 32'b0;")
                    lines.append(f"  tri_bb_min_max_{idx}_c = 32'b0;")
                    lines.append(f"  tri_bb_min_max_{idx}_valid_in = 1'b0;")
                elif hw_type == "fp_min_2":
                    lines.append(f"  fp_min_2_{idx}_a = 32'b0;")
                    lines.append(f"  fp_min_2_{idx}_b = 32'b0;")
                    lines.append(f"  fp_min_2_{idx}_valid_in = 1'b0;")
                elif hw_type == "fp_max_2":
                    lines.append(f"  fp_max_2_{idx}_a = 32'b0;")
                    lines.append(f"  fp_max_2_{idx}_b = 32'b0;")
                    lines.append(f"  fp_max_2_{idx}_valid_in = 1'b0;")
                elif hw_type == "fp_add_half_fast":
                    lines.append(f"  fp_add_half_fast_{idx}_in = 32'b0;")
                    lines.append(f"  fp_add_half_fast_{idx}_valid_in = 1'b0;")
                elif hw_type == "fp32_to_int16":
                    lines.append(f"  fp32_to_int16_{idx}_in = 32'b0;")
                    lines.append(f"  fp32_to_int16_{idx}_valid_in = 1'b0;")
                elif hw_type == "int16_add_sub":
                    lines.append(f"  int16_sub_{idx}_a = 16'b0;")
                    lines.append(f"  int16_sub_{idx}_b = 16'b0;")

        lines.append("")
        lines.append("  if (state == ST_CALC) begin")
        lines.append("    case (cycle_cnt)")
        for cycle in sorted(launch_by_cycle.keys()):
            lines.append(f"      8'd{cycle}: begin")
            for op in launch_by_cycle[cycle]:
                hw_type = self.ops[op][0]
                inst = op_unit_idx[op]
                inputs = self.op_inputs.get(op, tuple())
                if hw_type == "fp_add_sub":
                    a = signal_to_rtl(inputs[0])
                    b = signal_to_rtl(inputs[1])
                    op_sub = self.ops[op][3] == "-"
                    lines.append(f"        fp_add_sub_{inst}_a = {a};")
                    lines.append(f"        fp_add_sub_{inst}_b = {b};")
                    lines.append(
                        f"        fp_add_sub_{inst}_op = 1'b{1 if op_sub else 0};"
                    )
                    lines.append(f"        fp_add_sub_{inst}_valid_in = 1'b1;")
                elif hw_type == "fp_add":
                    a = signal_to_rtl(inputs[0])
                    b = signal_to_rtl(inputs[1])
                    lines.append(f"        fp_add_{inst}_a = {a};")
                    lines.append(f"        fp_add_{inst}_b = {b};")
                    lines.append(f"        fp_add_{inst}_valid_in = 1'b1;")
                elif hw_type == "fp_sub":
                    a = signal_to_rtl(inputs[0])
                    b = signal_to_rtl(inputs[1])
                    lines.append(f"        fp_sub_{inst}_a = {a};")
                    lines.append(f"        fp_sub_{inst}_b = {b};")
                    lines.append(f"        fp_sub_{inst}_valid_in = 1'b1;")
                elif hw_type == "fp_mul":
                    a = signal_to_rtl(inputs[0])
                    b = signal_to_rtl(inputs[1])
                    lines.append(f"        fp_mul_{inst}_a = {a};")
                    lines.append(f"        fp_mul_{inst}_b = {b};")
                    lines.append(f"        fp_mul_{inst}_valid_in = 1'b1;")
                elif hw_type == "fp_recip":
                    a = signal_to_rtl(inputs[0])
                    lines.append(f"        fp_recip_{inst}_in = {a};")
                    lines.append(f"        fp_recip_{inst}_valid_in = 1'b1;")
                elif hw_type == "tri_bb_min_max":
                    a = signal_to_rtl(inputs[0])
                    b = signal_to_rtl(inputs[1])
                    c = signal_to_rtl(inputs[2])
                    lines.append(f"        tri_bb_min_max_{inst}_a = {a};")
                    lines.append(f"        tri_bb_min_max_{inst}_b = {b};")
                    lines.append(f"        tri_bb_min_max_{inst}_c = {c};")
                    lines.append(f"        tri_bb_min_max_{inst}_valid_in = 1'b1;")
                elif hw_type == "fp_min_2":
                    a = signal_to_rtl(inputs[0])
                    b = signal_to_rtl(inputs[1])
                    lines.append(f"        fp_min_2_{inst}_a = {a};")
                    lines.append(f"        fp_min_2_{inst}_b = {b};")
                    lines.append(f"        fp_min_2_{inst}_valid_in = 1'b1;")
                elif hw_type == "fp_max_2":
                    a = signal_to_rtl(inputs[0])
                    b = signal_to_rtl(inputs[1])
                    lines.append(f"        fp_max_2_{inst}_a = {a};")
                    lines.append(f"        fp_max_2_{inst}_b = {b};")
                    lines.append(f"        fp_max_2_{inst}_valid_in = 1'b1;")
                elif hw_type == "fp_add_half_fast":
                    a = signal_to_rtl(inputs[0])
                    lines.append(f"        fp_add_half_fast_{inst}_in = {a};")
                    lines.append(f"        fp_add_half_fast_{inst}_valid_in = 1'b1;")
                elif hw_type == "fp32_to_int16":
                    a = signal_to_rtl(inputs[0])
                    lines.append(f"        fp32_to_int16_{inst}_in = {a};")
                    lines.append(f"        fp32_to_int16_{inst}_valid_in = 1'b1;")
                elif hw_type == "int16_add_sub":
                    a = signal_to_rtl(inputs[0])
                    b = signal_to_rtl(inputs[1])
                    lines.append(f"        int16_sub_{inst}_a = {a}[15:0];")
                    lines.append(f"        int16_sub_{inst}_b = {b}[15:0];")
            lines.append("      end")
        lines.append("      default: ;")
        lines.append("    endcase")
        lines.append("  end")
        lines.append("end")

        Path(output_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
        return reg_name_by_node, tri_reg_pair_by_node

    def schedule(self, hw_limits, max_cycles=150, pipeline_register_delay=1):
        """Uses OR-Tools to find the optimal cycle-accurate schedule for the generated DAG."""
        model = cp_model.CpModel()
        start_times = {}

        # 1. Create Start Time Variables
        for node_id in self.ops:
            start_times[node_id] = model.NewIntVar(0, max_cycles, f"start_{node_id}")

        # 2. Add Dependency Constraints with the 1-Cycle Gap
        for src, dst in self.dependencies:
            latency = self.ops[src][1]
            model.Add(
                start_times[dst] >= start_times[src] + latency + pipeline_register_delay
            )

        # 3. Add Hardware Resource Constraints
        for t in range(max_cycles + 1):
            for hw_type, limit in hw_limits.items():
                active_ops_at_t = []
                for node_id, op_data in self.ops.items():
                    otype = op_data[0]
                    if otype == hw_type:
                        is_active = model.NewBoolVar(f"{node_id}_active_at_{t}")
                        model.Add(start_times[node_id] == t).OnlyEnforceIf(is_active)
                        model.Add(start_times[node_id] != t).OnlyEnforceIf(
                            is_active.Not()
                        )
                        active_ops_at_t.append(is_active)

                if active_ops_at_t:
                    model.Add(sum(active_ops_at_t) <= limit)

        # 4. Minimize Total Pipeline Latency
        pipeline_latency = model.NewIntVar(0, max_cycles, "pipeline_latency")
        for node_id, op_data in self.ops.items():
            lat = op_data[1]
            model.Add(pipeline_latency >= start_times[node_id] + lat)

        model.Minimize(pipeline_latency)

        # 5. Solve and Output
        solver = cp_model.CpSolver()
        status = solver.Solve(model)

        if status == cp_model.OPTIMAL or status == cp_model.FEASIBLE:
            print(f"Optimal Pipeline Latency: {int(solver.ObjectiveValue())} cycles\n")

            consumers = {node_id: [] for node_id in self.ops}
            for src, dst in self.dependencies:
                consumers[src].append(dst)

            solved_start_times = {
                node_id: solver.Value(start_times[node_id]) for node_id in self.ops
            }
            sorted_ops = sorted(self.ops.keys(), key=lambda x: solved_start_times[x])
            op_unit_idx, _unit_count = self._assign_unit_indices(
                sorted_ops, solved_start_times, hw_limits
            )
            preferred_reg_by_node = self._build_preferred_temp_binding(
                sorted_ops,
                solved_start_times,
                hw_limits,
                consumers,
            )

            temp_intervals = []
            for node_id, op_data in self.ops.items():
                node_name = self.node_names.get(node_id, "")

                # Check if this signal should be allocated a temp register
                # Skip named signals unless they (or any part of them) are in drop_named_signals
                should_use_temp = False
                if not node_name:
                    # Unnamed signal always uses temp
                    should_use_temp = True
                elif " / " in node_name:
                    # Multi-output signal: use temp if ANY part is dropped
                    parts = [s.strip() for s in node_name.split(" / ")]
                    should_use_temp = any(
                        part in self.drop_named_signals for part in parts
                    )
                elif node_name in self.drop_named_signals:
                    # Single-output dropped signal uses temp
                    should_use_temp = True

                if not should_use_temp:
                    continue

                # Bound nodes are routed to a deterministic consumer-input register.
                if node_id in preferred_reg_by_node:
                    continue

                start_t = solver.Value(start_times[node_id])
                end_t = start_t + op_data[1]
                last_use_t = end_t
                if consumers[node_id]:
                    last_use_t = max(
                        solver.Value(start_times[use_id])
                        for use_id in consumers[node_id]
                    )

                temp_intervals.append((start_t, last_use_t, node_id))
                # tri_bb_min_max produces two outputs (min and max); allocate a second temp
                if op_data[0] == "tri_bb_min_max":
                    temp_intervals.append((start_t, last_use_t, f"{node_id}__max_out"))

            # Separate intervals by output bit-width so 32-bit and 16-bit pools never mix.
            INT16_OPS = ("fp32_to_int16", "int16_add_sub", "int16_mul")

            def _op_width(nid):
                actual = nid.replace("__max_out", "")
                return 16 if self.ops[actual][0] in INT16_OPS else 32

            temp_intervals_32 = [
                (s, e, n) for s, e, n in temp_intervals if _op_width(n) == 32
            ]
            temp_intervals_16 = [
                (s, e, n) for s, e, n in temp_intervals if _op_width(n) == 16
            ]
            temp_intervals_32.sort(key=lambda item: (item[0], item[1]))
            temp_intervals_16.sort(key=lambda item: (item[0], item[1]))

            free_registers = []
            active_registers = []
            temp_register_by_node = {}
            temp_usage_by_register = {}
            next_temp_register = 0
            max_temp_registers = 0

            def _alloc_pool(intervals, prefix):
                nonlocal max_temp_registers
                free_regs = []
                active_regs = []
                next_reg = 0
                for start_t, last_use_t, node_id in intervals:
                    while active_regs and active_regs[0][0] <= start_t:
                        _, freed_reg = heapq.heappop(active_regs)
                        heapq.heappush(free_regs, freed_reg)

                    if free_regs:
                        reg_idx = heapq.heappop(free_regs)
                    else:
                        reg_idx = next_reg
                        next_reg += 1

                    actual_node_id = node_id.replace("__max_out", "")
                    actual_op_data = self.ops[actual_node_id]

                    temp_register_by_node[node_id] = f"{prefix}{reg_idx}"
                    temp_usage_by_register.setdefault(f"{prefix}{reg_idx}", []).append(
                        (start_t + actual_op_data[1], last_use_t)
                    )
                    heapq.heappush(active_regs, (last_use_t, reg_idx))
                    max_temp_registers = max(max_temp_registers, len(active_regs))

            _alloc_pool(temp_intervals_32, "tmp")
            _alloc_pool(temp_intervals_16, "stmp")

            # Add deterministic bindings after pool allocation.
            temp_register_by_node.update(preferred_reg_by_node)

            print(f"Max Temp Registers Needed: {max_temp_registers}\n")

            rtl_blocks_path = Path(__file__).with_name(
                "raster_frontend_autogen_blocks.svh"
            )
            reg_name_by_node, tri_reg_pair_by_node = self.dump_raster_frontend_blocks(
                solved_start_times,
                hw_limits,
                temp_register_by_node,
                rtl_blocks_path,
                op_unit_idx=op_unit_idx,
                unit_count=_unit_count,
            )
            print(f"RTL blocks written to {rtl_blocks_path}")

            gantt_path = Path(__file__).with_name("temp_register_gantt.mmd")
            flowchart_path = Path(__file__).with_name("hardware_flowchart.mmd")

            # Write a Gantt chart that primarily shows operations (one section per op)
            if self.ops:
                base_date = datetime(2026, 1, 1)
                gantt_lines = [
                    "gantt",
                    "    title Operation Gantt",
                    "    dateFormat  YY",
                    "    axisFormat  %y",
                    "    todaymarker off",
                ]

                # Allocate specific hardware unit instances for each operation
                op_unit_map = {}
                unit_usage = {}
                hw_units = {}
                hw_created_counts = {}

                for op in sorted_ops:
                    otype = self.ops[op][0]
                    start_t = solver.Value(start_times[op])
                    end_t = start_t + self.ops[op][1]
                    limit = hw_limits.get(otype, 1)

                    heap = hw_units.setdefault(otype, [])
                    created = hw_created_counts.get(otype, 0)

                    inst_idx = None
                    # Reuse any instance that is free at or before start_t
                    if heap and heap[0][0] <= start_t:
                        free_time, idx = heapq.heappop(heap)
                        inst_idx = idx

                    if inst_idx is None:
                        if created < limit:
                            created += 1
                            hw_created_counts[otype] = created
                            inst_idx = created
                        else:
                            # Fallback: reuse the earliest finishing instance
                            free_time, idx = heapq.heappop(heap)
                            inst_idx = idx

                    # Mark this instance busy until end_t
                    heapq.heappush(hw_units[otype], (end_t, inst_idx))

                    unit_name = f"{otype}_{inst_idx}"
                    op_unit_map[op] = unit_name
                    unit_usage.setdefault(unit_name, []).append((start_t, end_t, op))

                # Emit Gantt grouped per physical unit
                for unit in sorted(
                    unit_usage.keys(),
                    key=lambda u: (u.split("_")[0], int(u.split("_")[-1])),
                ):
                    gantt_lines.append(f"    section {unit}")
                    for idx, (start_t, end_t, op) in enumerate(
                        unit_usage[unit], start=1
                    ):
                        # Start and end cycle labels as two-digit values
                        start_label = f"{start_t:02d}"
                        end_label = f"{end_t:02d}"
                        label = op
                        gantt_lines.append(
                            f"    {label} :active, {start_label}, {end_label}"
                        )

                gantt_path.write_text("\n".join(gantt_lines) + "\n", encoding="utf-8")
                print(f"Mermaid gantt written to {gantt_path}")

            # Flat flowchart: operation nodes + output register nodes + leaf input nodes
            flowchart_lines = ["flowchart LR"]
            color_map = {
                "fp_add_sub": "#f9c74f",
                "fp_add": "#f9c74f",
                "fp_sub": "#f9c74f",
                "int16_add_sub": "#f9c74f",
                "fp_mul": "#90be6d",
                "int16_mul": "#90be6d",
                "fp_recip": "#f94144",
                "fp32_to_int16": "#577590",
                "tri_bb_min_max": "#277da1",
                "fp_min_2": "#f3722c",
                "fp_max_2": "#f94144",
                "fp_add_half_fast": "#90be6d",
            }
            REG_COLOR = "#d8d8d8"
            LEAF_COLOR = "#c8e6fa"

            def _op_output_regs(op):
                """Return [(mermaid_node_id, reg_label, tag)] for outputs of op."""
                ht = self.ops[op][0]
                if ht == "tri_bb_min_max" and op in tri_reg_pair_by_node:
                    min_r, max_r = tri_reg_pair_by_node[op]
                    return [(f"R_{min_r}", min_r, "min"), (f"R_{max_r}", max_r, "max")]
                reg = reg_name_by_node.get(op, "")
                return [(f"R_{reg}", reg, "")] if reg else []

            # Op nodes
            for op in sorted_ops:
                hw_type = self.ops[op][0]
                inst = op_unit_idx.get(op, "?")
                node_label = f"{hw_type}_{inst}\\n{op}".replace('"', "'")
                flowchart_lines.append(f'    {op}["{node_label}"]')

            # Output register nodes (stadium shape)
            seen_regs: set = set()
            for op in sorted_ops:
                for reg_id, reg_label, _ in _op_output_regs(op):
                    if reg_id not in seen_regs:
                        flowchart_lines.append(f'    {reg_id}(["{reg_label}"])')
                        seen_regs.add(reg_id)

            # Leaf input register nodes
            seen_leaves: set = set()
            for op in sorted_ops:
                for sig in self.op_inputs.get(op, ()):
                    if isinstance(sig, Signal) and not sig.hw_id:
                        leaf_rtl = HardwareDAG._leaf_expr_to_rtl(sig.expr)
                        leaf_id = "L_" + re.sub(r"[^0-9A-Za-z_]", "_", leaf_rtl)
                        if leaf_id not in seen_leaves:
                            flowchart_lines.append(f'    {leaf_id}(["{leaf_rtl}"])')
                            seen_leaves.add(leaf_id)

            # Edges: op --> output register
            for op in sorted_ops:
                for reg_id, _, _ in _op_output_regs(op):
                    flowchart_lines.append(f"    {op} --> {reg_id}")

            # Edges: leaf register --> op
            for op in sorted_ops:
                for sig in self.op_inputs.get(op, ()):
                    if isinstance(sig, Signal) and not sig.hw_id:
                        leaf_rtl = HardwareDAG._leaf_expr_to_rtl(sig.expr)
                        leaf_id = "L_" + re.sub(r"[^0-9A-Za-z_]", "_", leaf_rtl)
                        flowchart_lines.append(f"    {leaf_id} --> {op}")

            # Edges: output register --> consumer op (via dependencies)
            for src, dst in self.dependencies:
                ht = self.ops[src][0]
                if ht == "tri_bb_min_max" and src in tri_reg_pair_by_node:
                    min_r, max_r = tri_reg_pair_by_node[src]
                    for sig in self.op_inputs.get(dst, ()):
                        if isinstance(sig, Signal) and sig.hw_id == src:
                            chosen = max_r if sig.expr.startswith("ceil(") else min_r
                            flowchart_lines.append(f"    R_{chosen} --> {dst}")
                else:
                    reg = reg_name_by_node.get(src, "")
                    if reg:
                        flowchart_lines.append(f"    R_{reg} --> {dst}")

            # Styles: op nodes
            for op in sorted_ops:
                hw_type = self.ops[op][0]
                color = color_map.get(hw_type, "#dddddd")
                flowchart_lines.append(
                    f"    style {op} fill:{color},stroke:#333,stroke-width:2px"
                )
            # Styles: register nodes
            for reg_id in seen_regs:
                flowchart_lines.append(
                    f"    style {reg_id} fill:{REG_COLOR},stroke:#888,stroke-width:1px"
                )
            # Styles: leaf nodes
            for leaf_id in seen_leaves:
                flowchart_lines.append(
                    f"    style {leaf_id} fill:{LEAF_COLOR},stroke:#888,stroke-width:1px"
                )

            flowchart_path.write_text(
                "\n".join(flowchart_lines) + "\n", encoding="utf-8"
            )
            print(f"Mermaid flowchart written to {flowchart_path}")

            print(
                f"{'Operation ID':<28} | {'Hardware Unit':<28} | {'Start C.':>10} | {'End C.':>10} | {'Name':>28} | {'Expression'}"
            )
            print("-" * 140)

            sorted_ops = sorted(
                self.ops.keys(), key=lambda x: solver.Value(start_times[x])
            )

            # Keep track of unit allocations per cycle
            cycle_issue_counts = {}

            for op in sorted_ops:
                start_t = solver.Value(start_times[op])
                hw_type = self.ops[op][0]
                latency = self.ops[op][1]
                expr = self.ops[op][2]
                op_symbol = (
                    self.ops[op][3]
                    if hw_type == "fp_add_sub" and len(self.ops[op]) > 3
                    else ""
                )
                if hw_type == "tri_bb_min_max" and len(self.ops[op]) > 3:
                    expr = f"min={self.ops[op][2]}, max={self.ops[op][3]}"
                end_t = start_t + latency

                # Determine signal name and what register it uses
                signal_name = self.node_names.get(op, "")
                # For multi-output signals (e.g., "tri_min_x / tri_max_x"), check if any part is dropped
                signal_parts = (
                    [s.strip() for s in signal_name.split("/")] if signal_name else []
                )
                is_dropped = any(
                    part in self.drop_named_signals for part in signal_parts
                )

                if signal_name and is_dropped:
                    # Dropped named signal uses temp register(s)
                    if hw_type == "tri_bb_min_max":
                        min_reg = temp_register_by_node.get(op, "")
                        max_reg = temp_register_by_node.get(f"{op}__max_out", "")
                        name = f"{signal_name} ({min_reg} / {max_reg})"
                    else:
                        register = temp_register_by_node.get(op, "")
                        name = f"{signal_name} ({register})"
                elif signal_name:
                    # Named signal not dropped, uses named register(s)
                    if "/" in signal_name:
                        # Multi-output signal
                        registers = " / ".join(
                            [f"{s.strip()}_reg" for s in signal_name.split("/")]
                        )
                        name = f"{signal_name} ({registers})"
                    else:
                        # Single output signal
                        register = f"{signal_name}_reg"
                        name = f"{signal_name} ({register})"
                else:
                    # Unnamed signal uses temp register
                    register = temp_register_by_node.get(op, "")
                    name = f"({register})" if register else ""

                # Assign a specific physical hardware sub-unit instance
                if start_t not in cycle_issue_counts:
                    cycle_issue_counts[start_t] = {}
                if hw_type not in cycle_issue_counts[start_t]:
                    cycle_issue_counts[start_t][hw_type] = 0

                inst_idx = cycle_issue_counts[start_t][hw_type]
                cycle_issue_counts[start_t][hw_type] += 1

                hw_unit_str = f"{hw_type} {inst_idx + 1}"
                if op_symbol:
                    hw_unit_str = f"{hw_unit_str} ({op_symbol})"
                if hw_type == "tri_bb_min_max":
                    hw_unit_str = f"{hw_unit_str} (min/max)"

                print(
                    f"{op:<28} | {hw_unit_str:<28} | {start_t:>10} | {end_t:>10} | {name:>28} | {expr}"
                )

        else:
            print("No feasible schedule found. Consider increasing max_cycles.")


class Signal:
    def __init__(self, dag, name=None, hw_id=None, expr=None, type="float_t"):
        self.dag = dag
        self.hw_id = hw_id
        self._name = None
        self.type = type

        # Track the mathematical expression for readability
        if name:
            self.expr = name
        elif expr:
            self.expr = expr
        else:
            self.expr = f"Node_{hw_id}"

        self.name = name

    @property
    def name(self):
        return self._name

    @name.setter
    def name(self, value):
        self._name = value
        if value and self.dag and self.hw_id:
            existing = self.dag.node_names.get(self.hw_id)
            if existing and existing != value:
                if value not in existing.split(" / "):
                    self.dag.node_names[self.hw_id] = f"{existing} / {value}"
            else:
                self.dag.node_names[self.hw_id] = value

    def __repr__(self):
        label = self.name if self.name else self.expr
        if self.hw_id:
            return f"Signal(name={label!r}, expr={self.expr!r}, hw_id={self.hw_id!r})"
        return f"Signal(name={label!r}, expr={self.expr!r})"

    def drop(self):
        """
        Mark this signal to use a temp register instead of a named reg.
        Returns self for method chaining.
        """
        if self._name and self.dag:
            self.dag.drop_named_signals.add(self._name)
        return self

    # --- Binary Operators ---
    def __add__(self, other):
        if self.type != other.type:
            raise TypeError("Binary operations require matching signal types.")
        new_expr = f"({self.expr} + {other.expr})"

        if self.dag.use_separate_add_sub:
            op_type = "fp_add" if self.type == "float_t" else "int16_add_sub"
        else:
            op_type = "fp_add_sub" if self.type == "float_t" else "int16_add_sub"

        node_id = self.dag.add_operation(op_type, self, other, new_expr, "+")
        return Signal(self.dag, hw_id=node_id, expr=new_expr, type=self.type)

    def __sub__(self, other):
        if self.type != other.type:
            raise TypeError("Binary operations require matching signal types.")
        new_expr = f"({self.expr} - {other.expr})"

        if self.dag.use_separate_add_sub:
            op_type = "fp_sub" if self.type == "float_t" else "int16_add_sub"
        else:
            op_type = "fp_add_sub" if self.type == "float_t" else "int16_add_sub"

        node_id = self.dag.add_operation(op_type, self, other, new_expr, "-")
        return Signal(self.dag, hw_id=node_id, expr=new_expr, type=self.type)

    def __mul__(self, other):
        if self.type != other.type:
            raise TypeError("Binary operations require matching signal types.")
        new_expr = f"({self.expr} * {other.expr})"
        op_type = "fp_mul" if self.type == "float_t" else "int16_mul"
        node_id = self.dag.add_operation(op_type, self, other, new_expr)
        return Signal(self.dag, hw_id=node_id, expr=new_expr, type=self.type)

    # --- Unary Operators ---
    def __rtruediv__(self, other):
        assert self.type == "float_t"
        if other == 1:
            new_expr = f"(1 / {self.expr})"
            node_id = self.dag.add_unary_operation("fp_recip", self, new_expr)
            return Signal(self.dag, hw_id=node_id, expr=new_expr)
        else:
            raise NotImplementedError("Only 1 / Signal is supported.")

    def to_int16(self):
        assert self.type == "float_t"
        new_expr = f"int({self.expr})"
        node_id = self.dag.add_unary_operation("fp32_to_int16", self, new_expr)
        return Signal(self.dag, hw_id=node_id, expr=new_expr, type="int16_t")

    @staticmethod
    def min_max_3(a, b, c):
        assert a.type == "float_t"
        assert b.type == "float_t"
        assert c.type == "float_t"

        # Ensure all signals belong to the same DAG
        if not (a.dag is b.dag is c.dag):
            raise ValueError("All signals must belong to the same HardwareDAG")

        dag = a.dag
        new_expr = f"min_max_3({a.expr}, {b.expr}, {c.expr})"
        node_id = dag.add_ternary_operation("MIN_MAX_3", a, b, c, new_expr)
        return Signal(dag, hw_id=node_id, expr=new_expr)

    @staticmethod
    def min(a, b):
        assert a.type == "float_t"
        assert b.type == "float_t"

        # Ensure all signals belong to the same DAG
        if not (a.dag is b.dag):
            raise ValueError("All signals must belong to the same HardwareDAG")

        dag = a.dag
        new_expr = f"min({a.expr}, {b.expr})"
        node_id = dag.add_operation("fp_min_2", a, b, new_expr)
        return Signal(dag, hw_id=node_id, expr=new_expr)

    @staticmethod
    def max(a, b):
        assert a.type == "float_t"
        assert b.type == "float_t"

        # Ensure all signals belong to the same DAG
        if not (a.dag is b.dag):
            raise ValueError("All signals must belong to the same HardwareDAG")

        dag = a.dag
        new_expr = f"max({a.expr}, {b.expr})"
        node_id = dag.add_operation("fp_max_2", a, b, new_expr)
        return Signal(dag, hw_id=node_id, expr=new_expr)

    @staticmethod
    def tri_bb_min_max(a, b, c):
        assert a.type == "float_t"
        assert b.type == "float_t"
        assert c.type == "float_t"

        # Ensure all signals belong to the same DAG
        if not (a.dag is b.dag is c.dag):
            raise ValueError("All signals must belong to the same HardwareDAG")

        dag = a.dag
        expr_key = f"tri_bb_min_max({a.expr}, {b.expr}, {c.expr})"
        min_expr = f"floor(min({a.expr}, {b.expr}, {c.expr}))"
        max_expr = f"ceil(max({a.expr}, {b.expr}, {c.expr}))"
        node_id = dag.add_tri_bb_min_max_operation(
            a, b, c, expr_key, min_expr, max_expr
        )
        return (
            Signal(dag, hw_id=node_id, expr=min_expr),
            Signal(dag, hw_id=node_id, expr=max_expr),
        )

    def fast_half_add_to_rounded(self):
        assert self.type == "float_t"
        dag = self.dag
        new_expr = f"({self.expr} + 0.5)"
        node_id = dag.add_fast_half_add_to_rounded_operation(self, new_expr)
        return Signal(dag, hw_id=node_id, expr=new_expr)


def auto_name_signals(namespace):
    named_signals = {}
    for var_name, value in namespace.items():
        if isinstance(value, Signal) and value.hw_id:
            value.name = var_name
            named_signals[var_name] = value
    return named_signals


# ==========================================
# Testing the New Math Functions
# ==========================================
if __name__ == "__main__":
    # Assuming float-to-int or float rounding takes 2 cycles in FPGA logic
    latencies = {
        "fp_add_sub": 8,
        "fp_add": 8,
        "fp_sub": 8,
        "int16_add_sub": 0,
        "fp_mul": 5,
        "int16_mul": 1,
        "fp_recip": 22,
        "fp32_to_int16": 2,
        "fp_min_2": 1,
        "fp_max_2": 1,
        "fp_add_half_fast": 2,
        "tri_bb_min_max": 5,
    }

    # Set to True to use separate fp_add and fp_sub units
    USE_SEPARATE_ADD_SUB = False

    if USE_SEPARATE_ADD_SUB:
        hw_limits = {
            "fp_add": 2,
            "fp_sub": 1,
            "int16_add_sub": 1,
            "fp_mul": 2,
            "fp_recip": 1,
            "fp32_to_int16": 1,
            "tri_bb_min_max": 1,
            "fp_min_2": 1,
            "fp_max_2": 1,
            "fp_add_half_fast": 1,
        }
    else:
        hw_limits = {
            "fp_add_sub": 2,
            "int16_add_sub": 1,
            "fp_mul": 2,
            "int16_mul": 2,
            "fp_recip": 1,
            "fp32_to_int16": 1,
            "tri_bb_min_max": 1,
            "fp_min_2": 1,
            "fp_max_2": 1,
            "fp_add_half_fast": 1,
        }

    dag = HardwareDAG(latencies, use_separate_add_sub=USE_SEPARATE_ADD_SUB)

    v0_x = Signal(dag, name="v0.x")
    v0_y = Signal(dag, name="v0.y")
    v1_x = Signal(dag, name="v1.x")
    v1_y = Signal(dag, name="v1.y")
    v2_x = Signal(dag, name="v2.x")
    v2_y = Signal(dag, name="v2.y")

    bin_min_x = Signal(dag, name="binMinX")
    bin_min_y = Signal(dag, name="binMinY")
    bin_max_x = Signal(dag, name="binMaxX")
    bin_max_y = Signal(dag, name="binMaxY")

    # dx, dy
    e0_dx = v2_y - v1_y
    e0_dy = v1_x - v2_x
    e1_dx = v0_y - v2_y
    e1_dy = v2_x - v0_x
    e2_dx = v1_y - v0_y
    e2_dy = v0_x - v1_x

    # Set names and mark for dropping
    e0_dx.name = "e0_dx"
    e0_dx.drop()
    e0_dy.name = "e0_dy"
    e0_dy.drop()
    e1_dx.name = "e1_dx"
    e1_dx.drop()
    e1_dy.name = "e1_dy"
    e1_dy.drop()
    e2_dx.name = "e2_dx"
    e2_dx.drop()
    e2_dy.name = "e2_dy"
    e2_dy.drop()

    # Calculate area = edge(v0, v1, v2) = ((v2_x - v0_x) * (v1_y - v0_y) - (v2_y - v0_y) * (v1_x - v0_x))
    invArea = 1 / ((e1_dy) * (e2_dx) - (v2_y - v0_y) * (v1_x - v0_x))

    # Calculate BB
    tri_min_x, tri_max_x = Signal.tri_bb_min_max(v0_x, v1_x, v2_x)
    tri_min_y, tri_max_y = Signal.tri_bb_min_max(v0_y, v1_y, v2_y)

    tri_min_x.name = "tri_min_x"
    tri_min_x.drop()
    tri_min_y.name = "tri_min_y"
    tri_min_y.drop()
    tri_max_x.name = "tri_max_x"
    tri_max_x.drop()
    tri_max_y.name = "tri_max_y"
    tri_max_y.drop()

    # Calculate actual Box
    bb_min_x = Signal.max(tri_min_x, bin_min_x)
    bb_min_y = Signal.max(tri_min_y, bin_min_y)
    bb_max_x = Signal.min(tri_max_x, bin_max_x)
    bb_max_y = Signal.min(tri_max_y, bin_max_y)

    bb_min_x.name = "bb_min_x"
    bb_min_x.drop()
    bb_min_y.name = "bb_min_y"
    bb_min_y.drop()
    bb_max_x.name = "bb_max_x"
    bb_max_x.drop()
    bb_max_y.name = "bb_max_y"
    bb_max_y.drop()

    # First initial edge
    p_min_x = bb_min_x.fast_half_add_to_rounded()
    p_min_y = bb_min_y.fast_half_add_to_rounded()

    p_min_x.name = "p_min_x"
    p_min_x.drop()
    p_min_y.name = "p_min_y"
    p_min_y.drop()

    # edge functions for e0, e1, e2
    e0_00 = e0_dx * (p_min_x - v1_x) + e0_dy * (p_min_y - v1_y)
    e1_00 = e1_dx * (p_min_x - v2_x) + e1_dy * (p_min_y - v2_y)
    e2_00 = e2_dx * (p_min_x - v0_x) + e2_dy * (p_min_y - v0_y)
    # Initials of the 2x2 start threads
    # (0,0)
    # e0_00 = e0_row
    # e1_00 = e1_row
    # e2_00 = e2_row
    # (1,0)
    e0_10 = e0_00 + e0_dx
    e1_10 = e1_00 + e1_dx
    e2_10 = e2_00 + e2_dx
    # (0,1)
    e0_01 = e0_00 + e0_dy
    e1_01 = e1_00 + e1_dy
    e2_01 = e2_00 + e2_dy
    # (1,1)
    e0_11 = e0_10 + e0_dy
    e1_11 = e1_10 + e1_dy
    e2_11 = e2_10 + e2_dy

    # offsets for 2x2 threads
    e0_dx_2x = e0_dx + e0_dx
    e0_dy_2x = e0_dy + e0_dy
    e1_dx_2x = e1_dx + e1_dx
    e1_dy_2x = e1_dy + e1_dy
    e2_dx_2x = e2_dx + e2_dx
    e2_dy_2x = e2_dy + e2_dy

    # Box dimensions
    bb_start_x = bb_min_x.to_int16()
    bb_start_y = bb_min_y.to_int16()
    bb_width = bb_max_x.to_int16() - bb_start_x
    bb_height = bb_max_y.to_int16() - bb_start_y

    named_signals = auto_name_signals(locals())

    print("\n--- Running OR-Tools Optimizer ---")

    # Run the cycle-accurate schedule calculation!
    dag.schedule(hw_limits=hw_limits, pipeline_register_delay=1)

    # print("\n--- Named Results ---")
    # for name, signal in named_signals.items():
    #     print(f"{name:<18} = {signal.expr}")
