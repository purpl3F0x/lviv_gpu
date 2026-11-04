// Demo of lviv_gl (sdk/lviv_gl) on gpu_top's raster core on the ZCU104 (bd/gpu_test), on the A53
// (standalone), driven from the UART console: a model from a glTF file on the SD card (sdk/gltf),
// with its camera and lights, drawn with OpenGL 1.x calls. It starts at the setup menu, logo.png at
// its top (in the program: logo_png.h, scripts/ui_assets.py's).
//
// Keys:
//   1, 2  who draws it: 1 the CPU, tile by tile; 2 the command processor, in one START
//   s     the model turning, or still again
//   r     drawing again, after a frame that failed
//   l     the glTF models (.gltf, .glb) on the SD card, numbered
//   o     another model: its number in l's list, then Enter
//   m     the setup menu (menu.cpp), alone on the screen while it is up, nothing drawn: the test
//         pattern, the settings (the DP output: 1280 x 720, or 1920 x 1080 with the 1280 x 720
//         picture in its center), or one of the SD card's models. Its keys: the arrows (or w, a, s
//         and d), Enter, Esc
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
#include "logo_png.h"
#include "lviv_gl.h"
#include "menu.h"
#include "sd.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xiltimer.h" // XTime_GetTime, COUNTS_PER_SECOND
#include "xparameters.h"
#include "xscugic.h"
#include "xuartps_hw.h"

// gpu_0's control port, from the address map of the XSA the platform was made from.
#ifndef GPU_BASEADDR
#define GPU_BASEADDR GPU_CTRL_BASEADDR
#endif

// The GPU's frame: shown as it is on a 1280 x 720 output, or in the center of a 1920 x 1080 one with
// black round it (the settings' wide output).
#define WIDTH 1280
#define HEIGHT 720
#define TILES_Y ((HEIGHT + GPU_TILE_SIZE - 1) / GPU_TILE_SIZE)
#define FRAME_ROWS (TILES_Y * GPU_TILE_SIZE) // the tile DMA writes whole tiles
#define STRIDE (WIDTH * 4)
#define WIDE_W 1920
#define WIDE_H 1080
#define WIDE_STRIDE (WIDE_W * 4)

static_assert(WIDTH == DP_WIDTH && HEIGHT == DP_HEIGHT, "the frame is shown as it is from the start");
static_assert(WIDTH % GPU_TILE_SIZE == 0, "whole tiles across: none past the frame's right edge");

// The frame buffers the DP output takes turns with (dp.h): one on the screen, one on its way there,
// one drawn into, so that the GPU draws as fast as it can. The GPU writes them and the DPDMA reads
// them, both behind the CPU's caches: they get 2 MiB blocks of their own (the standalone translation
// table's for DDR below 4 GiB), not cached (main), so that nothing needs a cache flush. Each holds the
// GPU's frame at its start, or a wide output with the GPU's frame in its center at WIDE_FRAME (the
// tile DMA's alignment), the output starting WIDE_OFFSET before it (aligned for the DPDMA).
#define MMU_BLOCK 0x200000
#define BUFFER_BYTES (8u << 20)
#define WIDE_OFFSET ((((WIDE_H - HEIGHT) / 2) * WIDE_W + (WIDE_W - WIDTH) / 2) * 4)
#define WIDE_FRAME ((WIDE_OFFSET + GPU_FRAME_ALIGN - 1) / GPU_FRAME_ALIGN * GPU_FRAME_ALIGN)
static_assert(WIDE_OFFSET % 256 == 0 && WIDE_FRAME - WIDE_OFFSET + WIDE_H * WIDE_STRIDE <= BUFFER_BYTES,
              "the wide output in a buffer, 256-byte aligned, with the GPU's frame in its center");
static uint8_t frame_memory[DP_FRAMES][BUFFER_BYTES] __attribute__((aligned(MMU_BLOCK)));
static bool wide; // the output at 1920 x 1080

// Buffer f as the DP output reads it; the GPU's frame in such a buffer; their stride
static uint32_t *output_buffer(int f)
{
    return reinterpret_cast<uint32_t *>(frame_memory[f] + (wide ? WIDE_FRAME - WIDE_OFFSET : 0));
}

static uint32_t *frame_in(uint32_t *output)
{
    return wide ? output + WIDE_OFFSET / 4 : output;
}

static uint32_t frame_stride(void)
{
    return wide ? WIDE_STRIDE : STRIDE;
}

// lviv_gl's frame memory, where the GPU reads each frame's triangles from: a section of its own at a
// fixed address (lviv_frame.ld)
extern "C" uint8_t lviv_frame_start[], lviv_frame_end[];

static size_t lviv_frame_bytes(void)
{
    return (uintptr_t)lviv_frame_end - (uintptr_t)lviv_frame_start;
}

static gpu_t gpu;
static XScuGic gic; // static: the DP output's interrupt handlers hold on to it

static bool drawing;       // a frame after another
static bool pattern_shown; // the test pattern on the screen, not the model
static gpu_mode_t mode = GPU_MODE_CPU;

// The setup menu: up or not, its page and the item selected on it, a line about that one. The main
// page: the test pattern, the settings, then the SD card's glTF files as when the menu came up; the
// settings: the output, back.
#define MENU_MODELS 64
enum menu_page_t
{
    MENU_MAIN,
    MENU_SETTINGS,
};
enum
{
    ITEM_PATTERN,
    ITEM_SETTINGS,
    ITEM_FIRST_MODEL,
};
enum
{
    ITEM_OUTPUT,
    ITEM_BACK,
    SETTINGS_ITEMS,
};
static bool menu_up;
static menu_page_t menu_page;
static int menu_models;
static char menu_names[MENU_MODELS][256];
static uint64_t menu_sizes[MENU_MODELS];
static int menu_selected;
static char menu_about[160];
static ui_image_t menu_logo; // logo.png, decoded at start-up (none: no pixels)

// The model, from the SD card (none: nothing drawn), its file's name; its turn (degrees) and
// whether it turns, TURN_RATE degrees a second whatever the frame rate
#define TURN_RATE 60.0f
static gltf_scene_t *scene;
static char scene_name[64];
static float angle;
static bool turning;
// f: the front end once, then its triangles again every frame (kept: lviv_gl holds them)
static bool keep_triangles, triangles_kept;

// Since the last report, from period_start: the frames drawn, the sum of their times (us) and of
// their squares, of the front end's times (us), of the command processor's cycle counts and of the
// tile DMA's for each frame's last tile write-back; dp_frames_shown then.
static uint64_t frames_drawn, frame_us, frame_us2, front_us, cp_cycles, tile_cycles;
static XTime period_start;
static uint32_t period_shown;

static const char *mode_name(void)
{
    return mode == GPU_MODE_CP ? "CP" : "CPU";
}

// A frame of the model, turned by angle about its vertical axis, for lviv_gl_frame; the angle on by
// the time since the last (a tenth of a second at most, after a pause)
static void draw_scene(void)
{
    static XTime last;
    XTime now;
    XTime_GetTime(&now);
    const float seconds = std::fmin((float)(now - last) / COUNTS_PER_SECOND, 0.1f);
    last = now;
    if (turning)
        angle = std::fmod(angle + TURN_RATE * seconds, 360.0f);
    gltf_scene_draw(scene, angle);
}

// The report's period from now on
static void restart_report(void)
{
    frames_drawn = frame_us = frame_us2 = front_us = cp_cycles = tile_cycles = 0;
    gpu_vis_dma_counters_clear(&gpu);
    XTime_GetTime(&period_start);
    period_shown = dp_frames_shown();
}

// The frames from now on drawn by mode, once there is a model.
static void start_drawing(void)
{
    if (!scene)
    {
        xil_printf("no model: l lists the SD card's, o opens one, m the menu\r\n");
        return;
    }
    gpu_set_mode(&gpu, mode);
    drawing = true;
    pattern_shown = false;
    restart_report();
    xil_printf("%s, %s\r\n", mode_name(), scene_name);
}

// One frame, drawn and sent to the screen without waiting for it, and once a second a report;
// drawing stops at one that fails.
static void draw_frame(void)
{
    XTime start, front, end;
    uint32_t failed_tile = 0;
    const bool again = keep_triangles && triangles_kept;
    XTime_GetTime(&start);
    if (!again)
        draw_scene();
    XTime_GetTime(&front);
    // Taken after the front end: until then, a frame waiting for the screen can still be sent
    uint32_t *const frame = frame_in(dp_back());
    const uint32_t stride = frame_stride();
    const gpu_status_t status =
        again ? lviv_gl_frame_again(frame, stride, &failed_tile) : lviv_gl_frame(frame, stride, &failed_tile);
    XTime_GetTime(&end);
    if (wide)
    {
        // The last row of tiles' rows under the frame, on the wide output: black again
        const ui_canvas_t below = {frame + HEIGHT * WIDE_W, WIDE_W, WIDTH, FRAME_ROWS - HEIGHT};
        ui_fill(&below, 0, 0, WIDTH, FRAME_ROWS - HEIGHT, ui_rgb(0, 0, 0));
    }
    triangles_kept = true;
    if (status != GPU_OK)
    {
        xil_printf("%s, %s: failed at tile %d: %s\r\n", mode_name(), scene_name, (int)failed_tile,
                   gpu_status_name(status));
        drawing = false;
        return;
    }
    dp_present();

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
        const uint32_t shown = dp_frames_shown();
        const int rate10 = (int)(n * 10 * COUNTS_PER_SECOND / (now - period_start));
        const int shown10 = (int)((uint64_t)(shown - period_shown) * 10 * COUNTS_PER_SECOND / (now - period_start));
        // n * (sum of squares) - sum^2 is n^2 times the variance, never negative.
        const double deviation = std::sqrt((double)(n * frame_us2 - frame_us * frame_us)) / (double)n;
        xil_printf("%s, %s: %d.%d frames/s (%d.%d shown), frame time %d \u00b1 %d us, front end %d us, %d triangles (",
                   mode_name(), scene_name, rate10 / 10, rate10 % 10, shown10 / 10, shown10 % 10, (int)(frame_us / n),
                   (int)deviation, (int)(front_us / n), (int)lviv_gl_triangles());
        if (mode == GPU_MODE_CP)
            xil_printf("CP cycle counter: %d, ", (int)(cp_cycles / n));
        xil_printf("tile write-back: %d cycles)\r\n", (int)(tile_cycles / n));
        gpu_vis_dma_counters_t vis;
        gpu_vis_dma_counters(&gpu, &vis);
        xil_printf("  visibility DMA a frame (mem_clk cycles): busy %d; waiting for visibility %d, commands %d, "
                   "retire %d; triangles starved %d, held by the core %d\r\n",
                   (int)(vis.busy / n), (int)(vis.vb_wait / n), (int)(vis.cmd_wait / n), (int)(vis.retire_wait / n),
                   (int)(vis.tri_starved / n), (int)(vis.tri_backpressure / n));
        gpu_vis_dma_counters_clear(&gpu);
        frames_drawn = frame_us = frame_us2 = front_us = cp_cycles = tile_cycles = 0;
        period_start = now;
        period_shown = shown;
    }
}

static void print_keys(void)
{
    xil_printf("keys: 1 CPU, 2 command processor; s turn the model or stop it; f front end every frame or "
               "once; r draw again; l SD card; o open a model; m menu; ? keys\r\n");
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

static bool is_gltf(const sd_entry_t *entry)
{
    const char *dot = std::strrchr(entry->name, '.');
    return !entry->directory && dot && (strcasecmp(dot, ".gltf") == 0 || strcasecmp(dot, ".glb") == 0);
}

static void list_entry(const sd_entry_t *entry, void *user)
{
    sd_listing &l = *static_cast<sd_listing *>(user);
    if (!is_gltf(entry))
        return;
    l.models++;
    if (l.wanted == 0)
        xil_printf("  %4d  %s  %u bytes\r\n", l.models, entry->name, (unsigned)entry->size);
    else if (l.models == l.wanted)
        std::snprintf(l.path, sizeof l.path, "0:/%s", entry->name);
}

// The SD card's glTF file at path ("0:/...") drawn from then on, from the front, by mode. The model
// so far stays if it does not load (false).
static bool load_model(const char *path)
{
    XTime start, read, parsed;
    XTime_GetTime(&start);
    void *data;
    size_t size;
    const int error = sd_read(path, &data, &size, GLTF_SCENE_PADDING);
    if (error != 0)
    {
        xil_printf("%s: %s\r\n", path, sd_error_name(error));
        return false;
    }
    XTime_GetTime(&read);
    char message[128];
    gltf_scene_t *loaded = gltf_scene_load(data, size, message, sizeof message);
    free(data);
    XTime_GetTime(&parsed);
    if (!loaded)
    {
        xil_printf("%s: %s\r\n", path, message);
        return false;
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
    return true;
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
    load_model(l.path);
}

// The frame buffer to draw the next screen into: the GPU's frame's place in it
static ui_canvas_t back_canvas(void)
{
    return {frame_in(dp_back()), (int)(frame_stride() / 4), WIDTH, HEIGHT};
}

// The test pattern on the screen instead of the model, nothing drawn until 1, 2, r or a model
static void show_test_pattern(void)
{
    drawing = false;
    pattern_shown = true;
    const ui_canvas_t c = back_canvas();
    test_pattern_draw(&c);
    dp_present();
}

static const char *output_name(void)
{
    return wide ? "1920 x 1080" : "1280 x 720";
}

static int menu_count(void)
{
    return menu_page == MENU_SETTINGS ? SETTINGS_ITEMS : ITEM_FIRST_MODEL + menu_models;
}

static void menu_describe(void)
{
    const char *about = nullptr;
    if (menu_page == MENU_SETTINGS)
        about = menu_selected == ITEM_BACK ? "Back to the menu"
                : wide                     ? "The DisplayPort output, the 1280 x 720 picture in its center"
                                           : "The DisplayPort output, the 1280 x 720 picture as it is";
    else if (menu_selected == ITEM_PATTERN)
        about = "Color bars and ramps: a check of the display";
    else if (menu_selected == ITEM_SETTINGS)
        about = "The DisplayPort output's resolution";
    if (about)
    {
        std::snprintf(menu_about, sizeof menu_about, "%s", about);
        return;
    }
    const int model = menu_selected - ITEM_FIRST_MODEL;
    std::snprintf(menu_about, sizeof menu_about, "Loads 0:/%.100s, %u KB", menu_names[model],
                  (unsigned)((menu_sizes[model] + 1023) >> 10));
}

// The menu as it is now, into c
static void menu_render(const ui_canvas_t *c)
{
    static char labels[ITEM_FIRST_MODEL + MENU_MODELS][64];
    const char *items[ITEM_FIRST_MODEL + MENU_MODELS];
    char now[96];
    if (menu_page == MENU_SETTINGS)
    {
        std::snprintf(labels[ITEM_OUTPUT], sizeof labels[0], "Display Output: [%s]", output_name());
        std::snprintf(labels[ITEM_BACK], sizeof labels[0], "Back");
        std::snprintf(now, sizeof now, "Output: %s at 60 Hz, the picture 1280 x 720", output_name());
    }
    else
    {
        std::snprintf(labels[ITEM_PATTERN], sizeof labels[0], "Test Pattern");
        std::snprintf(labels[ITEM_SETTINGS], sizeof labels[0], "Settings");
        for (int i = 0; i < menu_models; i++)
            std::snprintf(labels[ITEM_FIRST_MODEL + i], sizeof labels[0], "Load %.56s", menu_names[i]);
        if (pattern_shown)
            std::snprintf(now, sizeof now, "Shown: the test pattern");
        else if (scene)
            std::snprintf(now, sizeof now, "Shown: %.48s, drawn by the %s%s", scene_name, mode_name(),
                          drawing ? "" : " (stopped)");
        else
            std::snprintf(now, sizeof now, "Shown: nothing");
    }
    const int count = menu_count();
    for (int i = 0; i < count; i++)
        items[i] = labels[i];
    const bool settings = menu_page == MENU_SETTINGS;
    const menu_screen m = {settings ? "Settings" : "lviv_gl Setup Utility",
                           items,
                           count,
                           menu_selected,
                           menu_about,
                           now,
                           menu_logo.pixels ? &menu_logo : nullptr,
                           settings ? "\x18\x19: Select    \x1b\x1a: Change    Enter: Choose    Esc: Back" : nullptr};
    menu_draw(c, m);
}

// The menu on the screen as it is now
static void menu_show(void)
{
    const ui_canvas_t c = back_canvas();
    menu_render(&c);
    dp_present();
}

// The menu's page, item selected on it
static void menu_go(menu_page_t page, int item)
{
    menu_page = page;
    menu_selected = item;
    menu_describe();
    menu_show();
}

// The DP output at 1920 x 1080 (to_wide) or 1280 x 720: its buffers black, the menu in the first
static void set_output(bool to_wide)
{
    wide = to_wide;
    const int w = wide ? WIDE_W : WIDTH, h = wide ? WIDE_H : HEIGHT, stride = (int)(frame_stride() / 4);
    uint32_t *buffers[DP_FRAMES];
    for (int f = 0; f < DP_FRAMES; f++)
    {
        buffers[f] = output_buffer(f);
        const ui_canvas_t all = {buffers[f], stride, w, h};
        ui_fill(&all, 0, 0, w, h, ui_rgb(0, 0, 0));
    }
    menu_describe();
    const ui_canvas_t first = {frame_in(buffers[0]), stride, WIDTH, HEIGHT};
    menu_render(&first);
    if (dp_set_mode(w, h, buffers, frame_stride()) != 0)
        xil_printf("DisplayPort: no %d x %d mode\r\n", w, h);
}

static void menu_entry(const sd_entry_t *entry, void *user)
{
    (void)user;
    if (!is_gltf(entry) || menu_models == MENU_MODELS)
        return;
    std::snprintf(menu_names[menu_models], sizeof menu_names[0], "%s", entry->name);
    menu_sizes[menu_models++] = entry->size;
}

static void load_logo(void)
{
    menu_logo = menu_image(logo_png, sizeof logo_png);
    if (!menu_logo.pixels)
        xil_printf("logo: logo.png does not decode\r\n");
}

// The menu up at its main page, the SD card listed again
static void menu_open(void)
{
    menu_up = true;
    menu_page = MENU_MAIN;
    menu_models = 0;
    const int error = sd_scan("0:/", menu_entry, nullptr);
    if (menu_selected >= menu_count())
        menu_selected = ITEM_PATTERN;
    menu_describe();
    if (error != 0)
        std::snprintf(menu_about, sizeof menu_about, "SD card: %s", sd_error_name(error));
    else if (menu_models == 0)
        std::snprintf(menu_about, sizeof menu_about, "No glTF files on the SD card");
    menu_show();
}

// Back to what the menu covered
static void menu_close(void)
{
    menu_up = false;
    if (pattern_shown)
    {
        show_test_pattern();
    }
    else if (drawing)
    {
        restart_report(); // the time the menu was up, out of the frame rate
    }
    else
    {
        const ui_canvas_t c = back_canvas();
        ui_fill(&c, 0, 0, WIDTH, HEIGHT, ui_rgb(0, 0, 0));
        dp_present();
    }
}

// The selected item. On the main page: the test pattern, the settings, or the model loaded (the menu
// up still if it does not load). On the settings': the other output, or back.
static void menu_choose(void)
{
    if (menu_page == MENU_SETTINGS)
    {
        if (menu_selected == ITEM_OUTPUT)
            set_output(!wide);
        else
            menu_go(MENU_MAIN, ITEM_SETTINGS);
        return;
    }
    if (menu_selected == ITEM_PATTERN)
    {
        menu_up = false;
        show_test_pattern();
        xil_printf("test pattern\r\n");
        return;
    }
    if (menu_selected == ITEM_SETTINGS)
    {
        menu_go(MENU_SETTINGS, ITEM_OUTPUT);
        return;
    }
    const char *name = menu_names[menu_selected - ITEM_FIRST_MODEL];
    std::snprintf(menu_about, sizeof menu_about, "Loading %.100s...", name);
    menu_show();
    char path[300];
    std::snprintf(path, sizeof path, "0:/%s", name);
    if (load_model(path))
    {
        menu_up = false;
        return;
    }
    std::snprintf(menu_about, sizeof menu_about, "%.100s did not load: the UART says why", name);
    menu_show();
}

// A key within ms milliseconds, or -1
static int read_key_within(int ms)
{
    XTime start, now;
    XTime_GetTime(&start);
    do
    {
        const int key = read_key();
        if (key >= 0)
            return key;
        XTime_GetTime(&now);
    } while (now - start < (XTime)ms * COUNTS_PER_SECOND / 1000);
    return -1;
}

// A key while the menu is up: the arrows (ESC [ or ESC O, then A, B, C or D) or w, s, d and a. Up
// and down move, left and right change the output on its line, Enter chooses; Esc alone or m goes
// back: to the main page, or the menu down.
static void menu_key(int key)
{
    static bool after_cr; // a terminal's CR LF: one Enter
    const bool lf_after_cr = key == '\n' && after_cr;
    after_cr = key == '\r';
    if (key == 0x1b)
    {
        const int next = read_key_within(10);
        key = next == '[' || next == 'O' ? read_key_within(10) : 'm';
        key = key == 'A' ? 'w' : key == 'B' ? 's' : key == 'C' ? 'd' : key == 'D' ? 'a' : key;
    }
    switch (key)
    {
    case 'w':
        if (menu_selected == 0)
            return;
        menu_selected--;
        break;
    case 's':
        if (menu_selected == menu_count() - 1)
            return;
        menu_selected++;
        break;
    case 'a':
    case 'd':
        if (menu_page == MENU_SETTINGS && menu_selected == ITEM_OUTPUT)
            set_output(!wide);
        return;
    case '\r':
    case '\n':
        if (!lf_after_cr)
            menu_choose();
        return;
    case 'm':
        if (menu_page == MENU_SETTINGS)
            menu_go(MENU_MAIN, ITEM_SETTINGS);
        else
            menu_close();
        return;
    default:
        return;
    }
    menu_describe();
    menu_show();
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
#ifdef GPU_PL_DDR
    xil_printf("GPU memory: PL DDR, triangles and textures copied there by the GDMA (CPU at 0x%x%08x)\r\n",
               (unsigned)((uint64_t)GPU_PL_DDR >> 32), (unsigned)GPU_PL_DDR);
#else
    xil_printf("GPU memory: PS DDR\r\n");
#endif

    // Black (the frame buffers start zeroed) until the first frame is shown
    uint32_t *buffers[DP_FRAMES];
    for (int f = 0; f < DP_FRAMES; f++)
        buffers[f] = output_buffer(f);
    if (dp_init(&gic, buffers, STRIDE) != 0)
    {
        xil_printf("DisplayPort: setup failed\r\n");
        return 1;
    }
    xil_printf("DisplayPort: %d x %d at 60 Hz; plug in or pull a monitor\r\n", DP_WIDTH, DP_HEIGHT);
    print_keys();
    load_logo();
    menu_open();

    for (;;)
    {
        const int key = read_key();
        if (menu_up)
        {
            if (key >= 0)
                menu_key(key);
            continue; // alone on the screen: nothing drawn
        }
        switch (key)
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
        case 'm':
            menu_open();
            break;
        case '?':
            print_keys();
            break;
        default: // none, or not a key of ours
            break;
        }
        if (drawing && !menu_up)
            draw_frame();
    }
}
