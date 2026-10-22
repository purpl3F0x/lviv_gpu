// Bare-metal driver for the GPU's control port (Zynq UltraScale+, standalone BSP).
//
// A frame is rendered one 128 x 128 tile at a time: point the frontend at the tile, let the
// visibility DMA stream the tile's triangles into the core, wait until the core is idle, then let
// the tile DMA write the tile's frame buffer to memory. Everything is polled; no interrupts.
#pragma once

#include <stdint.h>

#include "gpu_triangle.h"

typedef struct {
  uintptr_t base;  // the control port, 0xA000_0000 in bd/dummy_test
} gpu_t;

typedef enum {
  GPU_OK = 0,
  GPU_TIMEOUT = -1,
  GPU_VIS_DMA_ERROR = -2,   // AXI or DataMover error during a tile
  GPU_TILE_DMA_ERROR = -3,  // tile write-back got a bad write response
} gpu_status_t;

// What a frame is drawn from, and where it goes. Every buffer must be in memory the GPU's masters
// reach (PS DDR below 4 GiB) and flushed from the CPU's caches before use (gpu_frame does that).
typedef struct {
  const gpu_triangle_t *triangles;  // GPU_TRIANGLE_BYTES each, 32-byte aligned
  const uint64_t *visibility;       // per triangle, bit t set if it touches tile t; 16-byte aligned
  uint32_t triangle_count;
  uint32_t *frame;                  // ARGB, 4 KiB aligned
  uint32_t stride;                  // bytes per frame row, a multiple of 512
  uint32_t tiles_x, tiles_y;        // tile t is (t % tiles_x, t / tiles_x); at most 64 tiles
} gpu_frame_t;

void gpu_init(gpu_t *gpu, uintptr_t base);
uint32_t gpu_read(const gpu_t *gpu, uint32_t offset);
void gpu_write(const gpu_t *gpu, uint32_t offset, uint32_t value);

// Frontend, orchestrator, input FIFO and all four threads report idle, twice in a row.
gpu_status_t gpu_wait_idle(const gpu_t *gpu);

// One tile, each step on its own.
void gpu_set_tile(const gpu_t *gpu, uint32_t tile_x, uint32_t tile_y);
gpu_status_t gpu_stream_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile);
gpu_status_t gpu_write_back_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile);

// The whole frame. On failure *failed_tile says where it stopped.
gpu_status_t gpu_frame(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile);

const char *gpu_status_name(gpu_status_t status);
