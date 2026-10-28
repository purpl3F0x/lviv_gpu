// The GPU's frames drawn by a CPU, as fast as it can, to compare the two: a frame (gpu.h's
// gpu_frame_t) drawn as the GPU draws it, with a CPU's arithmetic rather than the core's. After
// Intel's Software Occlusion Culling rasterizer (github.com/rygorous/intel_occlusion_cull): the
// triangles binned to tiles once a frame (by their boxes, among those of their GPU tiles: their
// visibility bits); in each tile, in their order, set up a SIMD vector of them at a time, each then
// drawn a block of pixels at a time over its box (sw_simd.h: AVX2's 4 x 2, NEON's 2 x 2), edge
// functions in 32-bit fixed point (4 fractional bits). The tiles are SW_RASTER_TILE square, cleared
// to the frame's clear color and z 1.0: at 64 their color and z, 16 KiB each, stay in a 32 KiB data
// cache. What the core draws: counter-clockwise triangles, the pixels whose centers they cover (by
// the top-left rule where on an edge, not both triangles'), z and 1/w linear, color and texture
// coordinates perspective-correct, the depth test, the nearest texel, the texture functions and
// the blend (GL's rounding: 255 as 1, not the core's 255/256). Plain C, no OS or BSP headers and no
// heap: it builds for the host and for the A53 alike.
#pragma once

#include "gpu.h"

#ifndef SW_RASTER_TILE
#define SW_RASTER_TILE 64 // pixels; divides the GPU's 128
#endif

#ifdef __cplusplus
extern "C"
{
#endif

// Texture id (a triangle's tex_id) as gpu_set_texture takes it: 1 << log2_size texels square, ARGB,
// in Morton order (gpu_texel_index). Kept by pointer, not copied. Returns 0, or -1 for an id or a
// size the GPU does not have (128 textures, up to 2048 x 2048).
int sw_raster_set_texture(uint32_t id, const uint32_t *texels, uint32_t log2_size);

// The frame drawn into frame->frame, frame->stride bytes a row: its width x height pixels (the GPU
// writes whole tiles, past them). GPU_BAD_SIZE as gpu_frame has it, else GPU_OK.
gpu_status_t sw_raster_frame(const gpu_frame_t *frame);

// The SIMD it was built with: "AVX2", "NEON", "vector" (GCC's vector extensions) or "scalar"
const char *sw_raster_simd(void);

#ifdef __cplusplus
}
#endif
