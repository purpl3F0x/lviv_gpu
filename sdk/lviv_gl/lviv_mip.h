// lviv_gl's mip levels: a level from the one above it by a Lanczos filter of three lobes, resized by
// stb_image_resize2 (sdk/third_party/stb) with its SIMD code: SSE2 or AVX2 on an x86-64 host, NEON
// on the A53.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

// out: the level below in, half its size. in: 1 << log2_size texels square, 8 to 2048. Both ARGB
// in Morton order (gpu_texel_index). repeat_s, repeat_t: the texture repeats along that axis, else
// its edge texels go on. Returns 0, or -1 for another size.
int lviv_mip_halve(uint32_t *out, const uint32_t *in, uint32_t log2_size, int repeat_s, int repeat_t);

#ifdef __cplusplus
}
#endif
