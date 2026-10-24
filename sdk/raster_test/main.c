// Tests of gpu_top's raster core on the ZCU104 (bd/gpu_test), on the A53 (standalone).
//
// One triangle, made here (no scene data): blue at the top, red at the bottom left, green at the
// bottom right, over a black clear colour. It is drawn twice:
//  1. Colour: untextured, so each pixel gets the corners' colours by its barycentric weights.
//  2. Texture: a 64 x 64 black and white checkerboard made here (8 x 8 squares of 8 texels),
//     repeated twice across the triangle and modulating its colours: the colours show in the
//     white squares, the black ones stay black. Every thread's texture cache reads it from PS DDR.
// Each is a frame of 1280 x 720 in 10 x 6 tiles of 128 x 128 (each with its z-buffers cleared, the
// triangle streamed into the core when its bounding box touches the tile, then written back),
// checked pixel by pixel against the triangle worked out here in floating point. A pixel whose
// centre is inside every edge by a pixel or more must be the expected colour, within
// COLOR_TOLERANCE in each channel; one outside an edge by a pixel or more the clear colour. Those in
// between are not checked, nor those on the border of a checkerboard square.
// Then the DisplayPort output shows the last frame, the link brought up and down as a monitor is
// plugged in and pulled, for as long as the board runs.
//
// Output goes to the PS UART.

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "board.h"
#include "dp.h"
#include "gpu.h"
#include "gpu_map.h"
#include "xil_printf.h"
#include "xiltimer.h" // XTime_GetTime, COUNTS_PER_SECOND
#include "xparameters.h"
#include "xscugic.h"

// gpu_0's control port, from the address map of the XSA the platform was made from.
#ifndef GPU_BASEADDR
#define GPU_BASEADDR XPAR_GPU_TOP_BD_0_BASEADDR
#endif

// The GPU's frame, shown on the DP output as it is: at most 64 tiles, a bit each in a triangle's
// visibility word.
#define WIDTH 1280
#define HEIGHT 720
#define TILES_X (WIDTH / GPU_TILE_SIZE)
#define TILES_Y ((HEIGHT + GPU_TILE_SIZE - 1) / GPU_TILE_SIZE)
#define TILES (TILES_X * TILES_Y)
#define FRAME_ROWS (TILES_Y * GPU_TILE_SIZE) // the tile DMA writes whole tiles
#define STRIDE (WIDTH * 4)
#define CLEAR_COLOR 0xFF000000u // opaque black
// The largest difference from the colour worked out here, per channel: the core interpolates in
// fixed point (8 fractional bits on the weights) and truncates.
#define COLOR_TOLERANCE 3

// The checkerboard: TEX_SIZE texels square, squares of TEX_CHECK texels.
#define TEX_ID 0
#define TEX_LOG2 6
#define TEX_SIZE (1 << TEX_LOG2)
#define TEX_CHECK 8
#define TEX_WHITE 0xFFFFFFFFu
#define TEX_BLACK 0xFF000000u
// Pixels this close to the border of a square (in squares: 1.2 pixels here) are not checked.
#define CHECK_MARGIN 0.02

_Static_assert(WIDTH == DP_WIDTH && HEIGHT == DP_HEIGHT, "the frame is shown as it is");
_Static_assert(TILES <= 64, "more tiles than bits in a visibility word");
_Static_assert((TEX_SIZE / TEX_CHECK) % 2 == 0, "expected() takes an even number of squares across");

typedef struct
{
    float x, y;     // screen pixels, y down
    uint32_t color; // ARGB
    float u, v;     // texture coordinates, 1 a texture's width
} corner_t;

// Counter-clockwise on the screen: the core draws a pixel only where none of the three edge
// functions is negative, which takes that winding (main checks it). The texture coordinates are
// the screen's, 480 pixels to the texture: squares of 60 pixels.
static const corner_t corners[3] = {
    {640.0f, 60.0f, 0xFF0000FFu, 1.0f, 0.0f},    // top: blue
    {160.0f, 660.0f, 0xFFFF0000u, 0.0f, 1.25f},  // bottom left: red
    {1120.0f, 660.0f, 0xFF00FF00u, 2.0f, 1.25f}, // bottom right: green
};

static gpu_triangle_t triangle __attribute__((aligned(64)));
static uint64_t visibility __attribute__((aligned(64)));
static uint32_t frame[FRAME_ROWS * WIDTH] __attribute__((aligned(4096)));
static uint32_t texture[TEX_SIZE * TEX_SIZE] __attribute__((aligned(4 * TEX_SIZE * TEX_SIZE)));

static gpu_t gpu;
static XScuGic gic; // static: the DP output's interrupt handlers hold on to it

// From build_triangle, for expected().
static double area;       // twice the triangle's, from edge()
static double length2[3]; // the square of the length of the edge opposite each corner

// raster_sw's edge function (rasterizer.h): c's distance from edge a -> b times the edge's length,
// positive on the inside of a triangle counter-clockwise on the screen.
static double edge(const corner_t *a, const corner_t *b, double cx, double cy)
{
    return (cx - a->x) * (b->y - a->y) - (cy - a->y) * (b->x - a->x);
}

// No libm: the application links without it.
static float min_f(float a, float b)
{
    return a < b ? a : b;
}
static float max_f(float a, float b)
{
    return a > b ? a : b;
}
static double floor_d(double a)
{
    const double i = (double)(long long)a;
    return i > a ? i - 1 : i;
}

// White squares where the square's x and y add up to an even number, black elsewhere.
static void fill_checkerboard(void)
{
    for (uint32_t y = 0; y < TEX_SIZE; y++)
        for (uint32_t x = 0; x < TEX_SIZE; x++)
            texture[gpu_texel_index(x, y)] = (x / TEX_CHECK + y / TEX_CHECK) % 2 ? TEX_BLACK : TEX_WHITE;
}

// The record, untextured or with the checkerboard repeated, and its visibility word from its
// bounding box (bit t set when the box overlaps tile t), as a binner would produce. Returns the
// tiles it touches.
static int build_triangle(int textured)
{
    float x0 = corners[0].x, x1 = x0, y0 = corners[0].y, y1 = y0;
    memset(&triangle, 0, sizeof triangle);
    for (int v = 0; v < 3; v++)
    {
        const corner_t *a = &corners[(v + 1) % 3], *b = &corners[(v + 2) % 3];
        triangle.v[v].x = corners[v].x;
        triangle.v[v].y = corners[v].y;
        triangle.v[v].z = 0.5f;
        triangle.v[v].w = 1.0f; // 1/w: no perspective
        triangle.v[v].color = corners[v].color;
        triangle.v[v].u = corners[v].u;
        triangle.v[v].v = corners[v].v;
        length2[v] = (double)(b->x - a->x) * (b->x - a->x) + (double)(b->y - a->y) * (b->y - a->y);
        x0 = min_f(x0, corners[v].x);
        x1 = max_f(x1, corners[v].x);
        y0 = min_f(y0, corners[v].y);
        y1 = max_f(y1, corners[v].y);
    }
    if (textured)
    {
        triangle.tex_id = TEX_ID;
        triangle.texture_mode = 1u << GPU_TEXTURE_MODE_U_SHIFT | 1u << GPU_TEXTURE_MODE_V_SHIFT; // tile
        triangle.texture_function = 1;                                                           // MODULATE
    }
    else
    {
        triangle.tex_id = GPU_TEX_ID_NONE;
        triangle.texture_function = 5; // COLOR
    }
    triangle.blend = (1u << GPU_SFACTOR_OP_SHIFT) | (0u << GPU_DFACTOR_OP_SHIFT); // ONE, ZERO
    triangle.depth_func = 1;                                                      // LESS
    area = edge(&corners[0], &corners[1], corners[2].x, corners[2].y);

    // Bounding box against the tiles, clipped to the screen.
    const int tx0 = (int)max_f(x0, 0) / GPU_TILE_SIZE, tx1 = (int)min_f(x1, WIDTH - 1) / GPU_TILE_SIZE;
    const int ty0 = (int)max_f(y0, 0) / GPU_TILE_SIZE, ty1 = (int)min_f(y1, HEIGHT - 1) / GPU_TILE_SIZE;
    int tiles = 0;
    visibility = 0;
    for (int ty = ty0; ty <= ty1; ty++)
    {
        for (int tx = tx0; tx <= tx1; tx++)
        {
            visibility |= 1ull << (ty * TILES_X + tx);
            tiles++;
        }
    }
    return tiles;
}

// What the core should draw at (x, y), sampled at the pixel's centre as the core does: 1 inside
// every edge by a pixel or more, *want the corners' colours by the barycentric weights (modulated
// by the checkerboard when textured); 0 outside one by a pixel or more, *want the clear colour;
// -1 in between, or on the border of a square.
static int expected(int x, int y, int textured, uint32_t *want)
{
    const double px = x + 0.5, py = y + 0.5;
    double weight[3];
    int near_edge = 0;
    for (int v = 0; v < 3; v++)
    {
        const double e = edge(&corners[(v + 1) % 3], &corners[(v + 2) % 3], px, py);
        const int far = e * e >= length2[v]; // a pixel or more from the edge
        if (e < 0 && far)
        {
            *want = CLEAR_COLOR;
            return 0;
        }
        near_edge |= !far;
        weight[v] = e / area;
    }
    if (near_edge)
        return -1;

    uint32_t texel = TEX_WHITE;
    if (textured)
    {
        // The square the texture coordinates fall in. Repeating the texture keeps a square's
        // colour: an even number of squares across.
        double u = 0, v = 0;
        for (int i = 0; i < 3; i++)
        {
            u += weight[i] * corners[i].u;
            v += weight[i] * corners[i].v;
        }
        const double sx = floor_d(u * (TEX_SIZE / TEX_CHECK)), sy = floor_d(v * (TEX_SIZE / TEX_CHECK));
        const double fx = u * (TEX_SIZE / TEX_CHECK) - sx, fy = v * (TEX_SIZE / TEX_CHECK) - sy;
        if (fx < CHECK_MARGIN || fx > 1 - CHECK_MARGIN || fy < CHECK_MARGIN || fy > 1 - CHECK_MARGIN)
            return -1;
        texel = ((long long)sx + (long long)sy) % 2 ? TEX_BLACK : TEX_WHITE;
    }

    // The weights are positive and add up to 1: each channel stays in 0..255.
    *want = 0;
    for (int shift = 0; shift < 32; shift += 8)
    {
        double c = 0;
        for (int v = 0; v < 3; v++)
            c += weight[v] * (double)(corners[v].color >> shift & 0xFF);
        uint32_t channel = (uint32_t)(c + 0.5);
        if (textured) // MODULATE, as raster_sw and the fragment shader round it
            channel = (channel * (texel >> shift & 0xFF) + 128) >> 8;
        *want |= channel << shift;
    }
    return 1;
}

// The largest difference between a and b in one channel.
static int color_error(uint32_t a, uint32_t b)
{
    int error = 0;
    for (int shift = 0; shift < 32; shift += 8)
    {
        const int d = abs((int)(a >> shift & 0xFF) - (int)(b >> shift & 0xFF));
        if (d > error)
            error = d;
    }
    return error;
}

// Every pixel against expected(); returns the wrong ones.
static int check_frame(const char *name, int textured)
{
    int pixels[2] = {0, 0}, wrong[2] = {0, 0}, unchecked = 0, worst = 0;
    for (int y = 0; y < FRAME_ROWS; y++)
    {
        for (int x = 0; x < WIDTH; x++)
        {
            uint32_t want, got = frame[y * WIDTH + x];
            const int inside = expected(x, y, textured, &want);
            if (inside < 0)
            {
                unchecked++;
                continue;
            }
            const int error = color_error(got, want);
            pixels[inside]++;
            if (inside && error > worst)
                worst = error;
            if (inside ? error > COLOR_TOLERANCE : got != want)
            {
                if (wrong[0] + wrong[1] < 8)
                    xil_printf("  pixel (%d, %d): 0x%08x, expected 0x%08x\r\n", x, y, (int)got, (int)want);
                wrong[inside]++;
            }
        }
    }
    xil_printf("%s: inside %d pixels, %d wrong (largest channel error %d, up to %d allowed)\r\n", name, pixels[1],
               wrong[1], worst, COLOR_TOLERANCE);
    xil_printf("%s: outside %d pixels, %d not the clear colour\r\n", name, pixels[0], wrong[0]);
    xil_printf("%s: %d pixels near an edge%s, not checked\r\n", name, unchecked,
               textured ? " or a square's border" : "");
    return wrong[0] + wrong[1];
}

// The triangle drawn into frame and checked; returns the errors.
static int run(const char *name, int textured)
{
    build_triangle(textured);
    gpu_frame_t f = {
        .triangles = &triangle,
        .visibility = &visibility,
        .triangle_count = 1,
        .frame = frame,
        .stride = STRIDE,
        .tiles_x = TILES_X,
        .tiles_y = TILES_Y,
        .clear_color = CLEAR_COLOR,
    };
    XTime start, end;
    uint32_t failed_tile = 0;
    memset(frame, 0, sizeof frame); // not the clear colour: a tile not written back shows
    XTime_GetTime(&start);
    gpu_status_t status = gpu_frame(&gpu, &f, &failed_tile);
    XTime_GetTime(&end);
    if (status != GPU_OK)
    {
        xil_printf("%s: FAIL at tile %d: %s\r\n", name, (int)failed_tile, gpu_status_name(status));
        return 1;
    }
    xil_printf("%s: frame %d us\r\n", name, (int)((end - start) / (COUNTS_PER_SECOND / 1000000)));
    return check_frame(name, textured);
}

int main(void)
{
    int errors = 0;

    xil_printf("\r\nRaster test: gpu_top's raster core at 0x%x\r\n", (int)GPU_BASEADDR);
    if (board_init(&gic) != 0)
    {
        xil_printf("interrupts: GIC setup failed\r\n");
        return 1;
    }
    gpu_init(&gpu, GPU_BASEADDR);

    const int tiles = build_triangle(0);
    xil_printf("triangle: (%d, %d) blue, (%d, %d) red, (%d, %d) green; in %d of %d tiles\r\n", (int)corners[0].x,
               (int)corners[0].y, (int)corners[1].x, (int)corners[1].y, (int)corners[2].x, (int)corners[2].y, tiles,
               TILES);
    if (area <= 0)
    {
        xil_printf("triangle: clockwise or flat, the core would draw nothing\r\n");
        return 1;
    }

    errors += run("colour", 0);

    fill_checkerboard();
    if (gpu_set_texture(&gpu, TEX_ID, texture, TEX_LOG2) == 0)
    {
        xil_printf("texture: %d x %d checkerboard at 0x%x\r\n", TEX_SIZE, TEX_SIZE, (int)(uintptr_t)texture);
        errors += run("texture", 1);
    }
    else
    {
        xil_printf("texture: FAIL: at 0x%x, outside the GPU's texture window\r\n", (int)(uintptr_t)texture);
        errors++;
    }
    xil_printf("%s\r\n", errors ? "FAIL" : "PASS");

    // The last frame, whether or not it passed.
    if (dp_init(&gic, frame, STRIDE) != 0)
    {
        xil_printf("DisplayPort: setup failed\r\n");
        return errors ? 1 : 0;
    }
    xil_printf("DisplayPort: showing the frame, %d x %d at 60 Hz; plug in or pull a monitor\r\n", DP_WIDTH, DP_HEIGHT);
    for (;;)
        dp_service();
}
