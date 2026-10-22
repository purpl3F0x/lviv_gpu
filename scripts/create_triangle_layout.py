"""Generate both sides of the 96-byte triangle record the triangle DMA streams into gpu_top.

One table below defines the layout. From it this script writes
  sdk/include/gpu_triangle.h          the C struct the CPU fills, with offset and size asserts
  rtl/generated/triangle_unpack.sv    the 768-bit record (little-endian: byte b is bits [8b+7:8b])
                                      to frontend_data_in_t
so the two cannot drift apart. Run it after changing the table.
"""

from pathlib import Path

TRIANGLE_BYTES = 96

# Per vertex, in order: (C name, C type, frontend_data_in_t field inside vertex_t). 4 bytes each.
VERTEX_FIELDS = [
    ("x", "float", "position.x"),  # screen position, pixels
    ("y", "float", "position.y"),
    ("z", "float", "position.z"),  # depth, 0..1
    ("w", "float", "position.w"),  # 1/w
    ("color", "uint32_t", "color"),  # ARGB
    ("u", "float", "u"),  # texcoord / w
    ("v", "float", "v"),
]
VERTEX_BYTES = 4 * len(VERTEX_FIELDS)

# Render state after the vertices, one byte each: (C name, comment,
# [(frontend_data_in_t field, SV cast or None, bit offset in the byte, width)]).
STATE_FIELDS = [
    ("tex_id", "texture table index; 0x80 = no texture", [("tex_id", None, 0, 8)]),
    ("texture_mode", "bit 0 u, bit 1 v: 0 clamp, 1 tile",
     [("texture_mode_u", "texture_address_mode_t", 0, 1),
      ("texture_mode_v", "texture_address_mode_t", 1, 1)]),
    ("texture_function", "fragment_op_t", [("texture_function", "fragment_op_t", 0, 3)]),
    ("blend", "sfactor [3:0], dfactor [7:4]: blend_op_t",
     [("sfactor_op", "blend_op_t", 0, 4), ("dfactor_op", "blend_op_t", 4, 4)]),
    ("depth_func", "depth_func_t", [("depth_func", "depth_func_t", 0, 3)]),
]

STATE_OFFSET = 3 * VERTEX_BYTES
PAD_BYTES = TRIANGLE_BYTES - STATE_OFFSET - len(STATE_FIELDS)
assert PAD_BYTES >= 0, "the fields do not fit in TRIANGLE_BYTES"

ROOT = Path(__file__).resolve().parent.parent
HEADER = ROOT / "sdk" / "include" / "gpu_triangle.h"
SV = ROOT / "rtl" / "generated" / "triangle_unpack.sv"
BANNER = "AUTO-GENERATED FROM scripts/create_triangle_layout.py"


def bits(byte_offset, lsb, width):
    low = 8 * byte_offset + lsb
    return f"[{low + width - 1}:{low}]" if width > 1 else f"[{low}]"


def header():
    lines = [
        f"// {BANNER}",
        f"// One {TRIANGLE_BYTES}-byte record per triangle, packed back to back in memory. Little-endian.",
        "#pragma once",
        "",
        "#include <stddef.h>",
        "#include <stdint.h>",
        "",
        "#ifdef __cplusplus",
        "#define GPU_STATIC_ASSERT(cond, msg) static_assert(cond, msg)",
        "#else",
        "#define GPU_STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)",
        "#endif",
        "",
        "typedef struct {",
    ]
    for name, ctype, _ in VERTEX_FIELDS:
        lines.append(f"    {ctype} {name};")
    lines += ["} gpu_vertex_t;", "", "typedef struct {", "    gpu_vertex_t v[3];"]
    for name, comment, _ in STATE_FIELDS:
        lines.append(f"    uint8_t {name};  // {comment}")
    if PAD_BYTES:
        lines.append(f"    uint8_t pad[{PAD_BYTES}];")
    lines += ["} gpu_triangle_t;", ""]

    lines.append(f"#define GPU_TRIANGLE_BYTES {TRIANGLE_BYTES}")
    lines.append("#define GPU_TEX_ID_NONE 0x80")
    for name, _, subfields in STATE_FIELDS:
        if len(subfields) > 1:
            for sv_name, _, lsb, width in subfields:
                lines.append(f"#define GPU_{sv_name.upper()}_SHIFT {lsb}")
                lines.append(f"#define GPU_{sv_name.upper()}_MASK 0x{(1 << width) - 1:x}u")
    lines.append("")

    lines.append(f'GPU_STATIC_ASSERT(sizeof(gpu_vertex_t) == {VERTEX_BYTES}, "gpu_vertex_t layout");')
    for i, (name, _, _) in enumerate(VERTEX_FIELDS):
        lines.append(f'GPU_STATIC_ASSERT(offsetof(gpu_vertex_t, {name}) == {4 * i}, "gpu_vertex_t.{name}");')
    for i, (name, _, _) in enumerate(STATE_FIELDS):
        lines.append(f'GPU_STATIC_ASSERT(offsetof(gpu_triangle_t, {name}) == {STATE_OFFSET + i}, '
                     f'"gpu_triangle_t.{name}");')
    lines.append(f'GPU_STATIC_ASSERT(sizeof(gpu_triangle_t) == GPU_TRIANGLE_BYTES, "gpu_triangle_t size");')
    return "\n".join(lines) + "\n"


def unpack_sv():
    lines = [
        f"// {BANNER}",
        f"// The {TRIANGLE_BYTES}-byte gpu_triangle_t of sdk/include/gpu_triangle.h to frontend_data_in_t.",
        "// Little-endian: byte b of the record is bits [8b+7:8b]. The padding is ignored.",
        "",
        "`timescale 1ns / 1ps",
        "",
        "import gpu_types_pkg::*;",
        "",
        "module triangle_unpack (",
        f"    input  logic [{8 * TRIANGLE_BYTES - 1}:0] packed_triangle,",
        "    output frontend_data_in_t triangle",
        ");",
        "  always_comb begin",
        "    triangle = '0;",
    ]
    for vertex in range(3):
        for i, (name, _, sv_field) in enumerate(VERTEX_FIELDS):
            offset = vertex * VERTEX_BYTES + 4 * i
            lines.append(f"    triangle.v{vertex}.{sv_field} = packed_triangle{bits(offset, 0, 32)};"
                         f"  // v[{vertex}].{name}")
    for i, (name, _, subfields) in enumerate(STATE_FIELDS):
        for sv_name, cast, lsb, width in subfields:
            value = f"packed_triangle{bits(STATE_OFFSET + i, lsb, width)}"
            if cast:
                value = f"{cast}'({value})"
            lines.append(f"    triangle.{sv_name} = {value};  // {name}")
    lines += ["  end", "endmodule", ""]
    return "\n".join(lines)


if __name__ == "__main__":
    HEADER.write_text(header(), encoding="utf-8")
    SV.write_text(unpack_sv(), encoding="utf-8")
    print(f"Generated: {HEADER}")
    print(f"Generated: {SV}")
