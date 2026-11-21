#include "lviv_mip.h"

#include <math.h>
#include <string.h>

#include "gpu.h"

// stb_image_resize2's memory, one allocation a resize: 0.5 MiB for a 2048 x 2048 texture's level
static unsigned char scratch[1u << 20] __attribute__((aligned(64)));
#define STBIR_MALLOC(size, user_data) ((void)(user_data), (size) <= sizeof scratch ? (void *)scratch : NULL)
#define STBIR_FREE(ptr, user_data) ((void)(ptr), (void)(user_data))
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "deprecated/stb_image_resize2.h"

#define PI 3.14159265358979323846
#define LOBES 3.0

// sinc(x) sinc(x / LOBES), x in the level's texels. In double: the same taps on every platform
static float lanczos(float x, float scale, void *user_data)
{
    const double px = PI * fabs((double)x);
    (void)scale;
    (void)user_data;
    if (px < 1e-9)
        return 1.0f;
    return px < PI * LOBES ? (float)(LOBES * sin(px) * sin(px / LOBES) / (px * px)) : 0.0f;
}

static float lanczos_support(float scale, void *user_data)
{
    (void)scale;
    (void)user_data;
    return (float)LOBES;
}

typedef struct
{
    const uint32_t *in;
    uint32_t *out;
} levels_t;

// stb's rows, out of Morton order and back into it. A texel's x is the even bits of its index
#define NEXT_X(index) (((index) - 0x55555555u) & 0x55555555u)

static const void *read_row(void *row, const void *input, int count, int x, int y, void *context)
{
    const uint32_t *in = ((const levels_t *)context)->in + gpu_texel_index(0, (uint32_t)y);
    uint32_t at = gpu_texel_index((uint32_t)x, 0);
    (void)input;
    for (int i = 0; i < count; i++, at = NEXT_X(at))
        memcpy((unsigned char *)row + 4 * i, &in[at], 4);
    return row;
}

static void write_row(const void *row, int count, int y, void *context)
{
    uint32_t *out = ((const levels_t *)context)->out + gpu_texel_index(0, (uint32_t)y);
    uint32_t at = 0;
    for (int i = 0; i < count; i++, at = NEXT_X(at))
        memcpy(&out[at], (const unsigned char *)row + 4 * i, 4);
}

int lviv_mip_halve(uint32_t *out, const uint32_t *in, uint32_t log2_size, int repeat_s, int repeat_t)
{
    // 8 x 8 to 2048 x 2048: stb does not repeat a texture narrower than the filter's 6 texels a side
    if (log2_size < 3 || log2_size > 11)
        return -1;
    const int size = 1 << log2_size;
    levels_t levels = {in, out};
    STBIR_RESIZE resize;
    // Its four channels each on its own: none weighted by alpha
    stbir_resize_init(&resize, in, size, size, 0, out, size / 2, size / 2, 0, STBIR_4CHANNEL, STBIR_TYPE_UINT8);
    stbir_set_edgemodes(&resize, repeat_s ? STBIR_EDGE_WRAP : STBIR_EDGE_CLAMP,
                        repeat_t ? STBIR_EDGE_WRAP : STBIR_EDGE_CLAMP);
    stbir_set_filter_callbacks(&resize, lanczos, lanczos_support, lanczos, lanczos_support);
    stbir_set_pixel_callbacks(&resize, read_row, write_row);
    stbir_set_user_data(&resize, &levels);
    return stbir_resize_extended(&resize) ? 0 : -1;
}
