// Bare-metal driver for the GPU's control port (Zynq UltraScale+, standalone BSP).
//
// A frame is rendered one 128 x 128 tile at a time: clear the z-buffers, point the frontend at the
// tile, let the visibility DMA stream the tile's triangles into the core, wait until the core is
// idle, then let the tile DMA write the tile's frame buffer to memory. The tile DMA leaves the
// clear colour behind in the frame buffer as it reads it, so only the first tile needs a clear (its
// CLEAR, at the start of the frame). The DMAs are polled, or with use_interrupts their interrupts
// are waited for (gpu_vis_dma_isr and gpu_tile_dma_isr, connected by the application). The core's
// idle state is always polled.
#pragma once

#include <stdint.h>

#include "gpu_triangle.h"

// The DMAs' interrupts.
typedef enum
{
    GPU_IRQ_VIS_DMA,
    GPU_IRQ_TILE_DMA,
    GPU_IRQS
} gpu_irq_t;

typedef struct
{
    uintptr_t base;     // the control port (XPAR_GPU_TOP_BD_0_BASEADDR in xparameters.h)
    int use_interrupts; // wait for the DMAs' interrupts instead of polling them
    // Kept by the interrupt handlers, per gpu_irq_t:
    volatile uint32_t irq_count[GPU_IRQS];    // interrupts handled
    volatile uint32_t irq_events[GPU_IRQS];   // the last one's events (GPU_INT_DONE, GPU_INT_ERROR)
    volatile uint32_t irq_spurious[GPU_IRQS]; // taken with no event pending
} gpu_t;

typedef enum
{
    GPU_OK = 0,
    GPU_TIMEOUT = -1,
    GPU_VIS_DMA_ERROR = -2,  // AXI or DataMover error during a tile
    GPU_TILE_DMA_ERROR = -3, // tile write-back got a bad write response
} gpu_status_t;

// What a frame is drawn from, and where it goes. Every buffer must be in memory the GPU's masters
// reach (PS DDR below 4 GiB) and flushed from the CPU's caches before use (gpu_frame does that).
typedef struct
{
    const gpu_triangle_t *triangles; // GPU_TRIANGLE_BYTES each, 32-byte aligned
    const uint64_t *visibility;      // per triangle, bit t set if it touches tile t; 16-byte aligned
    uint32_t triangle_count;
    uint32_t *frame;           // ARGB, 4 KiB aligned
    uint32_t stride;           // bytes per frame row, a multiple of 512
    uint32_t tiles_x, tiles_y; // tile t is (t % tiles_x, t / tiles_x); at most 64 tiles
    uint32_t clear_color;      // ARGB, where no triangle draws
} gpu_frame_t;

void gpu_init(gpu_t *gpu, uintptr_t base);
uint32_t gpu_read(const gpu_t *gpu, uint32_t offset);
void gpu_write(const gpu_t *gpu, uint32_t offset, uint32_t value);

// Interrupt handlers, for the interrupt controller to call with the gpu_t (XScuGic_Connect): each
// takes its DMA's pending events, clears them, which drops the line, and counts the interrupt.
void gpu_vis_dma_isr(void *gpu);
void gpu_tile_dma_isr(void *gpu);

// Frontend, orchestrator, input FIFO and all four threads report idle, twice in a row.
gpu_status_t gpu_wait_idle(const gpu_t *gpu);

// The frame buffers filled with color (the tile DMA's CLEAR), and color left behind by every
// write-back from then on. The core must be idle.
gpu_status_t gpu_clear_frame_buffers(const gpu_t *gpu, uint32_t color);

// Texture id (a triangle's tex_id): 1 << log2_size texels square, ARGB, in Morton order (bit 2i of
// a texel's index is bit i of its x, bit 2i + 1 bit i of its y: gpu_texel_index), at a multiple of
// their own size in bytes, inside the texture window (gpu_map.h). Flushes them from the data
// cache. Returns 0, or -1 if the GPU cannot use them where they are.
int gpu_set_texture(const gpu_t *gpu, uint32_t id, const uint32_t *texels, uint32_t log2_size);
uint32_t gpu_texel_index(uint32_t x, uint32_t y);

// One tile, each step on its own.
gpu_status_t gpu_clear_zbuffers(const gpu_t *gpu); // every thread's back to 1.0, the far plane
void gpu_set_tile(const gpu_t *gpu, uint32_t tile_x, uint32_t tile_y);
gpu_status_t gpu_stream_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile);
gpu_status_t gpu_write_back_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile);

// The whole frame. On failure *failed_tile says where it stopped.
gpu_status_t gpu_frame(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile);

const char *gpu_status_name(gpu_status_t status);
