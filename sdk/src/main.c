// GPU bring-up demo for bd/dummy_test: gpu_top with dummy_core, on the ZCU104's A53 (standalone).
//
//  1. Register check: write and read back registers through the crossbar.
//  2. Scene: random triangles, and a fake visibility stream from their bounding boxes (bit t of
//     a triangle's word is set when its box overlaps tile t), as a binner would produce.
//  3. Frame: 1280 x 720 in 10 x 6 tiles of 128 x 128, each streamed by the visibility DMA and the
//     DataMover into the core, then written back by the tile DMA.
//  4. Check: dummy_core paints each tile with A = 0xFF, R = 2 * x, G = 2 * y (x, y in the tile)
//     and B = the number of triangles the tile received, so every pixel is known in advance.
//
// Output goes to the PS UART.

#include <stdint.h>
#include <string.h>

#include "gpu.h"
#include "gpu_map.h"
#include "xil_printf.h"
#include "xtime_l.h"

#ifndef GPU_BASEADDR
#define GPU_BASEADDR 0xA0000000u  // gpu_0/s_axi_ctrl in bd/dummy_test
#endif

#define WIDTH 1280
#define HEIGHT 720
#define TILES_X (WIDTH / GPU_TILE_SIZE)
#define TILES_Y ((HEIGHT + GPU_TILE_SIZE - 1) / GPU_TILE_SIZE)
#define TILES (TILES_X * TILES_Y)
#define FRAME_ROWS (TILES_Y * GPU_TILE_SIZE)  // the tile DMA writes whole tiles
#define STRIDE (WIDTH * 4)
#define TRIANGLES 512

static gpu_triangle_t triangles[TRIANGLES] __attribute__((aligned(64)));
static uint64_t visibility[TRIANGLES] __attribute__((aligned(64)));
static uint32_t frame[FRAME_ROWS * WIDTH] __attribute__((aligned(4096)));
static uint32_t tile_triangles[TILES];

static uint32_t rng_state = 1;

static uint32_t rng(uint32_t range) {
  rng_state = rng_state * 1664525u + 1013904223u;
  return (rng_state >> 8) % range;
}

static int min3(int a, int b, int c) { return a < b ? (a < c ? a : c) : (b < c ? b : c); }
static int max3(int a, int b, int c) { return a > b ? (a > c ? a : c) : (b > c ? b : c); }

static int check_registers(const gpu_t *gpu) {
  int errors = 0;
  uint32_t value;

  gpu_set_tile(gpu, 3, 2);
  value = gpu_read(gpu, GPU_FRONTEND_OFFSET + APB_FRONT_END_FRONTEND_REG_TILE_X);
  if ((value & APB_FRONT_END_FRONTEND_REG_TILE_X_TILE_X_MASK) != 3) {
    xil_printf("  frontend TILE_X read 0x%x, expected 3\r\n", (int)value);
    errors++;
  }
  gpu_set_tile(gpu, 0, 0);

  gpu_write(gpu, GPU_LUT_BASE(5), 0x12345600u);
  value = gpu_read(gpu, GPU_LUT_BASE(5));
  if (value != 0x12345600u) {
    xil_printf("  texture LUT base 5 read 0x%x, expected 0x12345600\r\n", (int)value);
    errors++;
  }
  gpu_write(gpu, GPU_LUT_BASE(5), 0);

  if (gpu_wait_idle(gpu) != GPU_OK) {
    xil_printf("  core not idle after reset\r\n");
    errors++;
  }
  return errors;
}

static void build_scene(void) {
  memset(tile_triangles, 0, sizeof tile_triangles);
  for (int i = 0; i < TRIANGLES; i++) {
    gpu_triangle_t *t = &triangles[i];
    int cx = (int)rng(WIDTH), cy = (int)rng(HEIGHT), size = 8 + (int)rng(240);
    int x[3], y[3];
    memset(t, 0, sizeof *t);
    for (int v = 0; v < 3; v++) {
      x[v] = cx + (int)rng(size) - size / 2;
      y[v] = cy + (int)rng(size) - size / 2;
      t->v[v].x = (float)x[v];
      t->v[v].y = (float)y[v];
      t->v[v].z = 0.5f;
      t->v[v].w = 1.0f;
      t->v[v].color = 0xFF000000u | rng(0x1000000);
    }
    t->tex_id = GPU_TEX_ID_NONE;
    t->texture_function = 5;  // COLOR
    t->blend = (1u << GPU_SFACTOR_OP_SHIFT) | (0u << GPU_DFACTOR_OP_SHIFT);  // ONE, ZERO
    t->depth_func = 1;  // LESS

    // Bounding box against the tiles, clipped to the screen.
    int x0 = min3(x[0], x[1], x[2]), x1 = max3(x[0], x[1], x[2]);
    int y0 = min3(y[0], y[1], y[2]), y1 = max3(y[0], y[1], y[2]);
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > WIDTH - 1) x1 = WIDTH - 1;
    if (y1 > HEIGHT - 1) y1 = HEIGHT - 1;
    visibility[i] = 0;
    if (x0 > x1 || y0 > y1) continue;
    for (int ty = y0 / GPU_TILE_SIZE; ty <= y1 / GPU_TILE_SIZE; ty++) {
      for (int tx = x0 / GPU_TILE_SIZE; tx <= x1 / GPU_TILE_SIZE; tx++) {
        visibility[i] |= 1ull << (ty * TILES_X + tx);
        tile_triangles[ty * TILES_X + tx]++;
      }
    }
  }
}

static int check_frame(void) {
  int wrong = 0;
  for (int y = 0; y < FRAME_ROWS; y++) {
    for (int x = 0; x < WIDTH; x++) {
      uint32_t count = tile_triangles[(y / GPU_TILE_SIZE) * TILES_X + x / GPU_TILE_SIZE];
      uint32_t want = 0xFF000000u | (uint32_t)(2 * (x % GPU_TILE_SIZE)) << 16 |
                      (uint32_t)(2 * (y % GPU_TILE_SIZE)) << 8 | (count > 255 ? 255 : count);
      uint32_t got = frame[y * WIDTH + x];
      if (got != want) {
        if (wrong < 8)
          xil_printf("  pixel (%d, %d): 0x%08x, expected 0x%08x\r\n", x, y, (int)got, (int)want);
        wrong++;
      }
    }
  }
  return wrong;
}

int main(void) {
  gpu_t gpu;
  XTime start, end;
  uint32_t failed_tile = 0;
  int errors = 0;

  xil_printf("\r\nGPU demo: gpu_top with dummy_core at 0x%x\r\n", (int)GPU_BASEADDR);
  gpu_init(&gpu, GPU_BASEADDR);

  int register_errors = check_registers(&gpu);
  xil_printf("register check: %s\r\n", register_errors ? "FAIL" : "ok");
  errors += register_errors;

  build_scene();
  int visible = 0;
  for (int t = 0; t < TILES; t++) visible += (int)tile_triangles[t];
  xil_printf("scene: %d triangles, %d triangle-tile pairs over %d tiles\r\n", TRIANGLES, visible,
             TILES);

  memset(frame, 0, sizeof frame);
  gpu_frame_t f = {
      .triangles = triangles,
      .visibility = visibility,
      .triangle_count = TRIANGLES,
      .frame = frame,
      .stride = STRIDE,
      .tiles_x = TILES_X,
      .tiles_y = TILES_Y,
  };

  XTime_GetTime(&start);
  gpu_status_t status = gpu_frame(&gpu, &f, &failed_tile);
  XTime_GetTime(&end);
  if (status != GPU_OK) {
    xil_printf("frame: FAIL at tile %d: %s\r\n", (int)failed_tile, gpu_status_name(status));
    return 1;
  }
  xil_printf("frame: %d us\r\n", (int)((end - start) / (COUNTS_PER_SECOND / 1000000)));

  int wrong = check_frame();
  xil_printf("image: %d of %d pixels wrong\r\n", wrong, FRAME_ROWS * WIDTH);
  errors += wrong;

  xil_printf("%s\r\n", errors ? "FAIL" : "PASS");
  return errors ? 1 : 0;
}
