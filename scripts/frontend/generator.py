import argparse
import ast
import csv
import inspect
import struct
import textwrap
from contextlib import contextmanager
from pathlib import Path

from ortools.sat.python import cp_model

DEFAULT_LATENCIES = {
    "fp_add": 11,
    "fp_sub": 11,
    "fp_mul": 8,
    "fp_neg": 0,
    "fp_recip": 29,
    "fx_add": 2,
    "fx_sub": 2,
    "fx_mul": 5,
    "fx_min_2": 1,
    "fx_max_2": 1,
    "fp_to_fx14_17": 6,
    "fp_to_fx27_16": 6,
    "fp_to_fx5_13": 6,
    "fp32_to_uint12": 2,
    "int_add": 1,
    "int_sub": 1,
    # Raster frontend operations from create_pipeline.py.
    "int16_add_sub": 0,
    "fp32_to_int16": 2,
    "tri_bb_min_max": 5,
    "fp_min_2": 1,
    "fp_max_2": 1,
    "fp_add_half_fast": 2,
}

# Add and subtract of the same number type share one configurable unit.
RESOURCE_ALIASES = {
    "fp_add": "fp_add_sub",
    "fp_sub": "fp_add_sub",
    "fx_add": "fx_add_sub",
    "fx_sub": "fx_add_sub",
}

FP = "fp"
FX = "fx"
INT16 = "int16"
UINT12 = "uint12"
_NOT_CONSTANT = object()


class Value:
    """Symbolic signal; arithmetic on it records operations in its graph."""

    KIND = None
    ADD_OP = None
    SUB_OP = None
    MUL_OP = None
    NEG_OP = None
    OP_LATENCIES = {}

    def __init__(
        self,
        graph,
        name,
        kind,
        op=None,
        operands=(),
        constant=_NOT_CONSTANT,
        producer=None,
        bit_slice=None,
    ):
        self.graph = graph
        self.name = name
        self.kind = kind
        self.op = op
        self.operands = operands
        self.constant = constant
        self.name_assigned = False
        self.producer = producer
        self.bit_slice = bit_slice

    def _binary(self, other, op):
        if not isinstance(other, Value):
            if isinstance(other, (int, float)) and not isinstance(other, bool):
                other = self.graph.constant(type(self), other)
            else:
                return NotImplemented
        if other.graph is not self.graph:
            raise ValueError("Operands belong to different graphs.")
        if other.KIND != self.KIND:
            raise TypeError(
                f"Cannot mix {type(self).__name__} and {type(other).__name__}."
            )
        op_type = getattr(type(self), f"{op.upper()}_OP")
        if op_type is None:
            raise TypeError(f"{type(self).__name__} does not support {op}.")
        return self.graph._record(op_type, type(self), self, other, expression=op)

    def __add__(self, other):
        return self._binary(other, "add")

    def __sub__(self, other):
        return self._binary(other, "sub")

    def __mul__(self, other):
        return self._binary(other, "mul")

    def __neg__(self):
        if self.NEG_OP is None:
            raise TypeError(f"{type(self).__name__} does not support negation.")
        return self.graph._record(self.NEG_OP, type(self), self, expression="neg")

    def __radd__(self, other):
        return self.__add__(other)

    def __rsub__(self, other):
        if isinstance(other, (int, float)) and not isinstance(other, bool):
            return self.graph.constant(type(self), other).__sub__(self)
        return NotImplemented

    def __rmul__(self, other):
        return self.__mul__(other)

    def __rtruediv__(self, other):
        if other != 1 or type(self) is not Float:
            raise TypeError("Only the float reciprocal 1 / x is supported.")
        return self.graph._record("fp_recip", Float, self)

    def __repr__(self):
        return f"{type(self).__name__}:{self.name}"


class Float(Value):
    KIND = FP
    ADD_OP = "fp_add"
    SUB_OP = "fp_sub"
    MUL_OP = "fp_mul"
    NEG_OP = "fp_neg"
    OP_LATENCIES = {
        "fp_add": 11,
        "fp_sub": 11,
        "fp_mul": 8,
        "fp_neg": 0,
        "fp_recip": 29,
        "fp_to_fx14_17": 6,
        "fp_to_fx27_16": 6,
        "fp32_to_uint12": 2,
        "tri_bb_min_max": 6,
        "fp_min_2": 1,
        "fp_max_2": 1,
        "fp_add_half_fast": 2,
    }


class Fx14_17(Value):
    KIND = "fx14_17"
    SIGNED = True
    INTEGER_BITS = 14
    FRACTIONAL_BITS = 17
    OP_LATENCIES = {"fp_to_fx14_17": 6}


class Fx27_16(Value):
    KIND = "fx27_16"
    SIGNED = True
    INTEGER_BITS = 27
    FRACTIONAL_BITS = 16
    OP_LATENCIES = {"fp_to_fx27_16": 6}


class Int16(Value):
    KIND = INT16
    ADD_OP = "int16_add_sub"
    SUB_OP = "int16_add_sub"
    OP_LATENCIES = {"int16_add_sub": 1, "fp32_to_int16": 6}


class Fx5_13(Value):
    KIND = "fx5_13"
    SIGNED = True
    INTEGER_BITS = 5
    FRACTIONAL_BITS = 13
    OP_LATENCIES = {"fp_to_fx5_13": 6}


class UInt1(Value):
    KIND = "uint1"
    BITS = 1


class UInt3(Value):
    KIND = "uint3"
    BITS = 3


class UInt4(Value):
    KIND = "uint4"
    BITS = 4


class UInt8(Value):
    KIND = "uint8"
    BITS = 8


class UInt32(Value):
    KIND = "uint32"
    BITS = 32


class UInt12(Value):
    KIND = UINT12
    SIGNED = False
    BITS = 12
    ADD_OP = "int_add"
    SUB_OP = "int_sub"
    OP_LATENCIES = {"fp32_to_uint12": 2, "int_add": 1, "int_sub": 1}


class TileAddrX(Value):
    KIND = "tile_addr_x"
    SIGNED = False
    BITS = 6
    ADD_OP = "int_add"
    SUB_OP = "int_sub"
    OP_LATENCIES = {"int_add": 1, "int_sub": 1}


class TileAddrY(Value):
    KIND = "tile_addr_y"
    SIGNED = False
    BITS = 6
    ADD_OP = "int_add"
    SUB_OP = "int_sub"
    OP_LATENCIES = {"int_add": 1, "int_sub": 1}


ANNOTATION_TYPES = {
    Float,
    Fx14_17,
    Fx27_16,
    Fx5_13,
    Int16,
    UInt1,
    UInt3,
    UInt4,
    UInt8,
    UInt32,
    UInt12,
    TileAddrX,
    TileAddrY,
}
_TRACE_SCOPE = []
_TRACE_CALLS = {}
_TRACE_ROOT = None


@contextmanager
def _trace_scope(function_name):
    call_index = _TRACE_CALLS.get(function_name, 0)
    _TRACE_CALLS[function_name] = call_index + 1
    prefix = None if function_name == _TRACE_ROOT else f"{function_name}_{call_index}"
    _TRACE_SCOPE.append(prefix)
    try:
        yield
    finally:
        _TRACE_SCOPE.pop()


def _float_to_fixed(value: Float, result_type: type[Value], operation: str) -> Value:
    if not isinstance(value, Float):
        raise TypeError(f"{operation}() expects a float value.")
    return value.graph._record(operation, result_type, value)


def fp_to_fx14_17(value: Float) -> Fx14_17:
    return _float_to_fixed(value, Fx14_17, "fp_to_fx14_17")


def fp_to_fx27_16(value: Float) -> Fx27_16:
    return _float_to_fixed(value, Fx27_16, "fp_to_fx27_16")


def fp_to_fx5_13(value: Float) -> Fx5_13:
    return _float_to_fixed(value, Fx5_13, "fp_to_fx5_13")


def fp32_to_uint12(value: Float) -> UInt12:
    if not isinstance(value, Float):
        raise TypeError("fp32_to_uint12() expects a float value.")
    return value.graph._record("fp32_to_uint12", UInt12, value)


def _uint12_to_local_quad(value: UInt12, result_type, tile_addr_parameter: str):
    if not isinstance(value, UInt12):
        raise TypeError("uint12_to_local_quad() expects a UInt12 value.")
    if value.constant is not _NOT_CONSTANT:
        mask = (1 << result_type.BITS) - 1
        return value.graph.constant(result_type, (value.constant >> 1) & mask)
    return result_type(
        value.graph,
        f"{value.name}_local_quad",
        result_type.KIND,
        operands=(value,),
        producer=value if value.op is not None else value.producer,
        bit_slice=(f"gpu_types_pkg::{tile_addr_parameter}", 1),
    )


def uint12_to_local_quad_x(value: UInt12) -> TileAddrX:
    return _uint12_to_local_quad(value, TileAddrX, "TILE_ADDR_X")


def uint12_to_local_quad_y(value: UInt12) -> TileAddrY:
    return _uint12_to_local_quad(value, TileAddrY, "TILE_ADDR_Y")


def _record_custom(op_type: str, result_type: type[Value], *operands: Value) -> Value:
    if not operands or any(not isinstance(operand, Value) for operand in operands):
        raise TypeError(f"{op_type}() expects symbolic Value arguments.")
    graph = operands[0].graph
    if any(operand.graph is not graph for operand in operands):
        raise ValueError("Operands belong to different graphs.")
    return graph._record(op_type, result_type, *operands)


def tri_bb_min_max(x0: Float, x1: Float, x2: Float) -> tuple[Float, Float]:
    if any(not isinstance(value, Float) for value in (x0, x1, x2)):
        raise TypeError("tri_bb_min_max() expects float arguments.")
    operation = _record_custom("tri_bb_min_max", Float, x0, x1, x2)
    return (
        operation.graph.output(operation, "min"),
        operation.graph.output(operation, "max"),
    )


def fp_max_2(a: Float, b: Float) -> Float:
    if not isinstance(a, Float) or not isinstance(b, Float):
        raise TypeError("fp_max_2() expects float arguments.")
    return _record_custom("fp_max_2", Float, a, b)


def fp_min_2(a: Float, b: Float) -> Float:
    if not isinstance(a, Float) or not isinstance(b, Float):
        raise TypeError("fp_min_2() expects float arguments.")
    return _record_custom("fp_min_2", Float, a, b)


def fx_max_2(a: Value, b: Value) -> Value:
    if type(a) not in (Fx14_17, Fx27_16) or type(b) is not type(a):
        raise TypeError("fx_max_2() expects matching fixed-point arguments.")
    return _record_custom("fx_max_2", type(a), a, b)


def fx_min_2(a: Value, b: Value) -> Value:
    if type(a) not in (Fx14_17, Fx27_16) or type(b) is not type(a):
        raise TypeError("fx_min_2() expects matching fixed-point arguments.")
    return _record_custom("fx_min_2", type(a), a, b)


def fp_add_half_fast(value: Float) -> Float:
    if not isinstance(value, Float):
        raise TypeError("fp_add_half_fast() expects a float argument.")
    return _record_custom("fp_add_half_fast", Float, value)


def fp32_to_int16(value: Float) -> Int16:
    if not isinstance(value, Float):
        raise TypeError("fp32_to_int16() expects a float argument.")
    return _record_custom("fp32_to_int16", Int16, value)


def int16_add_sub(a: Int16, b: Int16) -> Int16:
    if not isinstance(a, Int16) or not isinstance(b, Int16):
        raise TypeError("int16_add_sub() expects int16 arguments.")
    return _record_custom("int16_add_sub", Int16, a, b)


def _bind_assignment(value, name, scope, loop_names):
    if not isinstance(value, Value) or value.constant is not _NOT_CONSTANT:
        return value
    if value.name_assigned:
        return value
    indices = [
        scope[loop_name]
        for loop_name in loop_names
        if isinstance(scope.get(loop_name), int)
    ]
    prefix = next((item for item in reversed(_TRACE_SCOPE) if item), None)
    parts = [part for part in (prefix, name) if part]
    if indices:
        parts.extend(map(str, indices))
    value.name = "_".join(parts)
    value.name_assigned = True
    return value


def _bind_tuple_assignment(values, names, scope, loop_names):
    if not isinstance(values, tuple) or len(values) != len(names):
        raise TypeError(f"Expected {len(names)} values for tuple assignment.")
    return tuple(
        _bind_assignment(value, name, scope, loop_names)
        for value, name in zip(values, names)
    )


class _AssignmentNamer(ast.NodeTransformer):
    def __init__(self):
        self.loop_names = []

    def _wrap(self, value, name):
        return ast.Call(
            func=ast.Name(id="_bind_assignment", ctx=ast.Load()),
            args=[
                value,
                ast.Constant(name),
                ast.Call(
                    func=ast.Name(id="locals", ctx=ast.Load()), args=[], keywords=[]
                ),
                ast.Tuple(
                    elts=[ast.Constant(loop_name) for loop_name in self.loop_names],
                    ctx=ast.Load(),
                ),
            ],
            keywords=[],
        )

    def visit_Assign(self, node):
        self.generic_visit(node)
        if len(node.targets) == 1:
            target = node.targets[0]
            if isinstance(target, ast.Name):
                node.value = self._wrap(node.value, target.id)
            elif isinstance(target, (ast.Tuple, ast.List)) and all(
                isinstance(element, ast.Name) for element in target.elts
            ):
                node.value = ast.Call(
                    func=ast.Name(id="_bind_tuple_assignment", ctx=ast.Load()),
                    args=[
                        node.value,
                        ast.Tuple(
                            elts=[ast.Constant(element.id) for element in target.elts],
                            ctx=ast.Load(),
                        ),
                        ast.Call(
                            func=ast.Name(id="locals", ctx=ast.Load()),
                            args=[],
                            keywords=[],
                        ),
                        ast.Tuple(
                            elts=[
                                ast.Constant(loop_name) for loop_name in self.loop_names
                            ],
                            ctx=ast.Load(),
                        ),
                    ],
                    keywords=[],
                )
        return node

    def visit_AnnAssign(self, node):
        self.generic_visit(node)
        if isinstance(node.target, ast.Name) and node.value is not None:
            node.value = self._wrap(node.value, node.target.id)
        return node

    def visit_FunctionDef(self, node):
        self.generic_visit(node)
        node.body = [
            ast.With(
                items=[
                    ast.withitem(
                        context_expr=ast.Call(
                            func=ast.Name(id="_trace_scope", ctx=ast.Load()),
                            args=[ast.Constant(node.name)],
                            keywords=[],
                        ),
                        optional_vars=None,
                    )
                ],
                body=node.body,
            )
        ]
        return node

    def visit_For(self, node):
        self.generic_visit(node.iter)
        names = [
            child.id for child in ast.walk(node.target) if isinstance(child, ast.Name)
        ]
        self.loop_names.extend(names)
        node.body = [self.visit(statement) for statement in node.body]
        node.orelse = [self.visit(statement) for statement in node.orelse]
        del self.loop_names[-len(names) :]
        return node


def trace(function, return_graph=False):
    """Trace a typed function, using assignment targets as operation names."""
    parameters = inspect.signature(function).parameters
    for name, parameter in parameters.items():
        if parameter.annotation not in ANNOTATION_TYPES:
            raise TypeError(
                f"Parameter {name} must use a supported symbolic value type."
            )

    function_nodes = []
    visited = set()

    def collect(current):
        if current.__name__ in visited:
            return
        visited.add(current.__name__)
        parsed = ast.parse(textwrap.dedent(inspect.getsource(current)))
        definition = next(
            node
            for node in parsed.body
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
            and node.name == current.__name__
        )
        for call in ast.walk(definition):
            if not isinstance(call, ast.Call) or not isinstance(call.func, ast.Name):
                continue
            helper = function.__globals__.get(call.func.id)
            if (
                inspect.isfunction(helper)
                and helper.__code__.co_filename == function.__code__.co_filename
            ):
                collect(helper)
        function_nodes.append(definition)

    collect(function)
    module = ast.Module(body=function_nodes, type_ignores=[])
    module = _AssignmentNamer().visit(module)
    ast.fix_missing_locations(module)
    namespace = dict(function.__globals__)
    namespace["_bind_assignment"] = _bind_assignment
    namespace["_bind_tuple_assignment"] = _bind_tuple_assignment
    exec(compile(module, inspect.getsourcefile(function) or "<dag>", "exec"), namespace)
    traced_function = namespace[function.__name__]

    graph = Graph()
    inputs = [
        graph.input(name, parameter.annotation)
        for name, parameter in parameters.items()
    ]
    global _TRACE_ROOT
    _TRACE_ROOT = function.__name__
    _TRACE_CALLS.clear()
    try:
        returned = traced_function(*inputs)
        graph.returns = returned if isinstance(returned, tuple) else (returned,)
        if any(not isinstance(value, Value) for value in graph.returns):
            raise TypeError("Traced functions must return symbolic values.")
    finally:
        _TRACE_ROOT = None
        _TRACE_SCOPE.clear()
    return graph if return_graph else graph.to_dag()


class Graph:
    """Collects operations traced from symbolic Python expressions."""

    def __init__(self):
        self.operations: list[Value] = []
        self.inputs = []
        self.returns = ()
        self._constants = {}
        self._expressions = {}

    def input(self, name: str, value_type: type[Value] = Float) -> Value:
        if value_type not in ANNOTATION_TYPES:
            raise ValueError(f"Unknown symbolic type: {value_type}")
        value = value_type(self, name, value_type.KIND)
        self.inputs.append(value)
        return value

    def constant(self, value_type: type[Value], value):
        if value_type not in ANNOTATION_TYPES:
            raise TypeError(f"Unsupported constant type: {value_type.__name__}")
        if not isinstance(value, (int, float)) or isinstance(value, bool):
            raise TypeError("Symbolic constants must be int or float values.")
        if value_type is Int16:
            value = int(value)
        elif value_type in (
            UInt1,
            UInt3,
            UInt4,
            UInt8,
            UInt32,
            UInt12,
            TileAddrX,
            TileAddrY,
        ):
            value = int(value)
            if not 0 <= value < (1 << value_type.BITS):
                raise ValueError(
                    f"{value_type.__name__} constants must be in the range "
                    f"0..{(1 << value_type.BITS) - 1}."
                )
        else:
            value = float(value)
        key = (value_type, value)
        if key not in self._constants:
            self._constants[key] = value_type(
                self, f"const_{value}", value_type.KIND, constant=value
            )
        return self._constants[key]

    def _record(self, op, value_type, *operands, expression=None):
        if any(operand.graph is not self for operand in operands):
            raise ValueError("Operands belong to different graphs.")
        if op.startswith(("fp_", "fp32_")) or op == "tri_bb_min_max":
            if any(type(operand) is not Float for operand in operands):
                raise TypeError(f"{op} requires Float operands.")

        if all(operand.constant is not _NOT_CONSTANT for operand in operands):
            folded = self._fold(op, expression, value_type, operands)
            if folded is not _NOT_CONSTANT:
                return self.constant(value_type, folded)

        commutative = op.endswith(("_add", "_mul", "_min_2", "_max_2"))
        operand_key = tuple(id(operand) for operand in operands)
        if commutative:
            operand_key = tuple(sorted(operand_key))
        cache_key = (op, expression, value_type, operand_key)
        if cache_key in self._expressions:
            return self._expressions[cache_key]

        value = value_type(
            self, f"{op}_{len(self.operations)}", value_type.KIND, op, operands
        )
        self.operations.append(value)
        value.expression = expression
        self._expressions[cache_key] = value
        return value

    def output(self, producer: Value, output_name: str) -> Value:
        if producer.graph is not self or producer.op is None:
            raise ValueError("Output producer must be an operation in this graph.")
        value = type(producer)(
            self,
            f"{producer.name}_{output_name}",
            producer.kind,
            producer=producer,
        )
        value.output_port = output_name
        return value

    @staticmethod
    def _fold(op, expression, value_type, operands):
        values = [operand.constant for operand in operands]
        if expression == "add":
            return values[0] + values[1]
        if expression == "sub":
            return values[0] - values[1]
        if expression == "mul":
            return values[0] * values[1]
        if expression == "neg":
            return -values[0]
        if op == "fp_recip":
            return 1.0 / values[0]
        if op in ("fp_min_2", "fx_min_2"):
            return min(values)
        if op in ("fp_max_2", "fx_max_2"):
            return max(values)
        if op in ("fp_to_fx14_17", "fp_to_fx27_16", "fp_to_fx5_13"):
            return values[0]
        if op == "fp32_to_int16":
            return int(values[0])
        return _NOT_CONSTANT

    def to_dag(self):
        """Return (nodes, edges, resource_types) for schedule_hardware_dag()."""
        nodes = [value.name for value in self.operations]
        duplicates = sorted({name for name in nodes if nodes.count(name) > 1})
        if duplicates:
            raise ValueError("Duplicate node names: " + ", ".join(duplicates))

        resource_types = {value.name: value.op for value in self.operations}
        edges = list(
            dict.fromkeys(
                (
                    (
                        source.producer.name
                        if source.producer is not None
                        else source.name
                    ),
                    value.name,
                )
                for value in self.operations
                for source in value.operands
                if source.op is not None or source.producer is not None
            )
        )
        return nodes, edges, resource_types


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
        II: Minimum number of cycles between input sets. Later launches are allowed.
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
    for value_type in ANNOTATION_TYPES:
        latency_table.update(value_type.OP_LATENCIES)
    if latencies:
        latency_table.update(latencies)

    missing = set(resource_types.values()) - set(latency_table)
    if missing:
        raise ValueError(
            "Missing latencies for operation types: " + ", ".join(sorted(missing))
        )

    used_types = set(resource_types.values())
    for shared in set(RESOURCE_ALIASES.values()):
        shared_latencies = {
            latency_table[op_type]
            for op_type, alias in RESOURCE_ALIASES.items()
            if alias == shared and op_type in used_types
        }
        if len(shared_latencies) > 1:
            raise ValueError(f"Operations sharing {shared} must have the same latency.")

    scheduling_resource_types = {
        node: RESOURCE_ALIASES.get(op_type, op_type)
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

    unit_assignment = {}
    unit_assignments_by_iteration = {}
    units_needed = {}
    for resource_type in unique_types:
        resource_nodes = [
            node for node in nodes if scheduling_resource_types[node] == resource_type
        ]
        copies = {
            node: max(
                1,
                (reservation_cycles[node] + II - 1) // II,
            )
            for node in resource_nodes
        }
        vertices = [
            (node, copy_index)
            for node in resource_nodes
            for copy_index in range(copies[node])
        ]
        conflicts = {vertex: set() for vertex in vertices}

        for node in resource_nodes:
            for first_copy in range(copies[node]):
                for second_copy in range(first_copy + 1, copies[node]):
                    first = (node, first_copy)
                    second = (node, second_copy)
                    conflicts[first].add(second)
                    conflicts[second].add(first)

        for first_index, first_node in enumerate(resource_nodes):
            for second_node in resource_nodes[first_index + 1 :]:
                first_start = schedule[first_node]
                second_start = schedule[second_node]
                first_reservation = reservation_cycles[first_node]
                second_reservation = reservation_cycles[second_node]
                overlap_in_one_input = (
                    first_start < second_start + second_reservation
                    and second_start < first_start + first_reservation
                )
                overlap_across_inputs = (
                    first_start - second_start + first_reservation - 1 >= II
                    or second_start - first_start + second_reservation - 1 >= II
                )
                if overlap_in_one_input or overlap_across_inputs:
                    for first_copy in range(copies[first_node]):
                        for second_copy in range(copies[second_node]):
                            first = (first_node, first_copy)
                            second = (second_node, second_copy)
                            conflicts[first].add(second)
                            conflicts[second].add(first)

        colors = {}
        uncolored = set(vertices)
        while uncolored:
            vertex = max(
                uncolored,
                key=lambda item: (
                    len({colors[n] for n in conflicts[item] if n in colors}),
                    len(conflicts[item]),
                    item[0],
                    item[1],
                ),
            )
            unavailable = {colors[n] for n in conflicts[vertex] if n in colors}
            color = next(
                candidate
                for candidate in range(len(vertices))
                if candidate not in unavailable
            )
            colors[vertex] = color
            uncolored.remove(vertex)

        color_names = {
            color: f"{resource_type}_{index}"
            for index, color in enumerate(sorted(set(colors.values())))
        }
        units_needed[resource_type] = len(color_names)
        for node in resource_nodes:
            assignments = [
                color_names[colors[node, copy_index]]
                for copy_index in range(copies[node])
            ]
            unit_assignments_by_iteration[node] = assignments
            unit_assignment[node] = ", ".join(assignments)

    return {
        "schedule": schedule,
        "operation_latencies": {
            node: latency_table[resource_types[node]] for node in nodes
        },
        "end_cycles": {
            node: schedule[node] + latency_table[resource_types[node]] for node in nodes
        },
        "modulo_slots": modulo_slots,
        "units_needed": units_needed,
        "unit_assignment": unit_assignment,
        "unit_assignments_by_iteration": unit_assignments_by_iteration,
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
    resource_columns = sorted(
        {RESOURCE_ALIASES.get(op_type, op_type) for op_type in resource_types.values()}
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


def raster_frontend(
    v0_x: Float,
    v0_y: Float,
    v1_x: Float,
    v1_y: Float,
    v2_x: Float,
    v2_y: Float,
    bin_min_x: Float,
    bin_min_y: Float,
    bin_max_x: Float,
    bin_max_y: Float,
    v0_u: Float,
    v0_v: Float,
    v1_u: Float,
    v1_v: Float,
    v2_u: Float,
    v2_v: Float,
):

    dx_0 = v2_y - v1_y
    dx_1 = v0_y - v2_y
    dx_2 = v1_y - v0_y

    dy_0 = v1_x - v2_x
    dy_1 = v2_x - v0_x
    dy_2 = v0_x - v1_x

    Area = dy_2 * dx_1 - dy_1 * dx_2

    invArea = 1.0 / Area

    min_x, max_x = tri_bb_min_max(v0_x, v1_x, v2_x)
    min_y, max_y = tri_bb_min_max(v0_y, v1_y, v2_y)

    # # ceil, floor here
    bb_min_x = fp_max_2(min_x, bin_min_x)
    bb_min_y = fp_max_2(min_y, bin_min_y)
    bb_max_x = fp_min_2(max_x, bin_max_x)
    bb_max_y = fp_min_2(max_y, bin_max_y)

    p_min_x = fp_add_half_fast(bb_min_x)
    p_min_y = fp_add_half_fast(bb_min_y)
    p_max_x = fp_add_half_fast(bb_max_x)
    p_max_y = fp_add_half_fast(bb_max_y)

    w0 = fp_to_fx27_16(dy_0 * (v1_y - p_min_y) + dx_0 * (v1_x - p_min_x))
    w1 = fp_to_fx27_16(dy_1 * (v2_x - p_min_x) + dx_1 * (v2_y - p_min_y))
    w2 = fp_to_fx27_16(dy_2 * (v0_x - p_min_x) + dx_2 * (v0_y - p_min_y))

    dx0_fx = fp_to_fx14_17(dx_0)
    dx1_fx = fp_to_fx14_17(dx_1)
    dx2_fx = fp_to_fx14_17(dx_2)
    dy0_fx = fp_to_fx14_17(dy_0)
    dy1_fx = fp_to_fx14_17(dy_1)
    dy2_fx = fp_to_fx14_17(dy_2)

    bb_min_x_int = fp32_to_uint12(bb_min_x)
    bb_min_y_int = fp32_to_uint12(bb_min_y)
    bb_max_x_int = fp32_to_uint12(bb_max_x)
    bb_max_y_int = fp32_to_uint12(bb_max_y)

    minX_local = uint12_to_local_quad_x(bb_min_x_int)
    minY_local = uint12_to_local_quad_y(bb_min_y_int)
    maxX_local = uint12_to_local_quad_x(bb_max_x_int)
    maxY_local = uint12_to_local_quad_y(bb_max_y_int)
    bb_width = maxX_local - minX_local
    bb_height = maxY_local - minY_local

    # e0_dx_plus_dy = dx0_fx + dy0_fx
    # e1_dx_plus_dy = dx1_fx + dy1_fx
    # e2_dx_plus_dy = dx2_fx + dy2_fx

    v0_u_fixed = fp_to_fx5_13(v0_u)
    v0_v_fixed = fp_to_fx5_13(v0_v)
    v1_u_fixed = fp_to_fx5_13(v1_u)
    v1_v_fixed = fp_to_fx5_13(v1_v)
    v2_u_fixed = fp_to_fx5_13(v2_u)
    v2_v_fixed = fp_to_fx5_13(v2_v)

    return (
        invArea,
        w0,
        w1,
        w2,
        dx0_fx,
        dx1_fx,
        dx2_fx,
        dy0_fx,
        dy1_fx,
        dy2_fx,
        # e0_dx_plus_dy,
        # e1_dx_plus_dy,
        # e2_dx_plus_dy,
        bb_width,
        bb_height,
        minX_local,
        minY_local,
        v0_u_fixed,
        v0_v_fixed,
        v1_u_fixed,
        v1_v_fixed,
        v2_u_fixed,
        v2_v_fixed,
    )


def value_width(value):
    value_type = type(value)
    if value_type is Float:
        return 32
    if value_type in (Fx14_17, Fx27_16, Fx5_13):
        return value_type.INTEGER_BITS + value_type.FRACTIONAL_BITS
    return getattr(value_type, "BITS", 16)


def pipeline_schedule(graph):
    latencies = dict(DEFAULT_LATENCIES)
    for value_type in ANNOTATION_TYPES:
        latencies.update(value_type.OP_LATENCIES)
    needed = set()

    def retain(value):
        producer = value.producer or value
        if producer.op is not None and producer not in needed:
            needed.add(producer)
            for operand in producer.operands:
                retain(operand)

    for value in graph.returns:
        retain(value)
    operations = [value for value in graph.operations if value in needed]
    starts = {}
    ends = {}

    def ready(value):
        return ends.get(value.producer or value, 0)

    for value in operations:
        starts[value] = max((ready(operand) for operand in value.operands), default=0)
        ends[value] = starts[value] + latencies[value.op]
    total = max((ready(value) for value in graph.returns), default=0)
    consumers = {value: [] for value in operations}
    for value in operations:
        for operand in value.operands:
            producer = operand.producer or operand
            if producer in consumers:
                consumers[producer].append(value)
    returned = {value.producer or value for value in graph.returns}
    for value in reversed(operations):
        if value_width(value) <= max(
            value_width(operand) for operand in value.operands
        ):
            continue
        deadlines = [starts[consumer] for consumer in consumers[value]]
        if value in returned:
            deadlines.append(total)
        starts[value] = min(deadlines) - latencies[value.op]
        ends[value] = starts[value] + latencies[value.op]
    return operations, starts, ends, latencies, total


def export_pipeline_rtl(
    graph,
    output_path,
    module_name="raster_frontend_core",
    latency_name="RASTER_FRONTEND_LATENCY",
):
    """Write an includable module; the latency localparam sits at file scope."""
    operations, starts, ends, latencies, total = pipeline_schedule(graph)
    declarations = []
    logic = []
    delays = {}

    def declaration(value, name):
        types = {
            Float: "float_t",
            Fx14_17: "fx_14_17_t",
            Fx27_16: "fx_27_16_t",
            Fx5_13: "fx_5_13_t",
            Int16: "int16_t",
            TileAddrX: "tile_addr_x_t",
            TileAddrY: "tile_addr_y_t",
            UInt12: "uint12_t",
        }
        if type(value) is UInt1:
            return f"logic {name}"
        if type(value) in (UInt3, UInt4, UInt8, UInt32):
            return f"logic [{value_width(value)-1}:0] {name}"
        return f"  gpu_types_pkg::{types[type(value)]} {name}"

    def rtl_width(value):
        if type(value) is TileAddrX:
            return "$bits(gpu_types_pkg::tile_addr_x_t)"
        if type(value) is TileAddrY:
            return "$bits(gpu_types_pkg::tile_addr_y_t)"
        return value_width(value)

    def base(value):
        if value.constant is not _NOT_CONSTANT:
            width = value_width(value)
            if type(value) is Float:
                bits = struct.unpack(">I", struct.pack(">f", value.constant))[0]
            elif type(value) in (Fx14_17, Fx27_16, Fx5_13):
                bits = int(value.constant * (1 << type(value).FRACTIONAL_BITS))
            else:
                bits = int(value.constant)
            return f"{width}'h{bits & ((1 << width)-1):x}", 0
        if value.producer is not None:
            producer = value.producer
            signal = f"n_{producer.name}"
            if value.bit_slice is not None:
                high, low = value.bit_slice
                signal += f"[{high}:{low}]"
            else:
                signal = f"n_{producer.name}_{value.output_port}"
            return signal, ends[producer]
        return (f"n_{value.name}", ends[value]) if value.op else (f"in_{value.name}", 0)

    def aligned(value, cycle):
        signal, ready_cycle = base(value)
        depth = cycle - ready_cycle
        if depth < 0:
            raise ValueError(f"{value.name} is not ready at cycle {cycle}.")
        if depth == 0 or value.constant is not _NOT_CONSTANT:
            return signal
        key = (signal, depth)
        if key not in delays:
            name = f"delay_{len(delays)}"
            delays[key] = name
            declarations.append(declaration(value, name) + ";")
            logic.append(
                f"delay_pipe #(.WIDTH({rtl_width(value)}), .STAGES({depth})) "
                f"u_{name} (.clk(clk), .rst_n(1'b1), .clken(clken), "
                f".data_in({signal}), .data_out({name}));"
            )
        return delays[key]

    def inline_pipeline(value, expression):
        name = f"n_{value.name}"
        latency = latencies[value.op]
        if latency == 0:
            logic.append(f"assign {name} = {expression};")
        else:
            pipe = f"pipe_{value.name}"
            declarations.append(declaration(value, pipe) + ";")
            logic.append(f"assign {pipe} = {expression};")
            logic.append(
                f"delay_pipe #(.WIDTH({rtl_width(value)}), .STAGES({latency})) "
                f"u_pipe_{value.name} (.clk(clk), .rst_n(1'b1), .clken(clken), "
                f".data_in({pipe}), .data_out({name}));"
            )

    for value in operations:
        name = f"n_{value.name}"
        declarations.append(declaration(value, name) + ";")
        operands = [aligned(operand, starts[value]) for operand in value.operands]
        latency = latencies[value.op]
        ports = [".aclk(clk)", ".aclken(clken)", ".valid_in(1'b1)"]
        if value.op == "fp_neg":
            inline_pipeline(value, f"{operands[0]} ^ 32'h80000000")
            continue
        if value.op in ("fp_add", "fp_sub", "fp_mul", "fp_recip", "fp32_to_int16"):
            ports.append(f".a({operands[0]})")
            if len(operands) == 2:
                ports.append(f".b({operands[1]})")
            ports.append(f".result({name})")
            logic.append(
                f"{value.op} #(.LATENCY({latency})) u_{value.name} ({', '.join(ports)});"
            )
        elif value.op in (
            "fp32_to_uint12",
            "fp_to_fx14_17",
            "fp_to_fx27_16",
            "fp_to_fx5_13",
        ):
            logic.append(
                f"{value.op} #(.LATENCY({latency})) u_{value.name} "
                f"(.aclk(clk), .aclken(clken), .s_axis_a_tvalid(1'b1), "
                f".s_axis_a_tdata({operands[0]}), .m_axis_result_tvalid(), "
                f".m_axis_result_tdata({name}));"
            )
        elif value.op == "tri_bb_min_max":
            declarations.extend(
                [
                    declaration(value, f"{name}_min") + ";",
                    declaration(value, f"{name}_max") + ";",
                ]
            )
            logic.append(
                f"tri_bb_min_max u_{value.name} (.clk(clk), .clken(clken), .rst_n(rst_n), "
                f".f_a({operands[0]}), .f_b({operands[1]}), .f_c({operands[2]}), "
                f".f_min_floor({name}_min), .f_max_ceil({name}_max));"
            )
        elif value.op in ("fp_min_2", "fp_max_2", "fp_add_half_fast"):
            ports = [".clk(clk)", ".clken(clken)", ".rst_n(rst_n)"]
            if value.op == "fp_add_half_fast":
                ports.extend([f".f_in({operands[0]})", f".f_out({name})"])
            else:
                suffix = "min" if value.op == "fp_min_2" else "max"
                ports.extend(
                    [
                        f".f_a({operands[0]})",
                        f".f_b({operands[1]})",
                        f".f_{suffix}({name})",
                    ]
                )
            logic.append(f"{value.op} u_{value.name} ({', '.join(ports)});")
        elif value.op in ("int_add", "int_sub"):
            if latency != 1:
                raise ValueError(f"{value.op} RTL has a fixed latency of one cycle.")
            if type(value) is UInt12:
                operand_type = UInt12
            elif type(value) in (TileAddrX, TileAddrY):
                operand_type = type(value)
            else:
                raise TypeError(f"{value.op} has an unsupported integer result type.")
            if any(type(operand) is not operand_type for operand in value.operands):
                raise TypeError(
                    f"{value.op} requires matching {operand_type.__name__} operands."
                )
            logic.append(
                f"{value.op} #(.WIDTH({rtl_width(value)})) u_{value.name} "
                f"(.clk(clk), .clken(clken), .a({operands[0]}), "
                f".b({operands[1]}), .s({name}));"
            )
        elif value.op == "int16_add_sub" or value.op in (
            "fx_add",
            "fx_sub",
            "fx_mul",
            "fx_min_2",
            "fx_max_2",
        ):
            operator = {"add": "+", "sub": "-", "mul": "*"}.get(value.expression)
            if operator:
                expression = f"$signed({operands[0]}) {operator} $signed({operands[1]})"
                if value.expression == "mul" and type(value) in (Fx14_17, Fx27_16):
                    width = 2 * max(value_width(operand) for operand in value.operands)
                    shift = (
                        sum(type(operand).FRACTIONAL_BITS for operand in value.operands)
                        - type(value).FRACTIONAL_BITS
                    )
                    expression = f"({width}'($signed({operands[0]})) * {width}'($signed({operands[1]}))) >>> {shift}"
            elif value.op == "int16_add_sub":
                expression = f"{operands[0]} - {operands[1]}"
            else:
                compare = "<" if value.op == "fx_min_2" else ">"
                expression = f"$signed({operands[0]}) {compare} $signed({operands[1]}) ? {operands[0]} : {operands[1]}"
            inline_pipeline(value, expression)
        else:
            raise ValueError(f"No RTL implementation for {value.op}.")

    outputs = []
    for index, value in enumerate(graph.returns):
        name = f"out_{value.name}"
        if name in [item[0] for item in outputs]:
            name += f"_{index}"
        outputs.append((name, aligned(value, total), value))
    logic.extend(f"assign {name} = {signal};" for name, signal, _ in outputs)
    ports = ["input logic clk", "input logic clken", "input logic rst_n"]
    ports.extend(
        "input " + declaration(value, f"in_{value.name}") for value in graph.inputs
    )
    ports.extend("output " + declaration(value, name) for name, _, value in outputs)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        "// Auto-generated by scripts/frontend/generator.py; do not edit.\n"
        f"localparam int {latency_name} = {total};\n\n"
        f"module {module_name} (\n  "
        + ",\n  ".join(ports)
        + "\n);\n"
        + "\n".join(declarations + logic)
        + "\nendmodule\n",
        encoding="utf-8",
    )
    return output_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--rtl", action="store_true", help="generate the II=1 RTL pipeline"
    )
    parser.add_argument(
        "--resource-table",
        action="store_true",
        help="also schedule II=1..10 and write the resource CSV",
    )
    args = parser.parse_args()

    graph = trace(raster_frontend, return_graph=True)
    nodes, edges, resource_types = graph.to_dag()
    if args.rtl:
        path = export_pipeline_rtl(
            graph,
            Path(__file__).parents[2]
            / "rtl"
            / "generated"
            / "raster_frontend_autogen.svh",
        )
        print(f"RTL written to {path}")
    if args.resource_table:
        resource_table_path = export_resource_table(
            nodes,
            edges,
            latencies=None,
            resource_types=resource_types,
            output_path=Path(__file__).with_name("frontend_resource_ii.csv"),
            ii_values=range(1, 11),
        )
        print(f"Resource table written to {resource_table_path}")

    if args.rtl:
        operations, starts, ends, latencies, total = pipeline_schedule(graph)
        counts = {}
        assignments = {}
        for value in operations:
            assignments[value.name] = f"u_{value.name}"
            counts[value.op] = counts.get(value.op, 0) + 1
        nodes = [value.name for value in operations]
        res = {
            "schedule": {value.name: starts[value] for value in operations},
            "operation_latencies": {
                value.name: latencies[value.op] for value in operations
            },
            "end_cycles": {value.name: ends[value] for value in operations},
            "unit_assignment": assignments,
            "units_needed": counts,
            "total_latency": total,
        }
    else:
        res = schedule_hardware_dag(
            nodes, edges, latencies=None, resource_types=resource_types, II=1
        )

    print(f"Total Latency: {res['total_latency']} cycles")
    print(f"Allocated Units: {res['units_needed']}")
    rows = [("Operation", "Type", "Allocated Unit", "Latency", "Start", "End")]
    for node in sorted(nodes, key=lambda name: (res["schedule"][name], name)):
        rows.append(
            (
                node,
                resource_types[node],
                res["unit_assignment"][node],
                str(res["operation_latencies"][node]),
                str(res["schedule"][node]),
                str(res["end_cycles"][node]),
            )
        )
    widths = [max(len(row[index]) for row in rows) for index in range(6)]
    print("\nOperation Schedule:")
    for row_index, row in enumerate(rows):
        print("  ".join(value.ljust(width) for value, width in zip(row, widths)))
        if row_index == 0:
            print("  ".join("-" * width for width in widths))


if __name__ == "__main__":
    main()
