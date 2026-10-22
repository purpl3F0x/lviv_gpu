// AUTO-GENERATED FROM scripts/create_triangle_layout.py
// One 96-byte record per triangle, packed back to back in memory. Little-endian.
#pragma once

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
#define GPU_STATIC_ASSERT(cond, msg) static_assert(cond, msg)
#else
#define GPU_STATIC_ASSERT(cond, msg) _Static_assert(cond, msg)
#endif

typedef struct {
    float x;
    float y;
    float z;
    float w;
    uint32_t color;
    float u;
    float v;
} gpu_vertex_t;

typedef struct {
    gpu_vertex_t v[3];
    uint8_t tex_id;  // texture table index; 0x80 = no texture
    uint8_t texture_mode;  // bit 0 u, bit 1 v: 0 clamp, 1 tile
    uint8_t texture_function;  // fragment_op_t
    uint8_t blend;  // sfactor [3:0], dfactor [7:4]: blend_op_t
    uint8_t depth_func;  // depth_func_t
    uint8_t pad[7];
} gpu_triangle_t;

#define GPU_TRIANGLE_BYTES 96
#define GPU_TEX_ID_NONE 0x80
#define GPU_TEXTURE_MODE_U_SHIFT 0
#define GPU_TEXTURE_MODE_U_MASK 0x1u
#define GPU_TEXTURE_MODE_V_SHIFT 1
#define GPU_TEXTURE_MODE_V_MASK 0x1u
#define GPU_SFACTOR_OP_SHIFT 0
#define GPU_SFACTOR_OP_MASK 0xfu
#define GPU_DFACTOR_OP_SHIFT 4
#define GPU_DFACTOR_OP_MASK 0xfu

GPU_STATIC_ASSERT(sizeof(gpu_vertex_t) == 28, "gpu_vertex_t layout");
GPU_STATIC_ASSERT(offsetof(gpu_vertex_t, x) == 0, "gpu_vertex_t.x");
GPU_STATIC_ASSERT(offsetof(gpu_vertex_t, y) == 4, "gpu_vertex_t.y");
GPU_STATIC_ASSERT(offsetof(gpu_vertex_t, z) == 8, "gpu_vertex_t.z");
GPU_STATIC_ASSERT(offsetof(gpu_vertex_t, w) == 12, "gpu_vertex_t.w");
GPU_STATIC_ASSERT(offsetof(gpu_vertex_t, color) == 16, "gpu_vertex_t.color");
GPU_STATIC_ASSERT(offsetof(gpu_vertex_t, u) == 20, "gpu_vertex_t.u");
GPU_STATIC_ASSERT(offsetof(gpu_vertex_t, v) == 24, "gpu_vertex_t.v");
GPU_STATIC_ASSERT(offsetof(gpu_triangle_t, tex_id) == 84, "gpu_triangle_t.tex_id");
GPU_STATIC_ASSERT(offsetof(gpu_triangle_t, texture_mode) == 85, "gpu_triangle_t.texture_mode");
GPU_STATIC_ASSERT(offsetof(gpu_triangle_t, texture_function) == 86, "gpu_triangle_t.texture_function");
GPU_STATIC_ASSERT(offsetof(gpu_triangle_t, blend) == 87, "gpu_triangle_t.blend");
GPU_STATIC_ASSERT(offsetof(gpu_triangle_t, depth_func) == 88, "gpu_triangle_t.depth_func");
GPU_STATIC_ASSERT(sizeof(gpu_triangle_t) == GPU_TRIANGLE_BYTES, "gpu_triangle_t size");
