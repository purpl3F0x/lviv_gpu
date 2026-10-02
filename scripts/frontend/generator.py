import csv
from pathlib import Path

from ortools.sat.python import cp_model

DEFAULT_LATENCIES = {
    # Thread pipeline latencies.
    "fp_add": 11,
    "fp_sub": 11,
    "fp_mul": 8,
    "fp_fma": 19,
    "fp_recip": 28,
    "fp_cmp": 2,
    "mux": 1,
    "mem_read": 1,
    "mem_write": 1,
    "fx_color_mul": 2,
    "fx_color_fma": 3,
    "fx_texture_mul": 2,
    "fx_texture_fma": 3,
    "fp_to_fx2_23": 2,
    "fx_color_to_u8": 2,
    # Raster frontend operations from create_pipeline.py.
    "fp_add_sub": 11,
    "int16_add_sub": 0,
    "int16_mul": 1,
    "fp32_to_int16": 2,
    "tri_bb_min_max": 5,
    "fp_min_2": 1,
    "fp_max_2": 1,
    "fp_add_half_fast": 2,
}


def schedule_hardware_dag(
    nodes: list[str],
    edges: list[tuple[str, str]],
    latencies: dict[str, int] | None,
    resource_types: dict[str, str],
    II: int,
    area_weights: dict[str, int] = None,
    max_cycles: int = 200,
    resource_ii: dict[str, int] | None = None,
):
    """
    Schedules a computational DAG targeting hardware functional units.

    Args:
        nodes: Names/IDs of operations.
        edges: Directed data dependencies (producer, consumer).
        latencies: Execution latency per operation type (e.g. {'fadd': 4, 'fmul': 3}).
        resource_types: Map of node -> op_type.
        II: Target Initiation Interval (cycles between consecutive input sets).
        area_weights: Cost per IP core type (default = 1000 per unit).
        max_cycles: Scheduling horizon limit.
        resource_ii: Initiation interval of each resource type. Defaults to
            one cycle because the thread arithmetic units are fully pipelined.
            Set a value greater than one for a resource that cannot accept a
            new operation every cycle.
    """
    if II < 1:
        raise ValueError("II must be at least 1 cycle.")

    latency_table = dict(DEFAULT_LATENCIES)
    if latencies:
        latency_table.update(latencies)

    missing = set(resource_types.values()) - set(latency_table)
    if missing:
        raise ValueError(
            "Missing latencies for operation types: " + ", ".join(sorted(missing))
        )

    # The raster frontend can use one configurable FP unit for both add and
    # subtract. Keep the mathematical operation type for the report, but use
    # one canonical resource class for modulo allocation.
    resource_aliases = {"fp_add": "fp_add_sub", "fp_sub": "fp_add_sub"}
    add_sub_latencies = {
        latency_table[op_type]
        for op_type in ("fp_add", "fp_sub")
        if op_type in resource_types.values()
    }
    if len(add_sub_latencies) > 1:
        raise ValueError(
            "fp_add and fp_sub must have the same latency when sharing a unit."
        )

    scheduling_resource_types = {
        node: resource_aliases.get(op_type, op_type)
        for node, op_type in resource_types.items()
    }
    unique_types = sorted(list(set(scheduling_resource_types.values())))

    resource_ii = dict(resource_ii or {})
    unknown_resource_ii = set(resource_ii) - set(unique_types)
    if unknown_resource_ii:
        raise ValueError(
            "Initiation intervals provided for unknown resources: "
            + ", ".join(sorted(unknown_resource_ii))
        )
    for resource_type, initiation_interval in resource_ii.items():
        if initiation_interval < 1:
            raise ValueError("Resource initiation intervals must be at least 1 cycle.")

    model = cp_model.CpModel()

    if area_weights is None:
        area_weights = {rt: 1000 for rt in unique_types}

    # --- 1. Variables ---
    t = {u: model.NewIntVar(0, max_cycles, f"t_{u}") for u in nodes}
    m = {u: model.NewIntVar(0, II - 1, f"m_{u}") for u in nodes}
    makespan = model.NewIntVar(0, max_cycles, "makespan")

    # Number of instantiated physical functional units per resource type
    R = {rt: model.NewIntVar(1, len(nodes), f"R_{rt}") for rt in unique_types}

    # Latency controls when a result is ready. Initiation interval controls
    # how soon the same physical unit can accept the next operation.
    reservation_cycles = {
        u: resource_ii.get(scheduling_resource_types[u], 1) for u in nodes
    }

    # Whether an operation occupies each modulo slot of its repeated execution.
    # The allowed assignments correctly handle operations spanning II.
    occupied = {}
    for u in nodes:
        for s in range(II):
            occupied[u, s] = model.NewBoolVar(f"{u}_occupies_slot_{s}")
            valid_pairs = [
                (
                    start_slot,
                    int(
                        any(
                            (start_slot + offset) % II == s
                            for offset in range(reservation_cycles[u])
                        )
                    ),
                )
                for start_slot in range(II)
            ]
            model.AddAllowedAssignments([m[u], occupied[u, s]], valid_pairs)

    # --- 2. Constraints ---
    # (a) Data Precedence
    for u, v in edges:
        lat = latency_table[resource_types[u]]
        model.Add(t[v] >= t[u] + lat)

    # (b) Makespan Tracking
    for u in nodes:
        lat = latency_table[resource_types[u]]
        model.Add(makespan >= t[u] + lat)

    # (c) Modulo Binding: m[u] = t[u] % II
    for u in nodes:
        model.AddModuloEquality(m[u], t[u], II)

    # (d) Slot Capacity and modulo unit binding.
    # An operation reserves every slot in its latency window, repeated modulo II.
    for rt in unique_types:
        nodes_of_type = [u for u in nodes if scheduling_resource_types[u] == rt]
        for s in range(II):
            model.Add(sum(occupied[u, s] for u in nodes_of_type) <= R[rt])

    # --- 3. Objective ---
    # Prioritize minimizing costly functional units; break ties by minimizing total pipeline depth
    cost_expr = sum(area_weights[rt] * R[rt] for rt in unique_types) + makespan
    model.Minimize(cost_expr)

    # --- 4. Solve ---
    solver = cp_model.CpSolver()
    solver.parameters.max_time_in_seconds = 30.0
    solver.parameters.num_workers = 4
    status = solver.Solve(model)

    if status not in (cp_model.OPTIMAL, cp_model.FEASIBLE):
        raise RuntimeError(
            "No feasible schedule found within the specified cycle bound."
        )

    # --- 5. Extract Schedule & Compute Hardware Bindings ---
    schedule = {u: solver.Value(t[u]) for u in nodes}
    modulo_slots = {u: solver.Value(m[u]) for u in nodes}
    units_needed = {rt: solver.Value(R[rt]) for rt in unique_types}
    total_latency = solver.Value(makespan)

    # Compute delay-matching registers (SRL depths) needed on dependencies
    edge_delays = {}
    for u, v in edges:
        prod_ready = schedule[u] + latency_table[resource_types[u]]
        cons_start = schedule[v]
        edge_delays[(u, v)] = cons_start - prod_ready

    reservation_slots = {
        u: [s for s in range(II) if solver.BooleanValue(occupied[u, s])] for u in nodes
    }

    # Bind operations to concrete units after solving. For fully pipelined
    # resources, operations can share a unit when their issue slots differ.
    unit_assignment = {}
    for resource_type in unique_types:
        resource_nodes = [
            u for u in nodes if scheduling_resource_types[u] == resource_type
        ]
        resource_nodes.sort(key=lambda u: (schedule[u], u))
        unit_slots = []
        for node in resource_nodes:
            occupied_slots = set(reservation_slots[node])
            unit_index = next(
                (
                    index
                    for index, used_slots in enumerate(unit_slots)
                    if occupied_slots.isdisjoint(used_slots)
                ),
                None,
            )
            if unit_index is None:
                unit_index = len(unit_slots)
                unit_slots.append(set())
            unit_slots[unit_index].update(occupied_slots)
            unit_assignment[node] = f"{resource_type}_{unit_index}"

        if len(unit_slots) > solver.Value(R[resource_type]):
            raise RuntimeError(
                f"Could not bind {resource_type} operations to the solved unit count."
            )

    return {
        "schedule": schedule,
        "modulo_slots": modulo_slots,
        "units_needed": units_needed,
        "unit_assignment": unit_assignment,
        "reservation_slots": reservation_slots,
        "delays": edge_delays,
        "total_latency": total_latency,
    }


def export_resource_table(
    nodes: list[str],
    edges: list[tuple[str, str]],
    latencies: dict[str, int] | None,
    resource_types: dict[str, str],
    output_path: str | Path,
    ii_values=range(1, 51),
    area_weights: dict[str, int] = None,
    max_cycles: int = 200,
    resource_ii: dict[str, int] | None = None,
):
    """Write allocated units and latency for each requested initiation interval."""
    resource_aliases = {"fp_add": "fp_add_sub", "fp_sub": "fp_add_sub"}
    resource_columns = sorted(
        {resource_aliases.get(op_type, op_type) for op_type in resource_types.values()}
    )
    fieldnames = ["II", "total_latency", "total_units", *resource_columns]

    rows = []
    for ii in ii_values:
        result = schedule_hardware_dag(
            nodes,
            edges,
            latencies=latencies,
            resource_types=resource_types,
            II=ii,
            area_weights=area_weights,
            max_cycles=max_cycles,
            resource_ii=resource_ii,
        )
        units = result["units_needed"]
        rows.append(
            {
                "II": ii,
                "total_latency": result["total_latency"],
                "total_units": sum(units.values()),
                **{resource: units.get(resource, 0) for resource in resource_columns},
            }
        )

    output_path = Path(output_path)
    with output_path.open("w", newline="", encoding="utf-8") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    return output_path


def build_raster_frontend_graph():
    """Build the arithmetic DAG described by scripts/create_pipeline.py."""
    nodes = []
    edges = []
    resource_types = {}

    def binary(name, op_type, left, right):
        nodes.append(name)
        resource_types[name] = op_type
        for source in (left, right):
            if source in resource_types:
                edges.append((source, name))
        return name

    def unary(name, op_type, source):
        nodes.append(name)
        resource_types[name] = op_type
        if source in resource_types:
            edges.append((source, name))
        return name

    # Edge differences and reciprocal triangle area.
    e0_dx = binary("e0_dx", "fp_sub", "v2_y", "v1_y")
    e0_dy = binary("e0_dy", "fp_sub", "v1_x", "v2_x")
    e1_dx = binary("e1_dx", "fp_sub", "v0_y", "v2_y")
    e1_dy = binary("e1_dy", "fp_sub", "v2_x", "v0_x")
    e2_dx = binary("e2_dx", "fp_sub", "v1_y", "v0_y")
    e2_dy = binary("e2_dy", "fp_sub", "v0_x", "v1_x")

    area_left = binary("area_left", "fp_mul", e1_dy, e2_dx)
    area_dy = binary("area_dy", "fp_sub", "v2_y", "v0_y")
    area_dx = binary("area_dx", "fp_sub", "v1_x", "v0_x")
    area_right = binary("area_right", "fp_mul", area_dy, area_dx)
    area = binary("area", "fp_sub", area_left, area_right)
    inv_area = unary("inv_area", "fp_recip", area)

    # Triangle bounding box and intersection with the bin bounding box.
    tri_x = unary("tri_bb_x", "tri_bb_min_max", "v0_x")
    tri_y = unary("tri_bb_y", "tri_bb_min_max", "v0_y")
    bb_min_x = binary("bb_min_x", "fp_max_2", tri_x, "bin_min_x")
    bb_min_y = binary("bb_min_y", "fp_max_2", tri_y, "bin_min_y")
    bb_max_x = binary("bb_max_x", "fp_min_2", tri_x, "bin_max_x")
    bb_max_y = binary("bb_max_y", "fp_min_2", tri_y, "bin_max_y")
    p_min_x = unary("p_min_x", "fp_add_half_fast", bb_min_x)
    p_min_y = unary("p_min_y", "fp_add_half_fast", bb_min_y)

    # Initial edge values at the first 2x2 thread quad.
    for edge_index, (dx, dy, vertex) in enumerate(
        ((e0_dx, e0_dy, "v1"), (e1_dx, e1_dy, "v2"), (e2_dx, e2_dy, "v0"))
    ):
        x_delta = binary(f"e{edge_index}_x_delta", "fp_sub", p_min_x, f"{vertex}_x")
        y_delta = binary(f"e{edge_index}_y_delta", "fp_sub", p_min_y, f"{vertex}_y")
        x_term = binary(f"e{edge_index}_x_term", "fp_mul", dx, x_delta)
        y_term = binary(f"e{edge_index}_y_term", "fp_mul", dy, y_delta)
        binary(f"e{edge_index}_00", "fp_add", x_term, y_term)

    # Per-quad increments and doubled increments.
    for edge_index, (edge_dx, edge_dy) in enumerate(
        ((e0_dx, e0_dy), (e1_dx, e1_dy), (e2_dx, e2_dy))
    ):
        e00 = f"e{edge_index}_00"
        e10 = binary(f"e{edge_index}_10", "fp_add", e00, edge_dx)
        binary(f"e{edge_index}_01", "fp_add", e00, edge_dy)
        binary(f"e{edge_index}_11", "fp_add", e10, edge_dy)
        binary(f"e{edge_index}_dx_2x", "fp_add", edge_dx, edge_dx)
        binary(f"e{edge_index}_dy_2x", "fp_add", edge_dy, edge_dy)

    # Bounding-box integer outputs.
    bb_start_x = unary("bb_start_x", "fp32_to_int16", bb_min_x)
    bb_start_y = unary("bb_start_y", "fp32_to_int16", bb_min_y)
    bb_max_x_i = unary("bb_max_x_i", "fp32_to_int16", bb_max_x)
    bb_max_y_i = unary("bb_max_y_i", "fp32_to_int16", bb_max_y)
    binary("bb_width", "int16_add_sub", bb_max_x_i, bb_start_x)
    binary("bb_height", "int16_add_sub", bb_max_y_i, bb_start_y)

    return nodes, edges, resource_types


nodes, edges, resource_types = build_raster_frontend_graph()

resource_table_path = export_resource_table(
    nodes,
    edges,
    latencies=None,
    resource_types=resource_types,
    output_path=Path(__file__).with_name("frontend_resource_ii.csv"),
    ii_values=range(1, 51),
)
print(f"Resource table written to {resource_table_path}")

# Run for II = 3 (accepting a new input set every 3 clock cycles).
res = schedule_hardware_dag(
    nodes, edges, latencies=None, resource_types=resource_types, II=3
)

print(f"Total Latency: {res['total_latency']} cycles")
print(f"Allocated Units: {res['units_needed']}")
print("\nOperation Schedule:")
for u in sorted(nodes, key=lambda n: res["schedule"][n]):
    print(
        f"  Node {u:16s} ({resource_types[u]}): starts cycle {res['schedule'][u]:3d} "
        f"[slot {res['modulo_slots'][u]}] -> mapped to {res['unit_assignment'][u]} "
        f"reserves slots {res['reservation_slots'][u]}"
    )

print("\nRegister Balancing (SRL Depths):")
for (u, v), delay in res["delays"].items():
    print(f"  {u} -> {v}: delay = {delay} cycles")
