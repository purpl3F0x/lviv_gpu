// Bare-metal driver for the GPU's control port (Zynq UltraScale+, standalone BSP).
//
// A frame is rendered one 128 x 128 tile at a time: clear the z-buffers, point the frontend at the
// tile and its box, let the visibility DMA stream the tile's triangles into the core, wait until the
// core is idle, then let the tile DMA write the tile's frame buffer to memory. The tile DMA leaves
// the clear color behind in the frame buffer as it reads it, so only the first tile needs a clear
// (its CLEAR, at the start of the frame).
//
// Who runs the tiles (gpu_set_mode):
//   GPU_MODE_CPU  this driver, tile by tile. The DMAs are polled, or with use_interrupts their
//                 interrupts are waited for (gpu_vis_dma_isr and gpu_tile_dma_isr, connected by the
//                 application). The core's idle state is always polled.
//   GPU_MODE_CP   the command processor: the driver writes the DMAs' frame registers and the frame
//                 size, starts it, and waits for the tile DMA's frame_done (its interrupt, the only
//                 one besides errors in this mode) or polls the command processor's BUSY.
// The frame buffers' clear (and, by the command processor, the z-buffers') is set up once: a frame
// that finished leaves them clear for the next, in the same mode with the same clear color.
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

typedef enum
{
    GPU_MODE_CPU, // reset
    GPU_MODE_CP,
} gpu_mode_t;

typedef struct
{
    uintptr_t base;     // the control port (XPAR_GPU_TOP_BD_0_BASEADDR in xparameters.h)
    int use_interrupts; // wait for the DMAs' interrupts instead of polling them
    gpu_mode_t mode;    // gpu_set_mode
    // The last frame finished in this mode: the frame buffers hold ready_color (each write-back leaves
    // CLEAR_VALUE behind), and after a command processor frame the z-buffers are clear too.
    int ready;
    uint32_t ready_color;
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
    GPU_BUS_ERROR = -4,      // a command processor register access got an error response
    GPU_BAD_SIZE = -5,       // width or height 0, or more than 64 tiles
} gpu_status_t;

// What a frame is drawn from, and where it goes, in memory the GPU's masters reach (PS DDR below
// 4 GiB). They do not see the CPU's caches: gpu_frame flushes the triangles and their visibility
// words from them, and the frame must be memory the CPU does not cache (Xil_SetTlbAttributes
// NORM_NONCACHE on its 2 MiB blocks), or kept out of its caches by the caller.
typedef struct
{
    const gpu_triangle_t *triangles; // GPU_TRIANGLE_BYTES each, 32-byte aligned
    const uint64_t *visibility;      // per triangle, bit t set if it touches tile t; 16-byte aligned
    uint32_t triangle_count;
    uint32_t *frame;        // ARGB, 4 KiB aligned, rows to the end of the last row of tiles
    uint32_t stride;        // bytes per frame row, a multiple of 512
    uint32_t width, height; // pixels; at most 64 tiles, tile t (t % tiles across, t / tiles across)
    uint32_t clear_color;   // ARGB, where no triangle draws
} gpu_frame_t;

// Tiles across and down a frame.
uint32_t gpu_tiles_x(const gpu_frame_t *frame);
uint32_t gpu_tiles_y(const gpu_frame_t *frame);

void gpu_init(gpu_t *gpu, uintptr_t base);
uint32_t gpu_read(const gpu_t *gpu, uint32_t offset);
void gpu_write(const gpu_t *gpu, uint32_t offset, uint32_t value);

// The command processor's MODE, and the DMAs' interrupt masks for it: in GPU_MODE_CP only the tile
// DMA's frame_done and both DMAs' errors interrupt. Not while a frame is being rendered.
void gpu_set_mode(gpu_t *gpu, gpu_mode_t mode);

// The command processor back to its reset state (MODE kept), e.g. after a frame that never ended.
// The units are not reset.
void gpu_cp_soft_reset(const gpu_t *gpu);

// The command processor's clock cycles for its last frame (FRAME_CYCLES).
uint32_t gpu_cp_frame_cycles(const gpu_t *gpu);

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

// One tile, each step on its own (GPU_MODE_CPU).
gpu_status_t gpu_clear_zbuffers(const gpu_t *gpu); // every thread's back to 1.0, the far plane
// The frontend's tile box: from the tile's first pixel to its last, or the frame's when the tile
// runs past it.
void gpu_set_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile_x, uint32_t tile_y);
gpu_status_t gpu_stream_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile);
gpu_status_t gpu_write_back_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile);

// The whole frame, by the tiles' runner of gpu->mode. On failure *failed_tile says where it stopped.
gpu_status_t gpu_frame(gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile);

const char *gpu_status_name(gpu_status_t status);
