import argparse
import ast
import csv
import inspect
import json
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
    "fp_to_fx14_10": 6,
    "fx28_20_to_fp32": 7,
    "int_mul": 4,
    "int_mul_add": 5,
    "int_mul_sub": 5,
    "int_min_max_3": 2,
    "int_min": 1,
    "int_max": 1,
    "tri_bb_aligned_boundries": 2,
    "fx_min_2": 1,
    "fx_max_2": 1,
    "fp_to_fx14_17": 6,
    "fp_to_fx27_16": 6,
    "fp_to_fx5_13": 6,
    "fp32_to_uint12": 2,
    "int_add": 1,
    "int_sub": 1,
    "reg": 1,
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
        self.attributes = {}
        self.batch_constant = False

    def as_batch_constant(self):
        """Keep this input stable until all active pipeline iterations finish."""
        if self not in self.graph.inputs:
            raise ValueError("Only inputs can be marked as batch-constant.")
        self.batch_constant = True
        return self

    def add_attribute(self, attributes: dict[str, str | int | bool]):
        if not isinstance(attributes, dict):
            raise TypeError("add_attribute() expects a dictionary.")
        for name, value in attributes.items():
            if not isinstance(name, str) or not name.isidentifier():
                raise ValueError(f"Invalid SystemVerilog attribute name: {name!r}")
            if not isinstance(value, (str, int, bool)):
                raise TypeError("Attribute values must be strings, integers, or bools.")
        self.attributes.update(attributes)
        return self

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
        "fp_to_fx14_10": 6,
        "fx28_20_to_fp32": 7,
        "int_mul": 4,
        "int_min_max_3": 2,
        "tri_bb_aligned_boundries": 2,
        "fp_to_fx14_17": 6,
        "fp_to_fx27_16": 6,
        "fp32_to_uint12": 2,
        "tri_bb_min_max": 6,
        "fp_min_2": 1,
        "fp_max_2": 1,
        "fp_add_half_fast": 2,
    }


class Fx14_10(Value):
    KIND = "fx14_10"
    SIGNED = True
    INTEGER_BITS = 14
    FRACTIONAL_BITS = 10
    ADD_OP = "int_add"
    SUB_OP = "int_sub"
    OP_LATENCIES = {
        "fp_to_fx14_10": 6,
        "fx14_10_to_uint12": 0,
        "int_add": 1,
        "int_sub": 1,
        "int_min_max_3": 2,
        "fx_min_2": 1,
        "fx_max_2": 1,
        "uint12_to_fx14_10": 0,
        "uint14_to_fx14_10": 0,
        "uint14_to_fx14_10_pixel_center": 0,
        "fx14_10_to_uint12": 0,
        "fx_bbox_min_even": 0,
        "fx_bbox_max_odd": 0,
    }


class Fx28_20(Value):
    KIND = "fx28_20"
    SIGNED = True
    INTEGER_BITS = 28
    FRACTIONAL_BITS = 20
    ADD_OP = "int_add"
    SUB_OP = "int_sub"
    OP_LATENCIES = {
        "int_add": 1,
        "int_sub": 1,
        "int_mul": 4,
        "int_mul_add": 5,
        "int_mul_sub": 5,
        "fx28_20_to_fp32": 7,
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


class ScreenAddrX(UInt12):
    KIND = "screen_addr_x"


class ScreenAddrY(UInt12):
    KIND = "screen_addr_y"


class UInt14(Value):
    KIND = "uint14"
    SIGNED = False
    BITS = 14
    OP_LATENCIES = {
        "tri_bb_aligned_boundries": 2,
        "int_min_max_3": 2,
        "int_min": 1,
        "int_max": 1,
        "uint12_to_uint14": 0,
        "uint14_to_uint12": 0,
    }


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
    Fx14_10,
    Fx28_20,
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
    ScreenAddrX,
    ScreenAddrY,
    UInt14,
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


def fp_to_fx14_10(value: Float) -> Fx14_10:
    return _float_to_fixed(value, Fx14_10, "fp_to_fx14_10")


def fx28_20_to_fp32(value: Fx28_20) -> Float:
    if not isinstance(value, Fx28_20):
        raise TypeError("fx28_20_to_fp32() expects an Fx28_20 value.")
    return value.graph._record("fx28_20_to_fp32", Float, value)


def fx14_10_mul(a: Fx14_10, b: Fx14_10) -> Fx28_20:
    if not isinstance(a, Fx14_10) or not isinstance(b, Fx14_10):
        raise TypeError("fx14_10_mul() expects Fx14_10 arguments.")
    return _record_custom("int_mul", Fx28_20, a, b)


def fx14_10_mul_add(a: Fx14_10, b: Fx14_10, c: Fx28_20) -> Fx28_20:
    if not isinstance(a, Fx14_10) or not isinstance(b, Fx14_10):
        raise TypeError("fx14_10_mul_add() expects Fx14_10 multiplicands.")
    if not isinstance(c, Fx28_20):
        raise TypeError("fx14_10_mul_add() expects an Fx28_20 addend.")
    return _record_custom("int_mul_add", Fx28_20, a, b, c)


def fx14_10_mul_sub(a: Fx14_10, b: Fx14_10, c: Fx28_20) -> Fx28_20:
    if not isinstance(a, Fx14_10) or not isinstance(b, Fx14_10):
        raise TypeError("fx14_10_mul_sub() expects Fx14_10 multiplicands.")
    if not isinstance(c, Fx28_20):
        raise TypeError("fx14_10_mul_sub() expects an Fx28_20 subtrahend.")
    return _record_custom("int_mul_sub", Fx28_20, a, b, c)


def uint12_to_fx14_10(value: UInt12) -> Fx14_10:
    if not isinstance(value, UInt12):
        raise TypeError("uint12_to_fx14_10() expects a UInt12 value.")
    return _record_custom("uint12_to_fx14_10", Fx14_10, value)


def fx14_10_to_uint12(value: Fx14_10) -> UInt12:
    if not isinstance(value, Fx14_10):
        raise TypeError("fx14_10_to_uint12() expects an Fx14_10 value.")
    return _record_custom("fx14_10_to_uint12", UInt12, value)


def uint12_to_uint14(value: UInt12) -> UInt14:
    if not isinstance(value, UInt12):
        raise TypeError("uint12_to_uint14() expects a UInt12 value.")
    return _record_custom("uint12_to_uint14", UInt14, value)


def uint14_to_uint12(value: UInt14) -> UInt12:
    if not isinstance(value, UInt14):
        raise TypeError("uint14_to_uint12() expects a UInt14 value.")
    return _record_custom("uint14_to_uint12", UInt12, value)


def uint12_to_fx14_10(value: UInt12) -> Fx14_10:
    if not isinstance(value, UInt12):
        raise TypeError("uint12_to_fx14_10() expects a UInt12 value.")
    return _record_custom("uint12_to_fx14_10", Fx14_10, value)


def uint14_to_fx14_10(value: UInt14) -> Fx14_10:
    if not isinstance(value, UInt14):
        raise TypeError("uint14_to_fx14_10() expects a UInt14 value.")
    return _record_custom("uint14_to_fx14_10", Fx14_10, value)


def uint14_to_fx14_10_pixel_center(value: UInt14) -> Fx14_10:
    if not isinstance(value, UInt14):
        raise TypeError("uint14_to_fx14_10_pixel_center() expects a UInt14 value.")
    return _record_custom("uint14_to_fx14_10_pixel_center", Fx14_10, value)


def fx_bbox_min_even(value: Fx14_10) -> Fx14_10:
    if not isinstance(value, Fx14_10):
        raise TypeError("fx_bbox_min_even() expects an Fx14_10 value.")
    return _record_custom("fx_bbox_min_even", Fx14_10, value)


def fx_bbox_max_odd(value: Fx14_10) -> Fx14_10:
    if not isinstance(value, Fx14_10):
        raise TypeError("fx_bbox_max_odd() expects an Fx14_10 value.")
    return _record_custom("fx_bbox_max_odd", Fx14_10, value)


def min_max_3(a: Fx14_10, b: Fx14_10, c: Fx14_10) -> tuple[Fx14_10, Fx14_10]:
    if any(not isinstance(value, Fx14_10) for value in (a, b, c)):
        raise TypeError("min_max_3() expects Fx14_10 arguments.")
    operation = _record_custom("int_min_max_3", Fx14_10, a, b, c)
    return (
        operation.graph.output(operation, "min"),
        operation.graph.output(operation, "max"),
    )


def uint_min_max_3(a: UInt14, b: UInt14, c: UInt14) -> tuple[UInt14, UInt14]:
    if any(not isinstance(value, UInt14) for value in (a, b, c)):
        raise TypeError("uint_min_max_3() expects UInt14 arguments.")
    operation = _record_custom("int_min_max_3", UInt14, a, b, c)
    return (
        operation.graph.output(operation, "min"),
        operation.graph.output(operation, "max"),
    )


def int_min(a: UInt14, b: UInt14) -> UInt14:
    if not isinstance(a, UInt14) or not isinstance(b, UInt14):
        raise TypeError("int_min() expects UInt14 arguments.")
    return _record_custom("int_min", UInt14, a, b)


def int_max(a: UInt14, b: UInt14) -> UInt14:
    if not isinstance(a, UInt14) or not isinstance(b, UInt14):
        raise TypeError("int_max() expects UInt14 arguments.")
    return _record_custom("int_max", UInt14, a, b)


def tri_bb_aligned_boundries(
    x0: Fx14_10, x1: Fx14_10, x2: Fx14_10
) -> tuple[UInt14, UInt14]:
    if any(not isinstance(value, Fx14_10) for value in (x0, x1, x2)):
        raise TypeError("tri_bb_aligned_boundries() expects Fx14_10 arguments.")
    operation = _record_custom("tri_bb_aligned_boundries", UInt14, x0, x1, x2)
    return (
        operation.graph.output(operation, "min"),
        operation.graph.output(operation, "max"),
    )


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
        bit_slice=(f"{tile_addr_parameter}", 1),
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


def register(value: Value) -> Value:
    if not isinstance(value, Value):
        raise TypeError("register() expects a symbolic Value.")
    return _record_custom("reg", type(value), value)


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
    if type(a) not in (Fx14_10, Fx14_17, Fx27_16) or type(b) is not type(a):
        raise TypeError("fx_max_2() expects matching fixed-point arguments.")
    return _record_custom("fx_max_2", type(a), a, b)


def fx_min_2(a: Value, b: Value) -> Value:
    if type(a) not in (Fx14_10, Fx14_17, Fx27_16) or type(b) is not type(a):
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
            ScreenAddrX,
            ScreenAddrY,
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

        commutative = expression in ("add", "mul") or op.endswith(("_min_2", "_max_2"))
        operand_key = tuple(id(operand) for operand in operands)
        if commutative:
            operand_key = tuple(sorted(operand_key))
        cache_key = (op, expression, value_type, operand_key)
        if op != "reg" and cache_key in self._expressions:
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


def value_width(value):
    value_type = type(value)
    if value_type is Float:
        return 32
    if value_type in (Fx14_10, Fx28_20, Fx14_17, Fx27_16, Fx5_13):
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
    """Write a module, omitting alignment delays for batch-constant inputs."""
    operations, starts, ends, latencies, total = pipeline_schedule(graph)
    batch_constants = {value for value in graph.inputs if value.batch_constant}
    for value in operations:
        if latencies[value.op] == 0 and all(
            operand in batch_constants or operand.constant is not _NOT_CONSTANT
            for operand in value.operands
        ):
            batch_constants.add(value)
    declarations = []
    logic = []
    delays = {}
    consumers = {value: set() for value in operations}
    for consumer in operations:
        for operand in consumer.operands:
            producer = operand.producer or operand
            if producer in consumers:
                consumers[producer].add(consumer)
    returned = {value.producer or value for value in graph.returns}
    retimed_registers = {}
    for value in operations:
        if value.op != "reg" or value in returned or len(consumers[value]) != 1:
            continue
        consumer = next(iter(consumers[value]))
        input_delay = starts[consumer] - ends[value]
        if input_delay > 0:
            retimed_registers[value] = (consumer, input_delay)

    def declaration(value, name):
        types = {
            Float: "float_t",
            Fx14_10: "fx_14_10_t",
            Fx28_20: "fx_28_20_t",
            Fx14_17: "fx_14_17_t",
            Fx27_16: "fx_27_16_t",
            Fx5_13: "fx_5_13_t",
            Int16: "int16_t",
            UInt14: "uint14_t",
            TileAddrX: "tile_addr_x_t",
            TileAddrY: "tile_addr_y_t",
            UInt12: "uint12_t",
            ScreenAddrX: "screen_addr_x_t",
            ScreenAddrY: "screen_addr_y_t",
        }
        if type(value) is UInt1:
            return f"logic {name}"
        if type(value) in (UInt3, UInt4, UInt8, UInt32):
            return f"logic [{value_width(value)-1}:0] {name}"
        return f"{types[type(value)]} {name}"

    def attribute_prefix(value):
        if not value.attributes:
            return ""
        attributes = []
        for name, attribute_value in value.attributes.items():
            if isinstance(attribute_value, str):
                rendered_value = json.dumps(attribute_value)
            elif isinstance(attribute_value, bool):
                rendered_value = "1'b1" if attribute_value else "1'b0"
            else:
                rendered_value = str(attribute_value)
            attributes.append(f"{name} = {rendered_value}")
        return "(* " + ", ".join(attributes) + " *) "

    def variable_declaration(value, name):
        return attribute_prefix(value) + declaration(value, name)

    def port_declaration(value, direction, name):
        return attribute_prefix(value) + direction + " " + declaration(value, name)

    def rtl_width(value):
        if type(value) is TileAddrX:
            return "$bits(tile_addr_x_t)"
        if type(value) is TileAddrY:
            return "$bits(tile_addr_y_t)"
        if type(value) is ScreenAddrX:
            return "$bits(screen_addr_x_t)"
        if type(value) is ScreenAddrY:
            return "$bits(screen_addr_y_t)"
        return value_width(value)

    def base(value):
        if value.constant is not _NOT_CONSTANT:
            width = value_width(value)
            if type(value) is Float:
                bits = struct.unpack(">I", struct.pack(">f", value.constant))[0]
            elif type(value) in (Fx14_10, Fx28_20, Fx14_17, Fx27_16, Fx5_13):
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
        if (value.producer or value) in batch_constants:
            return signal
        retimed = retimed_registers.get(value)
        if retimed is not None and cycle == starts[retimed[0]]:
            return signal
        depth = cycle - ready_cycle
        if depth < 0:
            raise ValueError(f"{value.name} is not ready at cycle {cycle}.")
        if depth == 0 or value.constant is not _NOT_CONSTANT:
            return signal
        key = (signal, depth)
        if key not in delays:
            name = f"delay_{len(delays)}"
            delays[key] = name
            declarations.append(variable_declaration(value, name) + ";")
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
            declarations.append(variable_declaration(value, pipe) + ";")
            logic.append(f"assign {pipe} = {expression};")
            logic.append(
                f"delay_pipe #(.WIDTH({rtl_width(value)}), .STAGES({latency})) "
                f"u_pipe_{value.name} (.clk(clk), .rst_n(1'b1), .clken(clken), "
                f".data_in({pipe}), .data_out({name}));"
            )

    for value in operations:
        name = f"n_{value.name}"
        declarations.append(variable_declaration(value, name) + ";")
        operand_cycle = starts[value]
        retimed = retimed_registers.get(value)
        if retimed is not None:
            operand_cycle += retimed[1]
        operands = [aligned(operand, operand_cycle) for operand in value.operands]
        latency = latencies[value.op]
        ports = [".aclk(clk)", ".aclken(clken)", ".valid_in(1'b1)"]
        if value.op == "fp_recip":
            ports.append(f".a({operands[0]})")
            ports.append(f".result({name})")
            logic.append(
                f"{value.op} #(.LATENCY({latency})) u_{value.name} ({', '.join(ports)});"
            )
        elif value.op in (
            "fp_to_fx14_10",
            "fx28_20_to_fp32",
            "fp_to_fx5_13",
        ):
            logic.append(
                f"{value.op} #(.LATENCY({latency})) u_{value.name} "
                f"(.aclk(clk), .aclken(clken), .s_axis_a_tvalid(1'b1), "
                f".s_axis_a_tdata({operands[0]}), .m_axis_result_tvalid(), "
                f".m_axis_result_tdata({name}));"
            )
        elif value.op == "tri_bb_aligned_boundries":
            declarations.extend(
                [
                    variable_declaration(value, f"{name}_min") + ";",
                    variable_declaration(value, f"{name}_max") + ";",
                ]
            )
            logic.append(
                f"tri_bb_aligned_boundries #(.WIDTH(24), .FRACTIONAL(10)) u_{value.name} "
                f"(.clk(clk), .clken(clken), .a({operands[0]}), .b({operands[1]}), "
                f".c({operands[2]}), .min_val({name}_min), .max_val({name}_max));"
            )
        elif value.op in ("int_min", "int_max"):
            logic.append(
                f"{value.op} #(.WIDTH({value_width(value)})) u_{value.name} "
                f"(.clk(clk), .clken(clken), .a({operands[0]}), "
                f".b({operands[1]}), .res({name}));"
            )
        elif value.op == "int_mul":
            if type(value) is not Fx28_20 or any(
                type(operand) is not Fx14_10 for operand in value.operands
            ):
                raise TypeError(
                    "int_mul in this frontend requires two Fx14_10 operands."
                )
            logic.append(
                f"int_mul #(.WIDTHA(24), .WIDTHB(24), .WIDTHP(48), "
                f".INPUT_BUFFERS(1), .OUTPUT_BUFFERS(2), .LATENCY({latency})) "
                f"u_{value.name} (.clk(clk), .clken(clken), .a({operands[0]}), "
                f".b({operands[1]}), .p({name}));"
            )
        elif value.op in (
            "uint12_to_uint14",
            "uint14_to_uint12",
            "uint14_to_fx14_10_pixel_center",
        ):
            operand = operands[0]
            expressions = {
                "uint12_to_uint14": f"{{2'b0, {operand}}}",
                "uint14_to_uint12": f"{operand}[11:0]",
                "uint14_to_fx14_10_pixel_center": f"{{{operand}, 1'b1, 9'b0}}",
            }
            if value.op == "uint12_to_uint14" and type(value.operands[0]) in (
                ScreenAddrX,
                ScreenAddrY,
            ):
                expressions[value.op] = f"uint14_t'({operand})"
            inline_pipeline(value, expressions[value.op])
        elif value.op in ("int_add", "int_sub"):
            if latency != 1:
                raise ValueError(f"{value.op} RTL has a fixed latency of one cycle.")
            supported_integer_types = (
                UInt12,
                UInt14,
                Fx14_10,
                Fx28_20,
                TileAddrX,
                TileAddrY,
            )
            if type(value) not in supported_integer_types:
                raise TypeError(f"{value.op} has an unsupported integer result type.")
            operand_type = type(value)
            if any(type(operand) is not operand_type for operand in value.operands):
                raise TypeError(
                    f"{value.op} requires matching {operand_type.__name__} operands."
                )
            macro = "INT_ADD" if value.op == "int_add" else "INT_SUB"
            logic.append(f"`{macro}(clk, clken, {operands[0]}, {operands[1]}, {name})")
        elif value.op == "reg":
            if len(operands) != 1 or type(value) is not type(value.operands[0]):
                raise TypeError("reg requires one input and preserves its type.")
            logic.append(f"`REG(clk, clken, {operands[0]}, {name})")
        else:
            raise ValueError(f"No RTL implementation for {value.op}.")

    outputs = []
    for index, value in enumerate(graph.returns):
        name = f"out_{value.name}"
        if name in [item[0] for item in outputs]:
            name += f"_{index}"
        outputs.append((name, aligned(value, total), value))
    logic.extend(f"assign {name} = {signal};" for name, signal, _ in outputs)
    ports = ["input logic clk", "input logic clken"]
    ports.extend(
        port_declaration(value, "input", f"in_{value.name}") for value in graph.inputs
    )
    ports.extend(port_declaration(value, "output", name) for name, _, value in outputs)
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        "// Auto-generated by scripts/frontend/generator_fixed_point.py; do not edit.\n"
        f"localparam int {latency_name} = {total};\n\n"
        "`define INT_ADD(CLK, CE, A, B, S) \\\n"
        "always_ff @(posedge CLK) begin \\\n"
        "    if (CE) S <= (A) + (B); \\\n"
        "end\n"
        "`define INT_SUB(CLK, CE, A, B, S) \\\n"
        "always_ff @(posedge CLK) begin \\\n"
        "    if (CE) S <= (A) - (B); \\\n"
        "end\n"
        "`define REG(CLK, CE, D, Q) \\\n"
        "always_ff @(posedge CLK) begin \\\n"
        "    if (CE) Q <= D; \\\n"
        "end\n"
        "\n\n(* use_dsp = \"simd\" *)\n"
        + f"module {module_name} (\n  "
        + ",\n  ".join(ports)
        + "\n);\n"
        + "\n // Declarations\n"
        + "\n".join(map("  {0}".format, declarations))
        + "\n // Logic\n"
        + "\n".join(map("  {0}".format, logic))
        + "\nendmodule\n",
        encoding="utf-8",
    )
    return output_path


###################################################
###################################################
###################################################


def raster_frontend(
    v0_x: Float,
    v0_y: Float,
    v1_x: Float,
    v1_y: Float,
    v2_x: Float,
    v2_y: Float,
    bin_min_x: ScreenAddrX,
    bin_min_y: ScreenAddrY,
    bin_max_x: ScreenAddrX,
    bin_max_y: ScreenAddrY,
    v0_u: Float,
    v0_v: Float,
    v1_u: Float,
    v1_v: Float,
    v2_u: Float,
    v2_v: Float,
):
    bin_min_x.as_batch_constant()
    bin_min_y.as_batch_constant()
    bin_max_x.as_batch_constant()
    bin_max_y.as_batch_constant()

    v0_x_fx = fp_to_fx14_10(v0_x)
    v0_y_fx = fp_to_fx14_10(v0_y)
    v1_x_fx = fp_to_fx14_10(v1_x)
    v1_y_fx = fp_to_fx14_10(v1_y)
    v2_x_fx = fp_to_fx14_10(v2_x)
    v2_y_fx = fp_to_fx14_10(v2_y)

    dx_0 = register(v2_y_fx) - register(v1_y_fx)
    dx_1 = register(v0_y_fx) - register(v2_y_fx)
    dx_2 = register(v1_y_fx) - register(v0_y_fx)
    dy_0 = register(v1_x_fx) - register(v2_x_fx)
    dy_1 = register(v2_x_fx) - register(v0_x_fx)
    dy_2 = register(v0_x_fx) - register(v1_x_fx)

    area = register(fx14_10_mul(register(dy_1), dx_2)) - register(fx14_10_mul(register(dy_2), dx_1))
    invArea = 1.0 / fx28_20_to_fp32(area)

    tri_min_x, tri_max_x = tri_bb_aligned_boundries(v0_x_fx, v1_x_fx, v2_x_fx)
    tri_min_y, tri_max_y = tri_bb_aligned_boundries(v0_y_fx, v1_y_fx, v2_y_fx)

    bin_min_x_u14 = uint12_to_uint14(bin_min_x)
    bin_min_y_u14 = uint12_to_uint14(bin_min_y)
    bin_max_x_u14 = uint12_to_uint14(bin_max_x)
    bin_max_y_u14 = uint12_to_uint14(bin_max_y)
    bb_min_x_u14 = int_max(tri_min_x, bin_min_x_u14)
    bb_min_y_u14 = int_max(tri_min_y, bin_min_y_u14)
    bb_max_x_u14 = int_min(tri_max_x, bin_max_x_u14)
    bb_max_y_u14 = int_min(tri_max_y, bin_max_y_u14)

    p_min_x = uint14_to_fx14_10_pixel_center(bb_min_x_u14)
    p_min_y = uint14_to_fx14_10_pixel_center(bb_min_y_u14)

    w0 = register(
        fx14_10_mul(register(dy_0), register(register(p_min_y) - register(register(v1_y_fx))))
    ) + register(fx14_10_mul(register(dx_0), register(register(p_min_x) - register(register(v1_x_fx)))))

    w1 = register(
        fx14_10_mul(register(dy_1), register(register(p_min_y) - register(register(v2_y_fx))))
    ) + register(fx14_10_mul(register(dx_1), register(register(p_min_x) - register(register(v2_x_fx)))))

    w2 = register(
        fx14_10_mul(register(dy_2), register(register(p_min_y) - register(register(v0_y_fx))))
    ) + register(fx14_10_mul(register(dx_2), register(register(p_min_x) - register(register(v0_x_fx)))))

    bb_min_x_int = uint14_to_uint12(register(bb_min_x_u14))
    bb_min_y_int = uint14_to_uint12(register(bb_min_y_u14))
    bb_max_x_int = uint14_to_uint12(register(bb_max_x_u14))
    bb_max_y_int = uint14_to_uint12(register(bb_max_y_u14))

    minX_local = uint12_to_local_quad_x(bb_min_x_int)
    minY_local = uint12_to_local_quad_y(bb_min_y_int)
    maxX_local = uint12_to_local_quad_x(bb_max_x_int)
    maxY_local = uint12_to_local_quad_y(bb_max_y_int)

    bb_width = maxX_local - minX_local
    bb_height = maxY_local - minY_local

    bb_width.add_attribute({"use_dsp": "no"})
    bb_height.add_attribute({"use_dsp": "no"})

    dx0_fx = dx_0
    dx1_fx = dx_1
    dx2_fx = dx_2
    dy0_fx = dy_0
    dy1_fx = dy_1
    dy2_fx = dy_2

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
            / "raster_frontend_fixed_autogen.svh",
            module_name="raster_frontend_fixed_core",
            latency_name="RASTER_FRONTEND_FIXED_LATENCY",
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
