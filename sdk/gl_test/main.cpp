// Demo of lviv_gl (sdk/lviv_gl) on gpu_top's raster core on the ZCU104 (bd/gpu_test), on the A53
// (standalone), driven from the UART console: a model from a glTF file on the SD card (sdk/gltf),
// with its camera and lights, drawn with OpenGL 1.x calls. At start-up, suzanne.gltf (sdk/sdcard),
// if the card has it.
//
// Keys:
//   1, 2  who draws it: 1 the CPU, tile by tile; 2 the command processor, in one START
//   s     the model turning, or still again
//   r     drawing again, after a frame that failed
//   l     the glTF models (.gltf, .glb) on the SD card, numbered
//   o     another model: its number in l's list, then Enter
//   ?     the keys
//
// Output goes to the PS UART.

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <strings.h> // strcasecmp

#include "board.h"
#include "bspconfig.h" // STDIN_BASEADDRESS
#include "dp.h"
#include "gltf_scene.h"
#include "gpu.h"
#include "gpu_map.h"
#include "lviv_gl.h"
#include "sd.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xiltimer.h" // XTime_GetTime, COUNTS_PER_SECOND
#include "xparameters.h"
#include "xscugic.h"
#include "xuartps_hw.h"

// gpu_0's control port, from the address map of the XSA the platform was made from.
#ifndef GPU_BASEADDR
#define GPU_BASEADDR XPAR_GPU_TOP_BD_0_BASEADDR
#endif

// The GPU's frame, shown on the DP output as it is.
#define WIDTH 1280
#define HEIGHT 720
#define TILES_Y ((HEIGHT + GPU_TILE_SIZE - 1) / GPU_TILE_SIZE)
#define FRAME_ROWS (TILES_Y * GPU_TILE_SIZE) // the tile DMA writes whole tiles
#define STRIDE (WIDTH * 4)
#define FRAME_WORDS (FRAME_ROWS * WIDTH)

static_assert(WIDTH == DP_WIDTH && HEIGHT == DP_HEIGHT, "the frame is shown as it is");

// Two frame buffers: one on the screen, the other drawn into, then shown. The GPU writes them and
// the DPDMA reads them, both behind the CPU's caches: they get 2 MiB blocks of their own (the
// standalone translation table's for DDR below 4 GiB), not cached (main), so that nothing needs a
// cache flush.
#define MMU_BLOCK 0x200000
static union {
    uint32_t frames[2][FRAME_WORDS];
    uint8_t blocks[(sizeof(uint32_t[2][FRAME_WORDS]) + MMU_BLOCK - 1) / MMU_BLOCK * MMU_BLOCK];
} frame_memory __attribute__((aligned(MMU_BLOCK)));
static uint32_t (*const frames)[FRAME_WORDS] = frame_memory.frames;

// lviv_gl's frame memory, where the GPU reads each frame's triangles from: a section of its own at a
// fixed address (lviv_frame.ld)
extern "C" uint8_t lviv_frame_start[], lviv_frame_end[];

static size_t lviv_frame_bytes(void)
{
    return (uintptr_t)lviv_frame_end - (uintptr_t)lviv_frame_start;
}

static gpu_t gpu;
static XScuGic gic; // static: the DP output's interrupt handlers hold on to it

static int back;     // the frame buffer not on the screen
static bool drawing; // a frame after another
static gpu_mode_t mode = GPU_MODE_CPU;

// The model, from the SD card (none: nothing drawn), its file's name; its turn (degrees) and
// whether it turns
static gltf_scene_t *scene;
static char scene_name[64];
static float angle;
static bool turning;
// f: the front end once, then its triangles again every frame (kept: lviv_gl holds them)
static bool keep_triangles, triangles_kept;

// The model drawn from the start, if the card has it (none otherwise, until o opens one)
static const char start_model[] = "0:/suzanne.gltf";

// Since the last report, from period_start: the frames drawn, the sum of their times (us) and of
// their squares, of the front end's times (us), of the command processor's cycle counts and of the
// tile DMA's for each frame's last tile write-back.
static uint64_t frames_drawn, frame_us, frame_us2, front_us, cp_cycles, tile_cycles;
static XTime period_start;

static const char *mode_name(void)
{
    return mode == GPU_MODE_CP ? "CP" : "CPU";
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

// A frame of the model, turned by angle about its vertical axis, for lviv_gl_frame
static void draw_scene(void)
{
    gltf_scene_draw(scene, angle);
    if (turning)
        angle = angle >= 359.0f ? 0.0f : angle + 1.0f;
}

// The frames from now on drawn by mode, once there is a model.
static void start_drawing(void)
{
    if (!scene)
    {
        xil_printf("no model: l lists the SD card's, o opens one\r\n");
        return;
    }
    gpu_set_mode(&gpu, mode);
    drawing = true;
    frames_drawn = frame_us = frame_us2 = front_us = cp_cycles = tile_cycles = 0;
    XTime_GetTime(&period_start);
    xil_printf("%s, %s\r\n", mode_name(), scene_name);
}

// One frame, drawn and shown, and once a second a report; drawing stops at one that fails.
static void draw_frame(void)
{
    XTime start, front, end;
    uint32_t failed_tile = 0;
    const bool again = keep_triangles && triangles_kept;
    XTime_GetTime(&start);
    if (!again)
        draw_scene();
    XTime_GetTime(&front);
    const gpu_status_t status = again ? lviv_gl_frame_again(frames[back], STRIDE, &failed_tile)
                                      : lviv_gl_frame(frames[back], STRIDE, &failed_tile);
    XTime_GetTime(&end);
    triangles_kept = true;
    if (status != GPU_OK)
    {
        xil_printf("%s, %s: failed at tile %d: %s\r\n", mode_name(), scene_name, (int)failed_tile,
                   gpu_status_name(status));
        drawing = false;
        return;
    }
    show_back();

    const uint64_t t = (end - front) / (COUNTS_PER_SECOND / 1000000);
    frames_drawn++;
    frame_us += t;
    frame_us2 += t * t;
    front_us += (front - start) / (COUNTS_PER_SECOND / 1000000);
    if (mode == GPU_MODE_CP)
        cp_cycles += gpu_cp_frame_cycles(&gpu);
    tile_cycles += gpu_tile_dma_cycles(&gpu);
    XTime now;
    XTime_GetTime(&now);
    if (now - period_start >= COUNTS_PER_SECOND)
    {
        const uint64_t n = frames_drawn;
        const int rate10 = (int)(n * 10 * COUNTS_PER_SECOND / (now - period_start));
        // n * (sum of squares) - sum^2 is n^2 times the variance, never negative.
        const double deviation = std::sqrt((double)(n * frame_us2 - frame_us * frame_us)) / (double)n;
        xil_printf("%s, %s: %d.%d frames/s, frame time %d \u00b1 %d us, front end %d us, %d triangles (",
                   mode_name(), scene_name, rate10 / 10, rate10 % 10, (int)(frame_us / n), (int)deviation,
                   (int)(front_us / n), (int)lviv_gl_triangles());
        if (mode == GPU_MODE_CP)
            xil_printf("CP cycle counter: %d, ", (int)(cp_cycles / n));
        xil_printf("tile write-back: %d cycles)\r\n", (int)(tile_cycles / n));
        frames_drawn = frame_us = frame_us2 = front_us = cp_cycles = tile_cycles = 0;
        period_start = now;
    }
}

static void print_keys(void)
{
    xil_printf("keys: 1 CPU, 2 command processor; s turn the model or stop it; f front end every frame or "
               "once; r draw again; l SD card; o open a model; ? keys\r\n");
}

// A key from the UART console, or -1 if there is none.
static int read_key(void)
{
    if (!XUartPs_IsReceiveData(STDIN_BASEADDRESS))
        return -1;
    return (int)(XUartPs_ReadReg(STDIN_BASEADDRESS, XUARTPS_FIFO_OFFSET) & 0xFF);
}

// A number typed at the console, echoed, up to Enter; -1 for none, or Esc
static int read_number(void)
{
    int n = -1;
    for (;;)
    {
        const int key = read_key();
        if (key >= '0' && key <= '9' && n < 100000)
        {
            n = (n < 0 ? 0 : n * 10) + (key - '0');
            xil_printf("%c", key);
        }
        else if ((key == '\b' || key == 0x7f) && n >= 0)
        {
            n = n >= 10 ? n / 10 : -1;
            xil_printf("\b \b");
        }
        else if (key == '\r' || key == '\n' || key == 0x1b)
        {
            xil_printf("\r\n");
            return key == 0x1b ? -1 : n;
        }
    }
}

// The glTF files (.gltf, .glb) in the SD card's root, numbered from 1 in the directory's order, for
// l (wanted 0: printed) and o (the path of the one wanted, in path; none found, empty)
struct sd_listing
{
    int wanted;
    int models; // the glTF files so far
    char path[300];
};

static void list_entry(const sd_entry_t *entry, void *user)
{
    sd_listing &l = *static_cast<sd_listing *>(user);
    const char *dot = std::strrchr(entry->name, '.');
    if (entry->directory || !dot || (strcasecmp(dot, ".gltf") != 0 && strcasecmp(dot, ".glb") != 0))
        return;
    l.models++;
    if (l.wanted == 0)
        xil_printf("  %4d  %s  %u bytes\r\n", l.models, entry->name, (unsigned)entry->size);
    else if (l.models == l.wanted)
        std::snprintf(l.path, sizeof l.path, "0:/%s", entry->name);
}

// The SD card's glTF file at path ("0:/...") drawn from then on, from the front, by mode. The model
// so far stays if it does not load; with missing_ok, quietly when there is no such file.
static void load_model(const char *path, bool missing_ok)
{
    XTime start, read, parsed;
    XTime_GetTime(&start);
    void *data;
    size_t size;
    const int error = sd_read(path, &data, &size, GLTF_SCENE_PADDING);
    if (error != 0)
    {
        if (!missing_ok || error != SD_NO_FILE)
            xil_printf("%s: %s\r\n", path, sd_error_name(error));
        return;
    }
    XTime_GetTime(&read);
    char message[128];
    gltf_scene_t *loaded = gltf_scene_load(data, size, message, sizeof message);
    free(data);
    XTime_GetTime(&parsed);
    if (!loaded)
    {
        xil_printf("%s: %s\r\n", path, message);
        return;
    }
    gltf_scene_free(scene);
    scene = loaded;
    triangles_kept = false;
    std::snprintf(scene_name, sizeof scene_name, "%s", path + 3);
    gltf_scene_setup(scene, WIDTH, HEIGHT);
    xil_printf("model: %s, %d triangles, %d texture%s, %d light%s, %s camera; %u bytes read in %d ms, parsed in %d "
               "ms\r\n",
               scene_name, gltf_scene_triangles(scene), gltf_scene_textures(scene),
               gltf_scene_textures(scene) == 1 ? "" : "s", gltf_scene_lights(scene),
               gltf_scene_lights(scene) == 1 ? "" : "s", gltf_scene_has_camera(scene) ? "its" : "the default",
               (unsigned)size, (int)((read - start) / (COUNTS_PER_SECOND / 1000)),
               (int)((parsed - read) / (COUNTS_PER_SECOND / 1000)));
    angle = 0;
    start_drawing();
}

// The SD card's glTF file n (l's numbers), as load_model
static void open_model(int n)
{
    sd_listing l = {n, 0, ""};
    const int error = sd_scan("0:/", list_entry, &l);
    if (error != 0)
    {
        xil_printf("SD card: %s\r\n", sd_error_name(error));
        return;
    }
    if (l.path[0] == '\0')
    {
        xil_printf("model: no glTF file %d on the SD card, of %d\r\n", n, l.models);
        return;
    }
    load_model(l.path, false);
}

int main(void)
{
    xil_printf("\r\nlviv_gl demo: gpu_top's raster core at 0x%x\r\n", (int)GPU_BASEADDR);
    if (board_init(&gic) != 0)
    {
        xil_printf("interrupts: GIC setup failed\r\n");
        return 1;
    }
    gpu_init(&gpu, GPU_BASEADDR);
    for (UINTPTR block = (UINTPTR)&frame_memory; block < (UINTPTR)&frame_memory + sizeof frame_memory;
         block += MMU_BLOCK)
        Xil_SetTlbAttributes(block, NORM_NONCACHE); // also writes back what the cache held of it

    if (lviv_gl_init(&gpu, WIDTH, HEIGHT, lviv_frame_start, lviv_frame_bytes()) != 0)
    {
        xil_printf("lviv_gl: setup failed\r\n");
        return 1;
    }
    glClearColor(0x63 / 255.0f, 0x63 / 255.0f, 0x63 / 255.0f, 1.0f); // raster_sw's
    xil_printf("lviv_gl: frame memory at 0x%x, %d MiB: %d triangles a frame\r\n", (int)(uintptr_t)lviv_frame_start,
               (int)(lviv_frame_bytes() >> 20), (int)(lviv_frame_bytes() / LVIV_GL_TRIANGLE_BYTES));

    // Black (the frame buffers start zeroed) until the first frame is shown
    if (dp_init(&gic, frames[back], STRIDE) != 0)
    {
        xil_printf("DisplayPort: setup failed\r\n");
        return 1;
    }
    back ^= 1;
    xil_printf("DisplayPort: %d x %d at 60 Hz; plug in or pull a monitor\r\n", DP_WIDTH, DP_HEIGHT);
    print_keys();
    load_model(start_model, true);

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
        case 's':
            turning = !turning;
            xil_printf("model: %s\r\n", turning ? "turning" : "still");
            break;
        case 'f':
            keep_triangles = !keep_triangles;
            xil_printf("front end: %s\r\n", keep_triangles ? "once, then the GPU alone" : "every frame");
            break;
        case 'r':
            start_drawing();
            break;
        case 'l': {
            xil_printf("glTF files on the SD card, 0:/ (o and a number to draw one)\r\n");
            sd_listing l = {0, 0, ""};
            const int error = sd_scan("0:/", list_entry, &l);
            if (error != 0)
                xil_printf("SD card: %s\r\n", sd_error_name(error));
            else if (l.models == 0)
                xil_printf("  none\r\n");
            break;
        }
        case 'o': {
            xil_printf("model (its number in l's list, Enter): ");
            const int n = read_number();
            if (n >= 0)
                open_model(n);
            break;
        }
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
