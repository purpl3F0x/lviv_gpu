// The GPU's raster core in software (sw_raster.h), for a CPU's speed, after Intel's Software
// Occlusion Culling rasterizer (github.com/rygorous/intel_occlusion_cull): the triangles binned to
// tiles, then in each tile set up a SIMD vector of them at a time (sw_simd.h), each drawn a vector
// of pixels at a time, a block of 2 rows, its color and z one vector each in the tile's buffers

#include "sw_raster.h"
#include "sw_simd.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// The GPU's (sdk/include/gpu_map.h, which needs the BSP)
#define GPU_TILE 128
#define GPU_TILES 64
#define TEXTURES 128
#define TEXTURE_MAX_LOG2 11

#define TILE SW_RASTER_TILE
_Static_assert(TILE >= 8 && GPU_TILE % TILE == 0, "SW_RASTER_TILE must divide the GPU's tile");
#define TILES (GPU_TILES * (GPU_TILE / TILE) * (GPU_TILE / TILE)) // in a frame, at most

// Positions in fixed point, 4 fractional bits, so that the edge functions fit 32 bits: in a
// triangle's box at most twice the frame's area (2^21 pixels at most) times 16 * 16
#define SUBPIXEL_BITS 4
#define SUBPIXEL (1 << SUBPIXEL_BITS)
// How far past the frame a vertex may be for the SIMD code (pixels); a triangle with one farther
// the scalar code draws (lviv_geom clips to the frustum, so none should be)
#ifndef SW_RASTER_GUARD
#define SW_RASTER_GUARD 64
#endif

// The tile's buffers: blocks of BLOCK_W x 2 pixels, a vector each, block after block along a pair
// of rows; without SIMD, rows as they are
#if SW_LANES
#define BLOCK_W (SW_LANES / 2)
#else
#define BLOCK_W TILE
#endif

#define INLINE SW_INLINE

// gpu_types_pkg.sv
enum
{
    REPLACE,
    MODULATE,
    DECAL,
    BLEND,
    ADD,
    COLOR
};
enum
{
    ZERO,
    ONE,
    SRC_COLOR,
    ONE_MINUS_SRC_COLOR,
    DST_COLOR,
    ONE_MINUS_DST_COLOR,
    SRC_ALPHA,
    ONE_MINUS_SRC_ALPHA,
    DST_ALPHA,
    ONE_MINUS_DST_ALPHA
};
enum
{
    DEPTH_LESS = 1,
    DEPTH_LEQUAL = 3
};

static struct
{
    const uint32_t *texels; // NULL: none
    uint32_t log2_size;
} textures[TEXTURES];

static _Alignas(64) uint32_t tile_color[TILE * TILE];
static _Alignas(64) float tile_z[TILE * TILE];

// Each tile's triangles, from bin_start[tile] to bin_start[tile + 1] in binned (an entry for each
// tile a triangle's box takes); the visibility bit of its GPU tile
static uint32_t *binned;     // on the heap: room_for
static uint32_t binned_room; // its entries
static uint32_t bin_start[TILES + 1], bin_fill[TILES];
static uint64_t bin_bit[TILES];

// Pixels, first to last
typedef struct
{
    int x0, y0, x1, y1;
} box_t;

int sw_raster_set_texture(uint32_t id, const uint32_t *texels, uint32_t log2_size)
{
    if (id >= TEXTURES || log2_size > TEXTURE_MAX_LOG2)
        return -1;
    textures[id].texels = texels;
    textures[id].log2_size = log2_size;
    return 0;
}

const char *sw_raster_simd(void)
{
    return SW_SIMD;
}

// The pixel's place in the tile's buffers: the row's, then (x + (x & -BLOCK_W)) past it
INLINE int row_index(int y)
{
    return (y >> 1) * (2 * TILE) + (y & 1) * BLOCK_W;
}

INLINE int tile_index(int x, int y)
{
    return row_index(y) + x + (x & -BLOCK_W);
}

INLINE uint32_t channel(uint32_t c, int shift)
{
    return c >> shift & 255u;
}

// x / 255, rounded (GL's colors, 255 as 1), for x up to 2 * 255 * 255
INLINE uint32_t div255(uint32_t x)
{
    x += 128;
    return (x + (x >> 8)) >> 8;
}

// A channel's value (0 to 255 but for rounding errors) to its byte
INLINE uint32_t to_byte(float f)
{
    f += 0.5f;
    return (uint32_t)(f > 0.0f ? (f < 255.0f ? f : 255.0f) : 0.0f);
}

// The texel coordinate's bits at the even bits (gpu_texel_index)
INLINE uint32_t spread(uint32_t v)
{
    v &= 0x7ffu;
    v = (v | v << 8) & 0x00ff00ffu;
    v = (v | v << 4) & 0x0f0f0f0fu;
    v = (v | v << 2) & 0x33333333u;
    return (v | v << 1) & 0x55555555u;
}

// A texture coordinate's texel: the nearest below (GL_NEAREST), tiled or clamped
INLINE uint32_t texel_coordinate(float c, float size, int32_t last, int tile)
{
    float f = c * size;
    f = f > -1e9f ? (f < 1e9f ? f : 1e9f) : -1e9f;
    int32_t i = (int32_t)f;
    i -= (float)i > f; // toward -infinity
    return (uint32_t)(tile ? i & last : i < 0 ? 0 : i > last ? last : i);
}

// GL_MODULATE
INLINE uint32_t modulate(uint32_t p, uint32_t t)
{
    uint32_t out = 0;
    for (int k = 0; k < 32; k += 8)
        out |= div255(channel(p, k) * channel(t, k)) << k;
    return out;
}

// The color p with the texel t, by the texture function op (not COLOR, which is p); GL_BLEND with
// the core's env color, 0
static uint32_t texture_function(unsigned op, uint32_t p, uint32_t t)
{
    const uint32_t ta = t >> 24;
    uint32_t out = 0;
    switch (op)
    {
    case REPLACE:
        return t;
    case MODULATE:
        return modulate(p, t);
    case DECAL:
        for (int k = 0; k < 24; k += 8)
            out |= div255(channel(p, k) * (255 - ta) + channel(t, k) * ta) << k;
        return out | (p & 0xff000000u);
    case BLEND:
        for (int k = 0; k < 24; k += 8)
            out |= div255(channel(p, k) * (255 - channel(t, k))) << k;
        break;
    case ADD:
        for (int k = 0; k < 24; k += 8)
        {
            const uint32_t sum = channel(p, k) + channel(t, k);
            out |= (sum > 255 ? 255 : sum) << k;
        }
        break;
    default:
        return 0;
    }
    return out | div255((p >> 24) * ta) << 24; // BLEND, ADD
}

// A blend factor's four channels, or otherwise for a code it does not have
static uint32_t factor(unsigned op, uint32_t s, uint32_t d, uint32_t otherwise)
{
    switch (op)
    {
    case ZERO:
        return 0;
    case ONE:
        return 0xffffffffu;
    case SRC_COLOR:
        return s;
    case ONE_MINUS_SRC_COLOR:
        return ~s;
    case DST_COLOR:
        return d;
    case ONE_MINUS_DST_COLOR:
        return ~d;
    case SRC_ALPHA:
        return (s >> 24) * 0x01010101u;
    case ONE_MINUS_SRC_ALPHA:
        return (~s >> 24) * 0x01010101u;
    case DST_ALPHA:
        return (d >> 24) * 0x01010101u;
    case ONE_MINUS_DST_ALPHA:
        return (~d >> 24) * 0x01010101u;
    }
    return otherwise;
}

static uint32_t blend(unsigned sfactor, unsigned dfactor, uint32_t s, uint32_t d)
{
    const uint32_t sf = factor(sfactor, s, d, 0xffffffffu), df = factor(dfactor, s, d, 0);
    uint32_t out = 0;
    for (int k = 0; k < 32; k += 8)
    {
        const uint32_t sum = div255(channel(s, k) * channel(sf, k) + channel(d, k) * channel(df, k));
        out |= (sum > 255 ? 255 : sum) << k;
    }
    return out;
}

// depth_func: a mask of {greater, equal, less}, of z against the stored z
INLINE int depth_pass(unsigned func, float z, float stored)
{
    return (int)(func & ((unsigned)(z < stored) | (unsigned)(z == stored) << 1 | (unsigned)(z > stored) << 2));
}

// Opaque, with the depth test less or less-equal: the pixel loops' fast case (also GL_MODULATE
// when textured)
INLINE int fast_state(const gpu_triangle_t *t)
{
    return t->blend == (ONE << GPU_SFACTOR_OP_SHIFT | ZERO << GPU_DFACTOR_OP_SHIFT) &&
           (t->depth_func == DEPTH_LESS || t->depth_func == DEPTH_LEQUAL);
}

// Its texture's texels and size; NULL if it draws none
INLINE const uint32_t *texture_of(const gpu_triangle_t *t, uint32_t *log2_size)
{
    if (t->tex_id >= TEXTURES || t->texture_function == COLOR || !textures[t->tex_id].texels)
        return NULL;
    *log2_size = textures[t->tex_id].log2_size;
    return textures[t->tex_id].texels;
}

// ---------------------------------------------------------------------------------------------
// The scalar code: a triangle at a time, in 64-bit fixed point, row by row, each row's covered span

static int64_t min3(int64_t a, int64_t b, int64_t c)
{
    return a < b ? (a < c ? a : c) : (b < c ? b : c);
}

static int64_t max3(int64_t a, int64_t b, int64_t c)
{
    return a > b ? (a > c ? a : c) : (b > c ? b : c);
}

// A position in fixed point, rounded
INLINE int64_t fixed(float f)
{
    const float s = f * SUBPIXEL;
    return (int64_t)(s < 0.0f ? s - 0.5f : s + 0.5f);
}

// floor(a / SUBPIXEL)
INLINE int64_t to_pixel(int64_t a)
{
    return a >= 0 ? a / SUBPIXEL : -((-a + SUBPIXEL - 1) / SUBPIXEL);
}

// The edge function, of c against a to b (in fixed point)
INLINE int64_t edge(int64_t ax, int64_t ay, int64_t bx, int64_t by, int64_t cx, int64_t cy)
{
    return (cx - ax) * (by - ay) - (cy - ay) * (bx - ax);
}

// [*lo, *hi], pixels along a row from its first, narrowed to where an edge is >= 0: e at the
// first, d a pixel right (inv_d 1 / |d|). The bound estimated in double, then made exact.
INLINE void edge_span(int64_t e, int64_t d, double inv_d, int *lo, int *hi)
{
    if (d > 0)
    {
        if (e >= 0)
            return;
        int64_t n = (int64_t)((double)-e * inv_d); // the first n with e + d * n >= 0
        while (e + d * n < 0)
            n++;
        while (n > 0 && e + d * (n - 1) >= 0)
            n--;
        if (n > *lo)
            *lo = n > *hi ? *hi + 1 : (int)n;
    }
    else if (d < 0)
    {
        if (e < 0)
        {
            *hi = *lo - 1;
            return;
        }
        int64_t n = (int64_t)((double)e * inv_d); // the last n with e + d * n >= 0
        while (e + d * (n + 1) >= 0)
            n++;
        while (n >= 0 && e + d * n < 0)
            n--;
        if (n < *hi)
            *hi = (int)n;
    }
    else if (e < 0)
        *hi = *lo - 1;
}

// A triangle in a tile, for the pixel loops: its box in the tile (pixels from the tile's first); at
// the box's first pixel's center its edges and attributes, and their steps a pixel right and down
typedef struct
{
    int x0, y0, x1, y1;
    int64_t e[3], edx[3], edy[3];
    double inv_edx[3]; // 1 / |edx|, or 0
    // z, 1/w, then each times 1/w: the color's B, G, R and A (0 to 255), u, v
    float a[8], adx[8], ady[8];
} setup_t;

INLINE void draw_rows(const gpu_triangle_t *t, const setup_t *s, const uint32_t *texels, uint32_t log2_size,
                      const int textured, const int fast)
{
    const int64_t edx0 = s->edx[0], edx1 = s->edx[1], edx2 = s->edx[2];
    const int64_t edy0 = s->edy[0], edy1 = s->edy[1], edy2 = s->edy[2];
    const double inv0 = s->inv_edx[0], inv1 = s->inv_edx[1], inv2 = s->inv_edx[2];
    const float dz = s->adx[0], dq = s->adx[1], db = s->adx[2], dg = s->adx[3], dr = s->adx[4], da = s->adx[5];
    const float du = s->adx[6], dv = s->adx[7];
    const float yz = s->ady[0], yq = s->ady[1], yb = s->ady[2], yg = s->ady[3], yr = s->ady[4], ya = s->ady[5];
    const float yu = s->ady[6], yv = s->ady[7];
    int64_t e0 = s->e[0], e1 = s->e[1], e2 = s->e[2];
    float z = s->a[0], q = s->a[1], b = s->a[2], g = s->a[3], r = s->a[4], a = s->a[5], u = s->a[6], v = s->a[7];

    const int less_equal = t->depth_func == DEPTH_LEQUAL;
    const unsigned depth_func = t->depth_func, op = t->texture_function;
    const unsigned sfactor = t->blend >> GPU_SFACTOR_OP_SHIFT & GPU_SFACTOR_OP_MASK;
    const unsigned dfactor = t->blend >> GPU_DFACTOR_OP_SHIFT & GPU_DFACTOR_OP_MASK;
    const int tile_u = t->texture_mode >> GPU_TEXTURE_MODE_U_SHIFT & GPU_TEXTURE_MODE_U_MASK;
    const int tile_v = t->texture_mode >> GPU_TEXTURE_MODE_V_SHIFT & GPU_TEXTURE_MODE_V_MASK;
    const float size = (float)(1u << log2_size);
    const int32_t last = (int32_t)(1u << log2_size) - 1;

    for (int y = s->y0; y <= s->y1; y++, e0 += edy0, e1 += edy1, e2 += edy2, z += yz, q += yq, b += yb, g += yg,
             r += yr, a += ya, u += yu, v += yv)
    {
        int lo = 0, hi = s->x1 - s->x0;
        edge_span(e0, edx0, inv0, &lo, &hi);
        edge_span(e1, edx1, inv1, &lo, &hi);
        edge_span(e2, edx2, inv2, &lo, &hi);
        if (lo > hi)
            continue;

        const float n = (float)lo;
        float pz = z + dz * n, pq = q + dq * n, pb = b + db * n, pg = g + dg * n, pr = r + dr * n, pa = a + da * n;
        float pu = u + du * n, pv = v + dv * n;
        const int base = row_index(y);
        for (int x = s->x0 + lo; x <= s->x0 + hi;
             x++, pz += dz, pq += dq, pb += db, pg += dg, pr += dr, pa += da, pu += du, pv += dv)
        {
            const int i = base + x + (x & -BLOCK_W);
            if (fast ? !(pz < tile_z[i] || (less_equal && pz == tile_z[i])) : !depth_pass(depth_func, pz, tile_z[i]))
                continue;
            tile_z[i] = pz;
            const float w = 1.0f / pq;
            uint32_t c = to_byte(pb * w) | to_byte(pg * w) << 8 | to_byte(pr * w) << 16 | to_byte(pa * w) << 24;
            if (textured)
            {
                const uint32_t tx = texel_coordinate(pu * w, size, last, tile_u);
                const uint32_t ty = texel_coordinate(pv * w, size, last, tile_v);
                const uint32_t texel = texels[spread(tx) | spread(ty) << 1];
                c = fast ? modulate(c, texel) : texture_function(op, c, texel);
            }
            tile_color[i] = fast ? c : blend(sfactor, dfactor, c, tile_color[i]);
        }
    }
}

static void draw_triangle_scalar(const gpu_triangle_t *t, const box_t *box)
{
    const gpu_vertex_t *v = t->v;
    // In the tile's fixed point: the frame's, less the tile's corner
    int64_t x[3], y[3];
    for (int k = 0; k < 3; k++)
    {
        x[k] = fixed(v[k].x) - (int64_t)box->x0 * SUBPIXEL;
        y[k] = fixed(v[k].y) - (int64_t)box->y0 * SUBPIXEL;
    }
    // Counter-clockwise on the screen only, as the core draws them
    const int64_t area = edge(x[0], y[0], x[1], y[1], x[2], y[2]);
    if (area <= 0)
        return;

    // The pixels whose centers its box takes, in the tile
    const int w = box->x1 - box->x0 + 1, h = box->y1 - box->y0 + 1;
    const int64_t fx0 = to_pixel(min3(x[0], x[1], x[2]) + SUBPIXEL / 2 - 1),
                  fx1 = to_pixel(max3(x[0], x[1], x[2]) - SUBPIXEL / 2);
    const int64_t fy0 = to_pixel(min3(y[0], y[1], y[2]) + SUBPIXEL / 2 - 1),
                  fy1 = to_pixel(max3(y[0], y[1], y[2]) - SUBPIXEL / 2);
    const int x0 = fx0 < 0 ? 0 : fx0 > w ? w : (int)fx0, x1 = fx1 < -1 ? -1 : fx1 > w - 1 ? w - 1 : (int)fx1;
    const int y0 = fy0 < 0 ? 0 : fy0 > h ? h : (int)fy0, y1 = fy1 < -1 ? -1 : fy1 > h - 1 ? h - 1 : (int)fy1;
    if (x0 > x1 || y0 > y1)
        return;

    uint32_t log2_size = 0;
    const uint32_t *texels = texture_of(t, &log2_size);

    setup_t s;
    s.x0 = x0;
    s.y0 = y0;
    s.x1 = x1;
    s.y1 = y1;
    const int64_t cx = (int64_t)x0 * SUBPIXEL + SUBPIXEL / 2, cy = (int64_t)y0 * SUBPIXEL + SUBPIXEL / 2;
    const int64_t ex[3] = {y[2] - y[1], y[0] - y[2], y[1] - y[0]}, ey[3] = {x[1] - x[2], x[2] - x[0], x[0] - x[1]};
    s.e[0] = edge(x[1], y[1], x[2], y[2], cx, cy);
    s.e[1] = edge(x[2], y[2], x[0], y[0], cx, cy);
    s.e[2] = edge(x[0], y[0], x[1], y[1], cx, cy);

    // The vertices' weights at the first pixel's center, and their steps; the attributes' planes
    const double inv_area = 1.0 / (double)area;
    double weight[3], wdx[3], wdy[3];
    float values[3][8];
    for (int k = 0; k < 3; k++)
    {
        s.edx[k] = ex[k] * SUBPIXEL;
        s.edy[k] = ey[k] * SUBPIXEL;
        s.inv_edx[k] = s.edx[k] ? 1.0 / (double)(s.edx[k] > 0 ? s.edx[k] : -s.edx[k]) : 0.0;
        weight[k] = (double)s.e[k] * inv_area;
        wdx[k] = (double)s.edx[k] * inv_area;
        wdy[k] = (double)s.edy[k] * inv_area;
        // The top-left rule, for coverage only: a pixel on an edge is in only if the edge is a left
        // one (the inside to its right) or a top one (level, the inside below)
        s.e[k] -= !(ex[k] > 0 || (ex[k] == 0 && ey[k] > 0));
        const float q = v[k].w; // 1/w
        values[k][0] = v[k].z;
        values[k][1] = q;
        for (int c = 0; c < 4; c++)
            values[k][2 + c] = (float)channel(v[k].color, 8 * c) * q;
        values[k][6] = v[k].u * q;
        values[k][7] = v[k].v * q;
    }
    for (int i = 0; i < 8; i++)
    {
        s.a[i] = (float)(weight[0] * values[0][i] + weight[1] * values[1][i] + weight[2] * values[2][i]);
        s.adx[i] = (float)(wdx[0] * values[0][i] + wdx[1] * values[1][i] + wdx[2] * values[2][i]);
        s.ady[i] = (float)(wdy[0] * values[0][i] + wdy[1] * values[1][i] + wdy[2] * values[2][i]);
    }

    const int fast = fast_state(t);
    if (!texels)
    {
        if (fast)
            draw_rows(t, &s, NULL, 0, 0, 1);
        else
            draw_rows(t, &s, NULL, 0, 0, 0);
    }
    else if (fast && t->texture_function == MODULATE)
        draw_rows(t, &s, texels, log2_size, 1, 1);
    else
        draw_rows(t, &s, texels, log2_size, 1, 0);
}

// ---------------------------------------------------------------------------------------------
// The SIMD code: SW_LANES triangles set up at once (a lane each), each then drawn a block of
// SW_LANES pixels at a time over its box, the blocks' edge functions in 32 bits

#if SW_LANES

// A batch of triangles in a tile, set up: a lane's triangle is in if ok; its box in the tile, from
// a block's first pixel; at that pixel's center its edges and attributes (sw_raster.c's setup_t's),
// and their steps a pixel right and down
typedef struct
{
    _Alignas(SW_ALIGN) int32_t ok[SW_LANES];
    _Alignas(SW_ALIGN) int32_t x0[SW_LANES], y0[SW_LANES], x1[SW_LANES], y1[SW_LANES];
    _Alignas(SW_ALIGN) int32_t e[3][SW_LANES], edx[3][SW_LANES], edy[3][SW_LANES];
    _Alignas(SW_ALIGN) float a[8][SW_LANES], adx[8][SW_LANES], ady[8][SW_LANES];
} batch_t;

// The first n of t (the other lanes out), in the tile at box
static void setup_batch(const gpu_triangle_t *const *t, int n, const box_t *box, batch_t *b)
{
    _Alignas(SW_ALIGN) float f[3][6][SW_LANES]; // per vertex x, y, z, 1/w, u, v
    _Alignas(SW_ALIGN) int32_t c[3][SW_LANES];
    for (int j = 0; j < SW_LANES; j++)
        for (int k = 0; k < 3; k++)
        {
            const gpu_vertex_t *v = &t[j < n ? j : 0]->v[k];
            f[k][0][j] = v->x;
            f[k][1][j] = v->y;
            f[k][2][j] = v->z;
            f[k][3][j] = v->w;
            f[k][4][j] = v->u;
            f[k][5][j] = v->v;
            c[k][j] = (int32_t)v->color;
        }

    // In the tile's fixed point: the frame's, less the tile's corner
    const vf scale = vf_set1((float)SUBPIXEL);
    const vi zero = vi_set1(0), one = vi_set1(1);
    vi X[3], Y[3];
    for (int k = 0; k < 3; k++)
    {
        X[k] = vi_sub(vf_round(vf_mul(vf_load(f[k][0]), scale)), vi_set1(box->x0 * SUBPIXEL));
        Y[k] = vi_sub(vf_round(vf_mul(vf_load(f[k][1]), scale)), vi_set1(box->y0 * SUBPIXEL));
    }

    // The edges, e(x, y) = A x + B y + C: 0 from vertex 1 to 2, 1 from 2 to 0, 2 from 0 to 1
    const vi A[3] = {vi_sub(Y[2], Y[1]), vi_sub(Y[0], Y[2]), vi_sub(Y[1], Y[0])};
    const vi B[3] = {vi_sub(X[1], X[2]), vi_sub(X[2], X[0]), vi_sub(X[0], X[1])};
    const vi C[3] = {vi_sub(vi_mul(Y[1], X[2]), vi_mul(X[1], Y[2])), vi_sub(vi_mul(Y[2], X[0]), vi_mul(X[2], Y[0])),
                     vi_sub(vi_mul(Y[0], X[1]), vi_mul(X[0], Y[1]))};
    const vi area = vi_add(vi_add(C[0], C[1]), C[2]); // wrapping, but itself within 32 bits

    // The pixels whose centers its box takes, in the tile; in if counter-clockwise (as the core
    // draws them) and some are
    vi x0 = vi_sra(vi_add(vi_min(vi_min(X[0], X[1]), X[2]), vi_set1(SUBPIXEL / 2 - 1)), SUBPIXEL_BITS);
    vi y0 = vi_sra(vi_add(vi_min(vi_min(Y[0], Y[1]), Y[2]), vi_set1(SUBPIXEL / 2 - 1)), SUBPIXEL_BITS);
    vi x1 = vi_sra(vi_sub(vi_max(vi_max(X[0], X[1]), X[2]), vi_set1(SUBPIXEL / 2)), SUBPIXEL_BITS);
    vi y1 = vi_sra(vi_sub(vi_max(vi_max(Y[0], Y[1]), Y[2]), vi_set1(SUBPIXEL / 2)), SUBPIXEL_BITS);
    x0 = vi_max(x0, zero);
    y0 = vi_max(y0, zero);
    x1 = vi_min(x1, vi_set1(box->x1 - box->x0));
    y1 = vi_min(y1, vi_set1(box->y1 - box->y0));
    vi_store(b->ok, vi_and(vi_gt(area, zero), vi_and(vi_gt(vi_add(x1, one), x0), vi_gt(vi_add(y1, one), y0))));
    for (int j = n; j < SW_LANES; j++)
        b->ok[j] = 0;
    x0 = vi_and(x0, vi_set1(-BLOCK_W));
    y0 = vi_and(y0, vi_set1(-2));
    vi_store(b->x0, x0);
    vi_store(b->y0, y0);
    vi_store(b->x1, x1);
    vi_store(b->y1, y1);

    // The edges at the first block's first pixel's center, and their steps; for coverage by the
    // top-left rule (draw_triangle_scalar's), 1 less where not a top or left edge
    const vi px = vi_add(vi_sll(x0, SUBPIXEL_BITS), vi_set1(SUBPIXEL / 2));
    const vi py = vi_add(vi_sll(y0, SUBPIXEL_BITS), vi_set1(SUBPIXEL / 2));
    vi E[3];
    for (int k = 0; k < 3; k++)
    {
        E[k] = vi_add(vi_add(vi_mul(A[k], px), vi_mul(B[k], py)), C[k]);
        const vi top_left = vi_or(vi_gt(A[k], zero), vi_and(vi_eq(A[k], zero), vi_gt(B[k], zero)));
        vi_store(b->e[k], vi_sub(E[k], vi_add(top_left, one)));
        vi_store(b->edx[k], vi_sll(A[k], SUBPIXEL_BITS));
        vi_store(b->edy[k], vi_sll(B[k], SUBPIXEL_BITS));
    }

    // The attributes' planes: from vertex 0's value, by the weights of vertices 1 and 2 (their
    // opposite edges over the area)
    const vf inv_area = vf_rcp(vi_float(area)), step = vf_mul(scale, inv_area);
    const vf w1 = vf_mul(vi_float(E[1]), inv_area), w2 = vf_mul(vi_float(E[2]), inv_area);
    const vf w1x = vf_mul(vi_float(A[1]), step), w2x = vf_mul(vi_float(A[2]), step);
    const vf w1y = vf_mul(vi_float(B[1]), step), w2y = vf_mul(vi_float(B[2]), step);
    const vi byte = vi_set1(255);
    vf value[8][3];
    for (int k = 0; k < 3; k++)
    {
        const vf q = vf_load(f[k][3]);
        const vi color = vi_load(c[k]);
        value[0][k] = vf_load(f[k][2]);
        value[1][k] = q;
        value[2][k] = vf_mul(vi_float(vi_and(color, byte)), q);
        value[3][k] = vf_mul(vi_float(vi_and(vi_srl(color, 8), byte)), q);
        value[4][k] = vf_mul(vi_float(vi_and(vi_srl(color, 16), byte)), q);
        value[5][k] = vf_mul(vi_float(vi_srl(color, 24)), q);
        value[6][k] = vf_mul(vf_load(f[k][4]), q);
        value[7][k] = vf_mul(vf_load(f[k][5]), q);
    }
    for (int i = 0; i < 8; i++)
    {
        const vf d1 = vf_sub(value[i][1], value[i][0]), d2 = vf_sub(value[i][2], value[i][0]);
        vf_store(b->a[i], vf_madd(w2, d2, vf_madd(w1, d1, value[i][0])));
        vf_store(b->adx[i], vf_madd(w2x, d2, vf_mul(w1x, d1)));
        vf_store(b->ady[i], vf_madd(w2y, d2, vf_mul(w1y, d1)));
    }
}

// The texel coordinate's bits at the even bits, each lane's (spread's)
INLINE vi vi_spread(vi v)
{
    v = vi_and(vi_or(v, vi_sll(v, 8)), vi_set1(0x00ff00ff));
    v = vi_and(vi_or(v, vi_sll(v, 4)), vi_set1(0x0f0f0f0f));
    v = vi_and(vi_or(v, vi_sll(v, 2)), vi_set1(0x33333333));
    return vi_and(vi_or(v, vi_sll(v, 1)), vi_set1(0x55555555));
}

// A texture coordinate's texels (texel_coordinate's)
INLINE vi vi_texel_coordinate(vf c, vf size, vi last, int tile)
{
    const vi i = vf_trunc(vf_floor(vf_max(vf_min(vf_mul(c, size), vf_set1(1e9f)), vf_set1(-1e9f))));
    return tile ? vi_and(i, last) : vi_min(vi_max(i, vi_set1(0)), last);
}

// The lanes pass takes, their texture function and blend done one by one
static void blend_lanes(vi pass, vi c, vi texel, int textured, const gpu_triangle_t *t, uint32_t *dst)
{
    _Alignas(SW_ALIGN) uint32_t color[SW_LANES], texels[SW_LANES], out[SW_LANES];
    vi_store(color, c);
    vi_store(texels, texel);
    vi_store(out, vi_load(dst));
    const unsigned sfactor = t->blend >> GPU_SFACTOR_OP_SHIFT & GPU_SFACTOR_OP_MASK;
    const unsigned dfactor = t->blend >> GPU_DFACTOR_OP_SHIFT & GPU_DFACTOR_OP_MASK;
    const unsigned bits = vi_bits(pass);
    for (int j = 0; j < SW_LANES; j++)
        if (bits >> j & 1)
        {
            const uint32_t s = textured ? texture_function(t->texture_function, color[j], texels[j]) : color[j];
            out[j] = blend(sfactor, dfactor, s, out[j]);
        }
    vi_store(dst, vi_load(out));
}

INLINE void draw_blocks(const gpu_triangle_t *t, const batch_t *b, int j, const uint32_t *texels, uint32_t log2_size,
                        const int textured, const int fast)
{
    const vi column = vi_column(), row = vi_row(), zero = vi_set1(0), none = vi_set1(-1);
    const vf fcolumn = vi_float(column), frow = vi_float(row);

    // Each lane's edges and attributes in the first block, and their steps a block right and down
#define EDGE(k)                                                                                                        \
    vi_add(vi_set1(b->e[k][j]), vi_add(vi_mul(vi_set1(b->edx[k][j]), column), vi_mul(vi_set1(b->edy[k][j]), row)))
#define ATTRIBUTE(i) vf_madd(vf_set1(b->ady[i][j]), frow, vf_madd(vf_set1(b->adx[i][j]), fcolumn, vf_set1(b->a[i][j])))
    vi e0_row = EDGE(0), e1_row = EDGE(1), e2_row = EDGE(2);
    vf z_row = ATTRIBUTE(0), q_row = ATTRIBUTE(1), b_row = ATTRIBUTE(2), g_row = ATTRIBUTE(3), r_row = ATTRIBUTE(4);
    vf a_row = ATTRIBUTE(5), u_row = ATTRIBUTE(6), v_row = ATTRIBUTE(7);
#undef EDGE
#undef ATTRIBUTE
    const vi e0x = vi_set1(b->edx[0][j] * BLOCK_W), e1x = vi_set1(b->edx[1][j] * BLOCK_W);
    const vi e2x = vi_set1(b->edx[2][j] * BLOCK_W);
    const vi e0y = vi_set1(b->edy[0][j] * 2), e1y = vi_set1(b->edy[1][j] * 2), e2y = vi_set1(b->edy[2][j] * 2);
    const vf zx = vf_set1(b->adx[0][j] * BLOCK_W), qx = vf_set1(b->adx[1][j] * BLOCK_W);
    const vf bx = vf_set1(b->adx[2][j] * BLOCK_W), gx = vf_set1(b->adx[3][j] * BLOCK_W);
    const vf rx = vf_set1(b->adx[4][j] * BLOCK_W), ax = vf_set1(b->adx[5][j] * BLOCK_W);
    const vf ux = vf_set1(b->adx[6][j] * BLOCK_W), vx = vf_set1(b->adx[7][j] * BLOCK_W);
    const vf zy = vf_set1(b->ady[0][j] * 2), qy = vf_set1(b->ady[1][j] * 2), by = vf_set1(b->ady[2][j] * 2);
    const vf gy = vf_set1(b->ady[3][j] * 2), ry = vf_set1(b->ady[4][j] * 2), ay = vf_set1(b->ady[5][j] * 2);
    const vf uy = vf_set1(b->ady[6][j] * 2), vy = vf_set1(b->ady[7][j] * 2);

    const int less_equal = t->depth_func == DEPTH_LEQUAL;
    const vi depth_lt = vi_set1(t->depth_func & 1 ? -1 : 0), depth_eq = vi_set1(t->depth_func & 2 ? -1 : 0);
    const vi depth_gt = vi_set1(t->depth_func & 4 ? -1 : 0);
    const int tile_u = t->texture_mode >> GPU_TEXTURE_MODE_U_SHIFT & GPU_TEXTURE_MODE_U_MASK;
    const int tile_v = t->texture_mode >> GPU_TEXTURE_MODE_V_SHIFT & GPU_TEXTURE_MODE_V_MASK;
    const vf size = vf_set1((float)(1u << log2_size));
    const vi last = vi_set1((int32_t)(1u << log2_size) - 1);

    // Edges that never rise to the right: one out over a whole block, the row is done
    const int fall0 = b->edx[0][j] <= 0, fall1 = b->edx[1][j] <= 0, fall2 = b->edx[2][j] <= 0;

    const int x0 = b->x0[j], x1 = b->x1[j];
    for (int y = b->y0[j]; y <= b->y1[j]; y += 2, e0_row = vi_add(e0_row, e0y), e1_row = vi_add(e1_row, e1y),
             e2_row = vi_add(e2_row, e2y), z_row = vf_add(z_row, zy), q_row = vf_add(q_row, qy),
             b_row = vf_add(b_row, by), g_row = vf_add(g_row, gy), r_row = vf_add(r_row, ry), a_row = vf_add(a_row, ay),
             u_row = vf_add(u_row, uy), v_row = vf_add(v_row, vy))
    {
        vi e0 = e0_row, e1 = e1_row, e2 = e2_row;
        for (int x = x0, k = 0, i = row_index(y) + 2 * x0; x <= x1;
             x += BLOCK_W, k++, i += 2 * BLOCK_W, e0 = vi_add(e0, e0x), e1 = vi_add(e1, e1x), e2 = vi_add(e2, e2x))
        {
            const vi inside = vi_gt(vi_or(vi_or(e0, e1), e2), none);
            if (!vi_any(inside))
            {
                if ((fall0 && !vi_any(vi_gt(e0, none))) || (fall1 && !vi_any(vi_gt(e1, none))) ||
                    (fall2 && !vi_any(vi_gt(e2, none))))
                    break;
                continue;
            }
            // The attributes k blocks along the row, as needed
            const vf along = vf_set1((float)k);
            const vf z = vf_madd(zx, along, z_row);
            const vf stored = vf_load(&tile_z[i]);
            vi pass;
            if (fast)
                pass = vi_and(inside, less_equal ? vf_le(z, stored) : vf_lt(z, stored));
            else
                pass =
                    vi_and(inside, vi_or(vi_or(vi_and(vf_lt(z, stored), depth_lt), vi_and(vf_eq(z, stored), depth_eq)),
                                         vi_and(vf_gt(z, stored), depth_gt)));
            if (!vi_any(pass))
                continue;
            vf_store(&tile_z[i], vf_select(pass, z, stored));

            const vf w = vf_rcp(vf_madd(qx, along, q_row));
            vi c = vi_argb(vf_mul(vf_madd(bx, along, b_row), w), vf_mul(vf_madd(gx, along, g_row), w),
                           vf_mul(vf_madd(rx, along, r_row), w), vf_mul(vf_madd(ax, along, a_row), w));
            vi texel = zero;
            if (textured)
            {
                const vi tx = vi_texel_coordinate(vf_mul(vf_madd(ux, along, u_row), w), size, last, tile_u);
                const vi ty = vi_texel_coordinate(vf_mul(vf_madd(vx, along, v_row), w), size, last, tile_v);
                texel = vi_gather(texels, vi_or(vi_spread(tx), vi_sll(vi_spread(ty), 1)));
                if (fast)
                    c = vi_modulate(c, texel);
            }
            if (fast)
                vi_store(&tile_color[i], vi_select(pass, c, vi_load(&tile_color[i])));
            else
                blend_lanes(pass, c, texel, textured, t, &tile_color[i]);
        }
    }
}

static void draw_lane(const gpu_triangle_t *t, const batch_t *b, int j)
{
    uint32_t log2_size = 0;
    const uint32_t *texels = texture_of(t, &log2_size);
    const int fast = fast_state(t);
    if (!texels)
    {
        if (fast)
            draw_blocks(t, b, j, NULL, 0, 0, 1);
        else
            draw_blocks(t, b, j, NULL, 0, 0, 0);
    }
    else if (fast && t->texture_function == MODULATE)
        draw_blocks(t, b, j, texels, log2_size, 1, 1);
    else
        draw_blocks(t, b, j, texels, log2_size, 1, 0);
}

// The tile's triangles waiting for their setup
static const gpu_triangle_t *pending[SW_LANES];
static int pending_count;

static void flush(const box_t *box)
{
    if (!pending_count)
        return;
    batch_t b;
    setup_batch(pending, pending_count, box, &b);
    for (int j = 0; j < pending_count; j++)
        if (b.ok[j])
            draw_lane(pending[j], &b, j);
    pending_count = 0;
}

// Its vertices within SW_RASTER_GUARD of the frame (width x height)
static int in_guard(const gpu_triangle_t *t, int width, int height)
{
    for (int k = 0; k < 3; k++)
        if (!(t->v[k].x >= -SW_RASTER_GUARD && t->v[k].x <= (float)(width + SW_RASTER_GUARD) &&
              t->v[k].y >= -SW_RASTER_GUARD && t->v[k].y <= (float)(height + SW_RASTER_GUARD)))
            return 0;
    return 1;
}

#endif

// The tile at box's next triangle, of a frame width x height; flush(box) after its last
static void add_triangle(const gpu_triangle_t *t, const box_t *box, int width, int height)
{
#if SW_LANES
    if (in_guard(t, width, height))
    {
        pending[pending_count++] = t;
        if (pending_count == SW_LANES)
            flush(box);
        return;
    }
    flush(box);
#else
    (void)width;
    (void)height;
#endif
    draw_triangle_scalar(t, box);
}

// ---------------------------------------------------------------------------------------------
// The frame

// The tiles a triangle's box takes in the frame (of width x height pixels); 0 if none
static int tile_box(const gpu_triangle_t *t, int width, int height, box_t *b)
{
    const gpu_vertex_t *v = t->v;
    float x0 = v[0].x, x1 = v[0].x, y0 = v[0].y, y1 = v[0].y;
    for (int k = 1; k < 3; k++)
    {
        x0 = v[k].x < x0 ? v[k].x : x0;
        x1 = v[k].x > x1 ? v[k].x : x1;
        y0 = v[k].y < y0 ? v[k].y : y0;
        y1 = v[k].y > y1 ? v[k].y : y1;
    }
    if (!(x1 >= 0.0f && y1 >= 0.0f && x0 < (float)width && y0 < (float)height))
        return 0;
    b->x0 = (x0 > 0.0f ? (int)x0 : 0) / TILE;
    b->y0 = (y0 > 0.0f ? (int)y0 : 0) / TILE;
    b->x1 = (x1 < (float)(width - 1) ? (int)x1 : width - 1) / TILE;
    b->y1 = (y1 < (float)(height - 1) ? (int)y1 : height - 1) / TILE;
    return 1;
}

// The tile's color at box to the frame
static void write_tile(const gpu_frame_t *frame, const box_t *box)
{
    const int n = box->x1 - box->x0 + 1;
    uint8_t *out = (uint8_t *)frame->frame + (size_t)box->y0 * frame->stride + (size_t)box->x0 * 4;
#if SW_LANES
    for (int y = 0; y <= box->y1 - box->y0; y += 2, out += 2 * frame->stride)
    {
        uint32_t *row0 = (uint32_t *)out, *row1 = y + 1 <= box->y1 - box->y0 ? (uint32_t *)(out + frame->stride) : NULL;
        int x = 0;
        if (row1)
            for (; x + BLOCK_W <= n; x += BLOCK_W)
                vi_store_rows(row0 + x, row1 + x, vi_load(&tile_color[row_index(y) + 2 * x]));
        for (; x < n; x++)
        {
            row0[x] = tile_color[tile_index(x, y)];
            if (row1)
                row1[x] = tile_color[tile_index(x, y + 1)];
        }
    }
#else
    for (int y = 0; y <= box->y1 - box->y0; y++, out += frame->stride)
        memcpy(out, &tile_color[y * TILE], (size_t)n * 4);
#endif
}

// Room in binned for n entries (a quarter more when it grows, for the frames after); 0 if the heap
// has none
static int room_for(uint32_t n)
{
    if (n <= binned_room)
        return 1;
    free(binned);
    binned_room = n + n / 4;
    binned = malloc((size_t)binned_room * sizeof *binned);
    if (!binned)
        binned_room = 0;
    return binned != NULL;
}

gpu_status_t sw_raster_frame(const gpu_frame_t *frame)
{
    const uint32_t gpu_across = (frame->width + GPU_TILE - 1) / GPU_TILE;
    const uint32_t gpu_down = (frame->height + GPU_TILE - 1) / GPU_TILE;
    if (gpu_across == 0 || gpu_down == 0 || gpu_across * gpu_down > GPU_TILES)
        return GPU_BAD_SIZE;
    const int width = (int)frame->width, height = (int)frame->height;
    const int across = (width + TILE - 1) / TILE, tiles = across * ((height + TILE - 1) / TILE);
    for (int i = 0; i < tiles; i++)
    {
        bin_bit[i] = (uint64_t)1 << (i / across * TILE / GPU_TILE * (int)gpu_across + i % across * TILE / GPU_TILE);
        bin_fill[i] = 0;
    }

    // Binned: the entries each tile gets counted, then filled in, the triangles in their order
    for (uint32_t t = 0; t < frame->triangle_count; t++)
    {
        box_t b;
        if (tile_box(&frame->triangles[t], width, height, &b))
            for (int ty = b.y0; ty <= b.y1; ty++)
                for (int tx = b.x0; tx <= b.x1; tx++)
                    bin_fill[ty * across + tx] += (frame->visibility[t] & bin_bit[ty * across + tx]) != 0;
    }
    uint32_t total = 0;
    for (int i = 0; i < tiles; i++)
    {
        bin_start[i] = total;
        total += bin_fill[i];
        bin_fill[i] = 0;
    }
    bin_start[tiles] = total;
    // With no room on the heap, its tiles each go through all its triangles
    const int all_binned = room_for(total);
    if (all_binned)
        for (uint32_t t = 0; t < frame->triangle_count; t++)
        {
            box_t b;
            if (tile_box(&frame->triangles[t], width, height, &b))
                for (int ty = b.y0; ty <= b.y1; ty++)
                    for (int tx = b.x0; tx <= b.x1; tx++)
                    {
                        const int i = ty * across + tx;
                        if (frame->visibility[t] & bin_bit[i])
                            binned[bin_start[i] + bin_fill[i]++] = t;
                    }
        }

    for (int i = 0; i < tiles; i++)
    {
        const int x = i % across * TILE, y = i / across * TILE;
        const box_t box = {x, y, (x + TILE < width ? x + TILE : width) - 1,
                           (y + TILE < height ? y + TILE : height) - 1};
        if (bin_start[i] == bin_start[i + 1])
        {
            uint8_t *row = (uint8_t *)frame->frame + (size_t)y * frame->stride + (size_t)x * 4;
            for (int k = y; k <= box.y1; k++, row += frame->stride)
                for (int n = 0; n <= box.x1 - x; n++)
                    ((uint32_t *)row)[n] = frame->clear_color;
            continue;
        }

        for (int k = 0; k < TILE * TILE; k++)
        {
            tile_color[k] = frame->clear_color;
            tile_z[k] = 1.0f;
        }
        if (all_binned)
            for (uint32_t k = bin_start[i]; k < bin_start[i + 1]; k++)
                add_triangle(&frame->triangles[binned[k]], &box, width, height);
        else
            for (uint32_t t = 0; t < frame->triangle_count; t++)
                if (frame->visibility[t] & bin_bit[i])
                    add_triangle(&frame->triangles[t], &box, width, height);
#if SW_LANES
        flush(&box);
#endif
        write_tile(frame, &box);
    }
    return GPU_OK;
}
