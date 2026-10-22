// AUTO-GENERATED FROM scripts/create_triangle_layout.py
// The 96-byte gpu_triangle_t of sdk/include/gpu_triangle.h to frontend_data_in_t.
// Little-endian: byte b of the record is bits [8b+7:8b]. The padding is ignored.

`timescale 1ns / 1ps

import gpu_types_pkg::*;

module triangle_unpack (
    input  logic [767:0] packed_triangle,
    output frontend_data_in_t triangle
);
  always_comb begin
    triangle = '0;
    triangle.v0.position.x = packed_triangle[31:0];  // v[0].x
    triangle.v0.position.y = packed_triangle[63:32];  // v[0].y
    triangle.v0.position.z = packed_triangle[95:64];  // v[0].z
    triangle.v0.position.w = packed_triangle[127:96];  // v[0].w
    triangle.v0.color = packed_triangle[159:128];  // v[0].color
    triangle.v0.u = packed_triangle[191:160];  // v[0].u
    triangle.v0.v = packed_triangle[223:192];  // v[0].v
    triangle.v1.position.x = packed_triangle[255:224];  // v[1].x
    triangle.v1.position.y = packed_triangle[287:256];  // v[1].y
    triangle.v1.position.z = packed_triangle[319:288];  // v[1].z
    triangle.v1.position.w = packed_triangle[351:320];  // v[1].w
    triangle.v1.color = packed_triangle[383:352];  // v[1].color
    triangle.v1.u = packed_triangle[415:384];  // v[1].u
    triangle.v1.v = packed_triangle[447:416];  // v[1].v
    triangle.v2.position.x = packed_triangle[479:448];  // v[2].x
    triangle.v2.position.y = packed_triangle[511:480];  // v[2].y
    triangle.v2.position.z = packed_triangle[543:512];  // v[2].z
    triangle.v2.position.w = packed_triangle[575:544];  // v[2].w
    triangle.v2.color = packed_triangle[607:576];  // v[2].color
    triangle.v2.u = packed_triangle[639:608];  // v[2].u
    triangle.v2.v = packed_triangle[671:640];  // v[2].v
    triangle.tex_id = packed_triangle[679:672];  // tex_id
    triangle.texture_mode_u = texture_address_mode_t'(packed_triangle[680]);  // texture_mode
    triangle.texture_mode_v = texture_address_mode_t'(packed_triangle[681]);  // texture_mode
    triangle.texture_function = fragment_op_t'(packed_triangle[690:688]);  // texture_function
    triangle.sfactor_op = blend_op_t'(packed_triangle[699:696]);  // blend
    triangle.dfactor_op = blend_op_t'(packed_triangle[703:700]);  // blend
    triangle.depth_func = depth_func_t'(packed_triangle[706:704]);  // depth_func
  end
endmodule
