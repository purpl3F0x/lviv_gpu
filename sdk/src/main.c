// GPU bring-up demo for bd/dummy_test: gpu_top with dummy_core, on the ZCU104's A53 (standalone).
//
//  0. Test pattern: colour ramps on the PS's DP output at DP_WIDTH x DP_HEIGHT, 60 Hz (dp.c), until
//     Enter is pressed on the UART, to check the display on its own.
//  1. Register check: write and read back registers through the crossbar.
//  2. Scene: random triangles, and a fake visibility stream from their bounding boxes (bit t of
//     a triangle's word is set when its box overlaps tile t), as a binner would produce.
//  3. Frame: 1280 x 720 in 10 x 6 tiles of 128 x 128, each streamed by the visibility DMA and the
//     DataMover into the core, then written back by the tile DMA.
//  4. Check: dummy_core paints each tile with A = 0xFF, R = 2 * x, G = 2 * y (x, y in the tile)
//     and B = the number of triangles the tile received, so every pixel is known in advance.
//  5. Interrupts: each DMA's line on its own (an event forced from software interrupts once, on
//     that DMA's handler; masked, it waits until unmasked), then the frame again, waiting for the
//     DMAs' interrupts instead of polling them: one per tile from each.
//  6. DisplayPort: the last frame instead of the test pattern (in its top-left corner on a larger
//     output), the link brought up and down as a monitor is plugged in and pulled, for as long as
//     the board runs.
//
// Output goes to the PS UART.

#include <stdint.h>
#include <string.h>

#include "bspconfig.h"
#include "dp.h"
#include "gpu.h"
#include "gpu_map.h"
#include "sleep.h"
#include "xil_assert.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xiltimer.h" // XTime_GetTime, COUNTS_PER_SECOND
#include "xinterrupt_wrap.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xuartps_hw.h"

// gpu_0's control port, from the address map of the XSA the platform was made from. The
// canonical name (IP gpu_top_bd, instance 0): XPAR_GPU_BASEADDR is the PS's Mali GPU.
#ifndef GPU_BASEADDR
#define GPU_BASEADDR XPAR_GPU_TOP_BD_0_BASEADDR
#endif

// pl_ps_irq0[n] is XPS_FPGAn_INT_ID; bd/dummy_test's irq_concat has vis_dma_irq on In0 and
// tile_dma_irq on In1 (the interrupts of gpu_0 in the platform's hw/sdt/pl.dtsi).
#define GPU_VIS_DMA_INT_ID XPS_FPGA0_INT_ID
#define GPU_TILE_DMA_INT_ID XPS_FPGA1_INT_ID

// The GPU's frame: at most 64 tiles, a bit each in a triangle's visibility word.
#define WIDTH 1280
#define HEIGHT 720
#define TILES_X (WIDTH / GPU_TILE_SIZE)
#define TILES_Y ((HEIGHT + GPU_TILE_SIZE - 1) / GPU_TILE_SIZE)
#define TILES (TILES_X * TILES_Y)
#define FRAME_ROWS (TILES_Y * GPU_TILE_SIZE) // the tile DMA writes whole tiles
#define STRIDE (WIDTH * 4)
#define TRIANGLES 512

static gpu_triangle_t triangles[TRIANGLES] __attribute__((aligned(64)));
static uint64_t visibility[TRIANGLES] __attribute__((aligned(64)));
static uint32_t frame[FRAME_ROWS * WIDTH] __attribute__((aligned(4096)));
static uint32_t screen[DP_HEIGHT * DP_WIDTH] __attribute__((aligned(4096))); // what the DP output shows
static uint32_t tile_triangles[TILES];

// Static: the interrupt handlers hold on to both.
static gpu_t gpu;
static XScuGic gic;

// A failed assert in a driver stops the program where it is, silently: say where.
static void on_assert(const char8 *file, s32 line)
{
    xil_printf("assert failed: %s, line %d\r\n", file, (int)line);
}

static uint32_t rng_state = 1;

static uint32_t rng(uint32_t range)
{
    rng_state = rng_state * 1664525u + 1013904223u;
    return (rng_state >> 8) % range;
}

static int min3(int a, int b, int c)
{
    return a < b ? (a < c ? a : c) : (b < c ? b : c);
}
static int max3(int a, int b, int c)
{
    return a > b ? (a > c ? a : c) : (b > c ? b : c);
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
// into blue with green rising downwards (two bands): the colour order and the levels.
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
            p[y * DP_WIDTH + x] = c;
        }
    }
}

// The frame on the screen, in its top-left corner, black around it.
static void show_frame(void)
{
    for (int y = 0; y < DP_HEIGHT; y++)
        for (int x = 0; x < DP_WIDTH; x++)
            screen[y * DP_WIDTH + x] = x < WIDTH && y < HEIGHT ? frame[y * WIDTH + x] : 0xFF000000u;
    dp_show(screen);
}

// Until Enter on the UART, following the monitor meanwhile.
static void wait_for_enter(int display)
{
    while (XUartPs_IsReceiveData(STDIN_BASEADDRESS))
        (void)XUartPs_ReadReg(STDIN_BASEADDRESS, XUARTPS_FIFO_OFFSET);
    for (;;)
    {
        if (display)
            dp_service();
        if (XUartPs_IsReceiveData(STDIN_BASEADDRESS))
        {
            const u8 c = (u8)XUartPs_ReadReg(STDIN_BASEADDRESS, XUARTPS_FIFO_OFFSET);
            if (c == '\r' || c == '\n')
                return;
        }
    }
}

static int check_registers(const gpu_t *gpu)
{
    int errors = 0;
    uint32_t value;

    gpu_set_tile(gpu, 3, 2);
    value = gpu_read(gpu, GPU_FRONTEND_OFFSET + APB_FRONT_END_FRONTEND_REG_TILE_X);
    if ((value & APB_FRONT_END_FRONTEND_REG_TILE_X_TILE_X_MASK) != 3)
    {
        xil_printf("  frontend TILE_X read 0x%x, expected 3\r\n", (int)value);
        errors++;
    }
    gpu_set_tile(gpu, 0, 0);

    gpu_write(gpu, GPU_LUT_BASE(5), 0x12345600u);
    value = gpu_read(gpu, GPU_LUT_BASE(5));
    if (value != 0x12345600u)
    {
        xil_printf("  texture LUT base 5 read 0x%x, expected 0x12345600\r\n", (int)value);
        errors++;
    }
    gpu_write(gpu, GPU_LUT_BASE(5), 0);

    if (gpu_wait_idle(gpu) != GPU_OK)
    {
        xil_printf("  core not idle after reset\r\n");
        errors++;
    }
    return errors;
}

static void build_scene(void)
{
    memset(tile_triangles, 0, sizeof tile_triangles);
    for (int i = 0; i < TRIANGLES; i++)
    {
        gpu_triangle_t *t = &triangles[i];
        int cx = (int)rng(WIDTH), cy = (int)rng(HEIGHT), size = 8 + (int)rng(240);
        int x[3], y[3];
        memset(t, 0, sizeof *t);
        for (int v = 0; v < 3; v++)
        {
            x[v] = cx + (int)rng(size) - size / 2;
            y[v] = cy + (int)rng(size) - size / 2;
            t->v[v].x = (float)x[v];
            t->v[v].y = (float)y[v];
            t->v[v].z = 0.5f;
            t->v[v].w = 1.0f;
            t->v[v].color = 0xFF000000u | rng(0x1000000);
        }
        t->tex_id = GPU_TEX_ID_NONE;
        t->texture_function = 5;                                                // COLOR
        t->blend = (1u << GPU_SFACTOR_OP_SHIFT) | (0u << GPU_DFACTOR_OP_SHIFT); // ONE, ZERO
        t->depth_func = 1;                                                      // LESS

        // Bounding box against the tiles, clipped to the screen.
        int x0 = min3(x[0], x[1], x[2]), x1 = max3(x[0], x[1], x[2]);
        int y0 = min3(y[0], y[1], y[2]), y1 = max3(y[0], y[1], y[2]);
        if (x0 < 0)
            x0 = 0;
        if (y0 < 0)
            y0 = 0;
        if (x1 > WIDTH - 1)
            x1 = WIDTH - 1;
        if (y1 > HEIGHT - 1)
            y1 = HEIGHT - 1;
        visibility[i] = 0;
        if (x0 > x1 || y0 > y1)
            continue;
        for (int ty = y0 / GPU_TILE_SIZE; ty <= y1 / GPU_TILE_SIZE; ty++)
        {
            for (int tx = x0 / GPU_TILE_SIZE; tx <= x1 / GPU_TILE_SIZE; tx++)
            {
                visibility[i] |= 1ull << (ty * TILES_X + tx);
                tile_triangles[ty * TILES_X + tx]++;
            }
        }
    }
}

static int check_frame(void)
{
    int wrong = 0;
    for (int y = 0; y < FRAME_ROWS; y++)
    {
        for (int x = 0; x < WIDTH; x++)
        {
            uint32_t count = tile_triangles[(y / GPU_TILE_SIZE) * TILES_X + x / GPU_TILE_SIZE];
            uint32_t want = 0xFF000000u | (uint32_t)(2 * (x % GPU_TILE_SIZE)) << 16 |
                            (uint32_t)(2 * (y % GPU_TILE_SIZE)) << 8 | (count > 255 ? 255 : count);
            uint32_t got = frame[y * WIDTH + x];
            if (got != want)
            {
                if (wrong < 8)
                    xil_printf("  pixel (%d, %d): 0x%08x, expected 0x%08x\r\n", x, y, (int)got, (int)want);
                wrong++;
            }
        }
    }
    return wrong;
}

// The frame from the scene, checked pixel by pixel; returns the errors.
static int render(const gpu_frame_t *f, const char *how)
{
    XTime start, end;
    uint32_t failed_tile = 0;

    memset(frame, 0, sizeof frame);
    XTime_GetTime(&start);
    gpu_status_t status = gpu_frame(&gpu, f, &failed_tile);
    XTime_GetTime(&end);
    if (status != GPU_OK)
    {
        xil_printf("frame (%s): FAIL at tile %d: %s\r\n", how, (int)failed_tile, gpu_status_name(status));
        return 1;
    }
    xil_printf("frame (%s): %d us\r\n", how, (int)((end - start) / (COUNTS_PER_SECOND / 1000000)));

    int wrong = check_frame();
    xil_printf("image: %d of %d pixels wrong\r\n", wrong, FRAME_ROWS * WIDTH);
    return wrong;
}

// The GIC, interrupts on: the DP output's first, the DMAs' later (setup_interrupts).
static int setup_gic(void)
{
    XScuGic_Config *config = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    if (config == NULL || XScuGic_CfgInitialize(&gic, config, config->CpuBaseAddress) != XST_SUCCESS)
        return -1;
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, (Xil_ExceptionHandler)XScuGic_InterruptHandler, &gic);
    Xil_ExceptionEnable();
    return 0;
}

// The DMAs' handlers on their lines.
static int setup_interrupts(void)
{
    const u32 ids[GPU_IRQS] = {GPU_VIS_DMA_INT_ID, GPU_TILE_DMA_INT_ID};
    const Xil_InterruptHandler handlers[GPU_IRQS] = {gpu_vis_dma_isr, gpu_tile_dma_isr};

    // Nothing left over from the polled frame, which would interrupt at once.
    gpu_write(&gpu, GPU_VIS_DMA_OFFSET + GPU_INT_RAW, GPU_INT_ALL);
    gpu_write(&gpu, GPU_TILE_DMA_OFFSET + GPU_INT_RAW, GPU_INT_ALL);

    for (int irq = 0; irq < GPU_IRQS; irq++)
    {
        // Level, active high, as the DMAs drive their lines.
        XScuGic_SetPriorityTriggerType(&gic, ids[irq], XINTERRUPT_DEFAULT_PRIORITY, XINTR_IS_LEVEL_TRIGGERED);
        if (XScuGic_Connect(&gic, ids[irq], handlers[irq], &gpu) != XST_SUCCESS)
            return -1;
        XScuGic_Enable(&gic, ids[irq]);
    }
    return 0;
}

// One DMA's interrupt line, with no transfer: an event forced from software interrupts once, on
// this DMA's handler (on the other's it would count as spurious there); masked, it waits until it
// is unmasked. Returns the errors.
static int check_interrupt(gpu_irq_t irq, uint32_t block, const char *name)
{
    int errors = 0;
    const uint32_t before = gpu.irq_count[irq];

    gpu_write(&gpu, block + GPU_INT_FORCE, GPU_INT_DONE);
    usleep(100);
    if (gpu.irq_count[irq] != before + 1)
    {
        xil_printf("  %s: forced event, %d interrupts, expected 1\r\n", name, (int)(gpu.irq_count[irq] - before));
        errors++;
    }

    gpu_write(&gpu, block + GPU_INT_MASK, GPU_INT_DONE);
    gpu_write(&gpu, block + GPU_INT_FORCE, GPU_INT_DONE);
    usleep(100);
    if (gpu.irq_count[irq] != before + 1)
    {
        xil_printf("  %s: masked event interrupted\r\n", name);
        errors++;
    }
    gpu_write(&gpu, block + GPU_INT_MASK, 0);
    usleep(100);
    if (gpu.irq_count[irq] != before + 2)
    {
        xil_printf("  %s: unmasked event, %d interrupts, expected 1\r\n", name, (int)(gpu.irq_count[irq] - before - 1));
        errors++;
    }

    uint32_t raw = gpu_read(&gpu, block + GPU_INT_RAW);
    if (raw != 0)
    {
        xil_printf("  %s: events 0x%x left after the interrupts\r\n", name, (int)raw);
        errors++;
    }
    return errors;
}

int main(void)
{
    int errors = 0;

    Xil_AssertSetCallback(on_assert);
    xil_printf("\r\nGPU demo: gpu_top with dummy_core at 0x%x\r\n", (int)GPU_BASEADDR);
    if (setup_gic() != 0)
    {
        xil_printf("interrupts: GIC setup failed\r\n");
        return 1;
    }

    _Static_assert(WIDTH <= DP_WIDTH && HEIGHT <= DP_HEIGHT, "the frame is larger than the DP output");
    fill_test_pattern(screen);
    const int display = dp_init(&gic, screen, DP_WIDTH * 4) == 0;
    if (display)
        xil_printf("DisplayPort: test pattern, %d x %d at 60 Hz; press Enter to run the GPU tests\r\n", DP_WIDTH,
                   DP_HEIGHT);
    else
        xil_printf("DisplayPort: setup failed; press Enter to run the GPU tests\r\n");
    wait_for_enter(display);

    gpu_init(&gpu, GPU_BASEADDR);

    int register_errors = check_registers(&gpu);
    xil_printf("register check: %s\r\n", register_errors ? "FAIL" : "ok");
    errors += register_errors;

    build_scene();
    int visible = 0;
    for (int t = 0; t < TILES; t++)
        visible += (int)tile_triangles[t];
    xil_printf("scene: %d triangles, %d triangle-tile pairs over %d tiles\r\n", TRIANGLES, visible, TILES);

    gpu_frame_t f = {
        .triangles = triangles,
        .visibility = visibility,
        .triangle_count = TRIANGLES,
        .frame = frame,
        .stride = STRIDE,
        .tiles_x = TILES_X,
        .tiles_y = TILES_Y,
        .clear_color = 0x00000000, // dummy_core ignores it: its frame buffer is a pattern
    };
    errors += render(&f, "polled");

    if (setup_interrupts() != 0)
    {
        xil_printf("interrupts: DMA interrupt setup failed\r\n");
        return 1;
    }
    int line_errors = check_interrupt(GPU_IRQ_VIS_DMA, GPU_VIS_DMA_OFFSET, "visibility DMA") +
                      check_interrupt(GPU_IRQ_TILE_DMA, GPU_TILE_DMA_OFFSET, "tile DMA");
    xil_printf("interrupt lines: %s\r\n", line_errors ? "FAIL" : "ok");
    errors += line_errors;

    const uint32_t vis_before = gpu.irq_count[GPU_IRQ_VIS_DMA], tile_before = gpu.irq_count[GPU_IRQ_TILE_DMA];
    gpu.use_interrupts = 1;
    errors += render(&f, "interrupts");
    gpu.use_interrupts = 0;
    int vis_irqs = (int)(gpu.irq_count[GPU_IRQ_VIS_DMA] - vis_before);
    int tile_irqs = (int)(gpu.irq_count[GPU_IRQ_TILE_DMA] - tile_before);
    int spurious = (int)(gpu.irq_spurious[GPU_IRQ_VIS_DMA] + gpu.irq_spurious[GPU_IRQ_TILE_DMA]);
    xil_printf("interrupts: %d visibility DMA, %d tile DMA (expected %d each), %d spurious\r\n", vis_irqs, tile_irqs,
               TILES, spurious);
    if (vis_irqs != TILES || tile_irqs != TILES || spurious)
        errors++;

    xil_printf("%s\r\n", errors ? "FAIL" : "PASS");

    if (!display)
        return errors ? 1 : 0;
    show_frame();
    xil_printf("DisplayPort: showing the frame (%d x %d) at %d x %d, 60 Hz; plug in or pull a monitor\r\n", WIDTH,
               HEIGHT, DP_WIDTH, DP_HEIGHT);
    for (;;)
        dp_service();
}
