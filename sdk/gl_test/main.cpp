// Demo of lviv_gl (sdk/lviv_gl) on gpu_top's raster core on the ZCU104 (bd/gpu_test), on the A53
// (standalone), driven from the UART console: a model drawn with OpenGL 1.x calls.
//
// Keys:
//   1, 2  who draws it: 1 the CPU, tile by tile; 2 the command processor, in one START
//   s     the model turning, or still again
//   r     drawing again, after a frame that failed
//   ?     the keys
//
// Output goes to the PS UART.

#include <cmath>
#include <cstdint>

#include <glm/glm.hpp>

#include "board.h"
#include "bspconfig.h" // STDIN_BASEADDRESS
#include "dp.h"
#include "gpu.h"
#include "gpu_map.h"
#include "lviv_gl.h"
#include "models/suzanne.h"
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

// The camera (raster_sw's: the model's bounding box, looked at from 1.5 spans along +z), the
// model's turn (degrees) and whether it turns
static glm::vec3 center, eye;
static float angle;
static bool turning;

// Since the last report, from period_start: the frames drawn, the sum of their times (us) and of
// their squares, of the front end's times (us) and of the command processor's cycle counts.
static uint64_t frames_drawn, frame_us, frame_us2, front_us, cp_cycles;
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

// lviv_gl's state, once: the camera's projection, the light (in eye space: set with the identity
// modelview), the material, the depth test, back faces culled, the model's arrays.
static int setup_scene(void)
{
    glm::vec3 lo(1e9f), hi(-1e9f);
    for (int i = 0; i < SUZANNE_VERTICES; i++)
    {
        const glm::vec3 p(suzanne_positions[i][0], suzanne_positions[i][1], suzanne_positions[i][2]);
        lo = glm::min(lo, p);
        hi = glm::max(hi, p);
    }
    const glm::vec3 size = hi - lo;
    center = (lo + hi) * 0.5f;
    eye = center + glm::vec3(0.0f, 0.0f, glm::max(size.x, glm::max(size.y, size.z)) * 1.5f);

    if (lviv_gl_init(&gpu, WIDTH, HEIGHT, lviv_frame_start, lviv_frame_bytes()) != 0)
        return -1;
    glViewport(0, 0, WIDTH, HEIGHT);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity();
    gluPerspective(45.0, (double)WIDTH / HEIGHT, 0.1, 1000.0);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity();
    const GLfloat light_position[] = {1, 1, 1, 0}, light_ambient[] = {0.1f, 0.1f, 0.1f, 1}, white[] = {1, 1, 1, 1};
    const GLfloat material_ambient[] = {0.5f, 0.5f, 0.5f, 1};
    glLightfv(GL_LIGHT0, GL_POSITION, light_position);
    glLightfv(GL_LIGHT0, GL_AMBIENT, light_ambient);
    glLightfv(GL_LIGHT0, GL_DIFFUSE, white);
    glLightfv(GL_LIGHT0, GL_SPECULAR, white);
    glMaterialfv(GL_FRONT_AND_BACK, GL_AMBIENT, material_ambient);
    glMaterialfv(GL_FRONT_AND_BACK, GL_DIFFUSE, white);
    glMaterialfv(GL_FRONT_AND_BACK, GL_SPECULAR, white);
    glMaterialf(GL_FRONT_AND_BACK, GL_SHININESS, 32.0f);
    glEnable(GL_LIGHTING);
    glEnable(GL_LIGHT0);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LESS);
    glEnable(GL_CULL_FACE);
    glClearColor(0x63 / 255.0f, 0x63 / 255.0f, 0x63 / 255.0f, 1.0f); // raster_sw's
    glEnableClientState(GL_VERTEX_ARRAY);
    glEnableClientState(GL_NORMAL_ARRAY);
    glEnableClientState(GL_COLOR_ARRAY);
    glEnableClientState(GL_TEXTURE_COORD_ARRAY);
    glVertexPointer(3, GL_FLOAT, 0, suzanne_positions);
    glNormalPointer(GL_FLOAT, 0, suzanne_normals);
    glColorPointer(4, GL_UNSIGNED_BYTE, 0, suzanne_colors);
    glTexCoordPointer(2, GL_FLOAT, 0, suzanne_texcoords);
    return glGetError() == GL_NO_ERROR ? 0 : -1;
}

// A frame of the model, turned by angle about its vertical axis, for lviv_gl_frame
static void draw_scene(void)
{
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glLoadIdentity();
    gluLookAt(eye.x, eye.y, eye.z, center.x, center.y, center.z, 0, 1, 0);
    glTranslatef(center.x, center.y, center.z);
    glRotatef(angle, 0, 1, 0);
    glTranslatef(-center.x, -center.y, -center.z);
    glDrawArrays(GL_TRIANGLES, 0, SUZANNE_VERTICES);
    if (turning)
        angle = angle >= 359.0f ? 0.0f : angle + 1.0f;
}

// The frames from now on drawn by mode.
static void start_drawing(void)
{
    gpu_set_mode(&gpu, mode);
    drawing = true;
    frames_drawn = frame_us = frame_us2 = front_us = cp_cycles = 0;
    XTime_GetTime(&period_start);
    xil_printf("%s, suzanne\r\n", mode_name());
}

// One frame, drawn and shown, and once a second a report; drawing stops at one that fails.
static void draw_frame(void)
{
    XTime start, front, end;
    uint32_t failed_tile = 0;
    XTime_GetTime(&start);
    draw_scene();
    XTime_GetTime(&front);
    const gpu_status_t status = lviv_gl_frame(frames[back], STRIDE, &failed_tile);
    XTime_GetTime(&end);
    if (status != GPU_OK)
    {
        xil_printf("%s, suzanne: failed at tile %d: %s\r\n", mode_name(), (int)failed_tile, gpu_status_name(status));
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
    XTime now;
    XTime_GetTime(&now);
    if (now - period_start >= COUNTS_PER_SECOND)
    {
        const uint64_t n = frames_drawn;
        const int rate10 = (int)(n * 10 * COUNTS_PER_SECOND / (now - period_start));
        // n * (sum of squares) - sum^2 is n^2 times the variance, never negative.
        const double deviation = std::sqrt((double)(n * frame_us2 - frame_us * frame_us)) / (double)n;
        xil_printf("%s, suzanne: %d.%d frames/s, frame time %d \u00b1 %d us, front end %d us, %d triangles",
                   mode_name(), rate10 / 10, rate10 % 10, (int)(frame_us / n), (int)deviation, (int)(front_us / n),
                   (int)lviv_gl_triangles());
        if (mode == GPU_MODE_CP)
            xil_printf(" (CP cycle counter: %d)", (int)(cp_cycles / n));
        xil_printf("\r\n");
        frames_drawn = frame_us = frame_us2 = front_us = cp_cycles = 0;
        period_start = now;
    }
}

static void print_keys(void)
{
    xil_printf("keys: 1 CPU, 2 command processor; s turn the model or stop it; r draw again; ? keys\r\n");
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

    if (setup_scene() != 0)
    {
        xil_printf("lviv_gl: setup failed\r\n");
        return 1;
    }
    xil_printf("lviv_gl: frame memory at 0x%x, %d MiB: %d triangles a frame\r\n", (int)(uintptr_t)lviv_frame_start,
               (int)(lviv_frame_bytes() >> 20), (int)(lviv_frame_bytes() / LVIV_GL_TRIANGLE_BYTES));
    xil_printf("model: suzanne, %d triangles\r\n", SUZANNE_VERTICES / 3);

    // Black (the frame buffers start zeroed) until the first frame is shown
    if (dp_init(&gic, frames[back], STRIDE) != 0)
    {
        xil_printf("DisplayPort: setup failed\r\n");
        return 1;
    }
    back ^= 1;
    xil_printf("DisplayPort: %d x %d at 60 Hz; plug in or pull a monitor\r\n", DP_WIDTH, DP_HEIGHT);
    print_keys();
    start_drawing();

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
        case 'r':
            start_drawing();
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
