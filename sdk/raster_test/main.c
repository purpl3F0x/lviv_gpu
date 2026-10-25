// Demo of gpu_top's raster core on the ZCU104 (bd/gpu_test), on the A53 (standalone), driven from
// the UART console.
//
// The DisplayPort output runs in the background from the start, 1280 x 720 at 60 Hz (dp.c). It
// shows the test pattern first; then the triangle, drawn again for every frame, one a vertical sync
// (60 frames a second while a frame takes less than 16.7 ms): into the frame buffer not on the
// screen, shown from the next vertical sync on. Once a second, the frames drawn and their times.
// Keys:
//   1, 2     who draws it: 1 the CPU, tile by tile; 2 the command processor, in one START
//   c, t, b  the triangle's color: c its corners' colors (untextured), t the texture alone, b the
//            texture modulating the colors
//   r        drawing again, after the test pattern or a frame that failed
//   p        the test pattern: color ramps made here, a check of the display on its own
//   ?        the keys
// The triangle, made here: blue at the top, red at the bottom left, green at the bottom right, over
// a black clear color. The texture: a 64 x 64 black and white checkerboard made here (8 x 8 squares
// of 8 texels), repeated twice across the triangle, read from PS DDR by every thread's texture
// cache. A frame is 1280 x 720 in 10 x 6 tiles of 128 x 128 (each with its z-buffers cleared, the
// triangle streamed into the core when its bounding box touches the tile, then written back).
//
// Output goes to the PS UART.

#include <stdint.h>
#include <string.h>

#include "board.h"
#include "bspconfig.h" // STDIN_BASEADDRESS
#include "dp.h"
#include "gpu.h"
#include "gpu_map.h"
#include "xil_printf.h"
#include "xiltimer.h" // XTime_GetTime, COUNTS_PER_SECOND
#include "xparameters.h"
#include "xscugic.h"
#include "xuartps_hw.h"

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

// The checkerboard: TEX_SIZE texels square, squares of TEX_CHECK texels.
#define TEX_ID 0
#define TEX_LOG2 6
#define TEX_SIZE (1 << TEX_LOG2)
#define TEX_CHECK 8
#define TEX_WHITE 0xFFFFFFFFu
#define TEX_BLACK 0xFF000000u

// The fragment shader's texture functions (fragment_op_t, gpu_types_pkg.sv)
#define FRAGMENT_REPLACE 0
#define FRAGMENT_MODULATE 1
#define FRAGMENT_COLOR 5

_Static_assert(WIDTH == DP_WIDTH && HEIGHT == DP_HEIGHT, "the frame is shown as it is");
_Static_assert(TILES <= 64, "more tiles than bits in a visibility word");

typedef enum
{
    SHADE_COLOR,   // the corners' colors
    SHADE_TEXTURE, // the texture alone
    SHADE_BLEND,   // the texture modulating the colors
} shade_t;

static const char *const shade_names[] = {"color", "texture", "blend"};
static const char *const mode_names[] = {[GPU_MODE_CPU] = "CPU", [GPU_MODE_CP] = "CP"};

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
// Two frame buffers: one on the screen, the other drawn into, then shown.
static uint32_t frames[2][FRAME_ROWS * WIDTH] __attribute__((aligned(4096)));
static uint32_t texture[TEX_SIZE * TEX_SIZE] __attribute__((aligned(4 * TEX_SIZE * TEX_SIZE)));

static gpu_t gpu;
static XScuGic gic; // static: the DP output's interrupt handlers hold on to it

static int back;       // the frame buffer not on the screen
static int texture_ok; // the texture is in the GPU's texture table
static int drawing;    // a frame after another, not the test pattern
static gpu_mode_t mode = GPU_MODE_CPU;
static shade_t shade = SHADE_COLOR;

// Since the last report: the frames drawn, their time all together and the longest, from when.
static int frames_drawn;
static XTime frames_time, longest, period_start;

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

// White squares where the square's x and y add up to an even number, black elsewhere.
static void fill_checkerboard(void)
{
    for (uint32_t y = 0; y < TEX_SIZE; y++)
        for (uint32_t x = 0; x < TEX_SIZE; x++)
            texture[gpu_texel_index(x, y)] = (x / TEX_CHECK + y / TEX_CHECK) % 2 ? TEX_BLACK : TEX_WHITE;
}

static uint32_t rgb(uint32_t r, uint32_t g, uint32_t b)
{
    return 0xFF000000u | r << 16 | g << 8 | b;
}

// The hue wheel across the line, at full saturation: red, yellow, green, cyan, blue, magenta, red.
static uint32_t hue(int x)
{
    const uint32_t h = (uint32_t)x * 6 * 256 / DP_WIDTH, f = h % 256;
    switch (h / 256)
    {
    case 0:
        return rgb(255, f, 0);
    case 1:
        return rgb(255 - f, 255, 0);
    case 2:
        return rgb(0, 255, f);
    case 3:
        return rgb(0, 255 - f, 255);
    case 4:
        return rgb(f, 0, 255);
    default:
        return rgb(255, 0, 255 - f);
    }
}

// Eight bands of ramps from left to right: the hue wheel (two bands), grey, red, green, blue, and red
// into blue with green rising downwards (two bands): the color order and the levels.
static void fill_test_pattern(uint32_t *p)
{
    _Static_assert(DP_HEIGHT % 8 == 0, "the test pattern's bands want DP_HEIGHT a multiple of 8");
    const int band_rows = DP_HEIGHT / 8;
    for (int y = 0; y < DP_HEIGHT; y++)
    {
        const int band = y / band_rows;
        for (int x = 0; x < DP_WIDTH; x++)
        {
            const uint32_t v = (uint32_t)x * 255 / (DP_WIDTH - 1);
            uint32_t c;
            switch (band)
            {
            case 0:
            case 1:
                c = hue(x);
                break;
            case 2:
                c = rgb(v, v, v);
                break;
            case 3:
                c = rgb(v, 0, 0);
                break;
            case 4:
                c = rgb(0, v, 0);
                break;
            case 5:
                c = rgb(0, 0, v);
                break;
            default:
                c = rgb(v, (uint32_t)(y - 6 * band_rows) * 255 / (2 * band_rows - 1), 255 - v);
                break;
            }
            p[y * WIDTH + x] = c;
        }
    }
}

// The record, colored as how says, and its visibility word from its bounding box (bit t set when
// the box overlaps tile t), as a binner would produce. Returns the tiles it touches.
static int build_triangle(shade_t how)
{
    float x0 = corners[0].x, x1 = x0, y0 = corners[0].y, y1 = y0;
    memset(&triangle, 0, sizeof triangle);
    for (int v = 0; v < 3; v++)
    {
        triangle.v[v].x = corners[v].x;
        triangle.v[v].y = corners[v].y;
        triangle.v[v].z = 0.5f;
        triangle.v[v].w = 1.0f; // 1/w: no perspective
        triangle.v[v].color = corners[v].color;
        triangle.v[v].u = corners[v].u;
        triangle.v[v].v = corners[v].v;
        x0 = min_f(x0, corners[v].x);
        x1 = max_f(x1, corners[v].x);
        y0 = min_f(y0, corners[v].y);
        y1 = max_f(y1, corners[v].y);
    }
    if (how == SHADE_COLOR)
    {
        triangle.tex_id = GPU_TEX_ID_NONE;
        triangle.texture_function = FRAGMENT_COLOR;
    }
    else
    {
        triangle.tex_id = TEX_ID;
        triangle.texture_mode = 1u << GPU_TEXTURE_MODE_U_SHIFT | 1u << GPU_TEXTURE_MODE_V_SHIFT; // tile
        triangle.texture_function = how == SHADE_TEXTURE ? FRAGMENT_REPLACE : FRAGMENT_MODULATE;
    }
    triangle.blend = (1u << GPU_SFACTOR_OP_SHIFT) | (0u << GPU_DFACTOR_OP_SHIFT); // ONE, ZERO
    triangle.depth_func = 1;                                                      // LESS

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

// The frame buffer drawn into on the screen from the next vertical sync on; the one before, once it
// is no longer read, drawn into next. With no stream to follow, a frame time at 60 Hz instead.
static void show_back(void)
{
    static XTime last;
    dp_show(frames[back]);
    if (dp_wait_shown() != 0)
    {
        XTime now;
        do
            XTime_GetTime(&now);
        while (now - last < COUNTS_PER_SECOND / 60);
    }
    XTime_GetTime(&last);
    back ^= 1;
}

static void show_test_pattern(void)
{
    drawing = 0;
    fill_test_pattern(frames[back]);
    show_back();
    xil_printf("test pattern\r\n");
}

// The frames from now on drawn by mode, colored by shade.
static void start_drawing(void)
{
    if (shade != SHADE_COLOR && !texture_ok)
    {
        xil_printf("%s: no texture\r\n", shade_names[shade]);
        drawing = 0;
        return;
    }
    build_triangle(shade);
    gpu_set_mode(&gpu, mode);
    drawing = 1;
    frames_drawn = 0;
    frames_time = longest = 0;
    XTime_GetTime(&period_start);
    xil_printf("%s, %s\r\n", mode_names[mode], shade_names[shade]);
}

static int us(XTime t)
{
    return (int)(t / (COUNTS_PER_SECOND / 1000000));
}

// One frame, drawn and shown, and once a second a report; drawing stops at one that fails.
static void draw_frame(void)
{
    gpu_frame_t f = {
        .triangles = &triangle,
        .visibility = &visibility,
        .triangle_count = 1,
        .frame = frames[back],
        .stride = STRIDE,
        .width = WIDTH,
        .height = HEIGHT,
        .clear_color = CLEAR_COLOR,
    };
    XTime start, end;
    uint32_t failed_tile = 0;
    XTime_GetTime(&start);
    gpu_status_t status = gpu_frame(&gpu, &f, &failed_tile);
    XTime_GetTime(&end);
    if (status != GPU_OK)
    {
        xil_printf("%s, %s: failed at tile %d: %s\r\n", mode_names[mode], shade_names[shade], (int)failed_tile,
                   gpu_status_name(status));
        drawing = 0;
        return;
    }
    show_back();

    frames_drawn++;
    frames_time += end - start;
    if (end - start > longest)
        longest = end - start;
    XTime now;
    XTime_GetTime(&now);
    if (now - period_start >= COUNTS_PER_SECOND)
    {
        const int rate10 = (int)((XTime)frames_drawn * 10 * COUNTS_PER_SECOND / (now - period_start));
        xil_printf("%s, %s: %d.%d frames/s, frame %d us on average, %d us the longest\r\n", mode_names[mode],
                   shade_names[shade], rate10 / 10, rate10 % 10, us(frames_time / frames_drawn), us(longest));
        frames_drawn = 0;
        frames_time = longest = 0;
        period_start = now;
    }
}

static void print_keys(void)
{
    xil_printf("keys: 1 CPU, 2 command processor; c color, t texture, b blend; r draw again; p test pattern; "
               "? keys\r\n");
}

// A key from the UART console, or -1 if there is none.
static int read_key(void)
{
    if (!XUartPs_IsReceiveData(STDIN_BASEADDRESS))
        return -1;
    return (int)(XUartPs_ReadReg(STDIN_BASEADDRESS, XUARTPS_FIFO_OFFSET) & 0xFF);
}

int main(void)
{
    xil_printf("\r\nRaster demo: gpu_top's raster core at 0x%x\r\n", (int)GPU_BASEADDR);
    if (board_init(&gic) != 0)
    {
        xil_printf("interrupts: GIC setup failed\r\n");
        return 1;
    }
    gpu_init(&gpu, GPU_BASEADDR);

    const int tiles = build_triangle(SHADE_COLOR);
    xil_printf("triangle: (%d, %d) blue, (%d, %d) red, (%d, %d) green; in %d of %d tiles\r\n", (int)corners[0].x,
               (int)corners[0].y, (int)corners[1].x, (int)corners[1].y, (int)corners[2].x, (int)corners[2].y, tiles,
               TILES);
    if (edge(&corners[0], &corners[1], corners[2].x, corners[2].y) <= 0)
        xil_printf("triangle: clockwise or flat, the core draws nothing\r\n");

    fill_checkerboard();
    texture_ok = gpu_set_texture(&gpu, TEX_ID, texture, TEX_LOG2) == 0;
    if (texture_ok)
        xil_printf("texture: %d x %d checkerboard at 0x%x\r\n", TEX_SIZE, TEX_SIZE, (int)(uintptr_t)texture);
    else
        xil_printf("texture: at 0x%x, outside the GPU's texture window\r\n", (int)(uintptr_t)texture);

    fill_test_pattern(frames[back]);
    if (dp_init(&gic, frames[back], STRIDE) != 0)
    {
        xil_printf("DisplayPort: setup failed\r\n");
        return 1;
    }
    back ^= 1;
    xil_printf("DisplayPort: %d x %d at 60 Hz, the test pattern; plug in or pull a monitor\r\n", DP_WIDTH, DP_HEIGHT);
    print_keys();

    for (;;)
    {
        switch (read_key())
        {
        case '1':
            mode = GPU_MODE_CPU;
            start_drawing();
            break;
        case '2':
            mode = GPU_MODE_CP;
            start_drawing();
            break;
        case 'c':
            shade = SHADE_COLOR;
            start_drawing();
            break;
        case 't':
            shade = SHADE_TEXTURE;
            start_drawing();
            break;
        case 'b':
            shade = SHADE_BLEND;
            start_drawing();
            break;
        case 'r':
            start_drawing();
            break;
        case 'p':
            show_test_pattern();
            break;
        case '?':
            print_keys();
            break;
        default: // none, or not a key of ours
            break;
        }
        if (drawing)
            draw_frame();
    }
}
