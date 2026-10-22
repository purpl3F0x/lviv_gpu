#include "gpu.h"

#include "xil_cache.h"
#include "xil_io.h"
#include "xil_types.h"

// The generated headers use the BSP's u32.
#include "apb_thread_regmap.h"
#include "axi_tile_dma_regmap.h"
#include "axi_visibility_dma_regmap.h"
#include "gpu_map.h"

// Register polls before a wait is declared hung (each is a round trip over the control port).
#define GPU_POLL_LIMIT 10000000u

#define BIT(n) (1u << (n))

void gpu_init(gpu_t *gpu, uintptr_t base) { gpu->base = base; }

uint32_t gpu_read(const gpu_t *gpu, uint32_t offset) { return Xil_In32(gpu->base + offset); }

void gpu_write(const gpu_t *gpu, uint32_t offset, uint32_t value) {
  Xil_Out32(gpu->base + offset, value);
}

static int core_idle(const gpu_t *gpu) {
  const uint32_t idle = APB_FRONT_END_FRONTEND_REG_STATUS_EMPTY_MASK |
                        APB_FRONT_END_FRONTEND_REG_STATUS_ORCHESTRATOR_EMPTY_MASK |
                        APB_FRONT_END_FRONTEND_REG_STATUS_INPUT_FIFO_IDLE_MASK;
  uint32_t status = gpu_read(gpu, GPU_FRONTEND_OFFSET + APB_FRONT_END_FRONTEND_REG_STATUS);
  if ((status & idle) != idle) return 0;
  for (int n = 0; n < GPU_THREADS; n++)
    if (gpu_read(gpu, GPU_THREAD_OFFSET(n) + THREAD_REG_STATUS) & THREAD_REG_STATUS_BUSY_MASK)
      return 0;
  return 1;
}

gpu_status_t gpu_wait_idle(const gpu_t *gpu) {
  // Twice in a row: a triangle still crossing a clock domain can hide for a few cycles.
  int streak = 0;
  for (uint32_t polls = 0; polls < GPU_POLL_LIMIT; polls++) {
    streak = core_idle(gpu) ? streak + 1 : 0;
    if (streak == 2) return GPU_OK;
  }
  return GPU_TIMEOUT;
}

void gpu_set_tile(const gpu_t *gpu, uint32_t tile_x, uint32_t tile_y) {
  gpu_write(gpu, GPU_FRONTEND_OFFSET + APB_FRONT_END_FRONTEND_REG_TILE_X,
            tile_x & APB_FRONT_END_FRONTEND_REG_TILE_X_TILE_X_MASK);
  gpu_write(gpu, GPU_FRONTEND_OFFSET + APB_FRONT_END_FRONTEND_REG_TILE_Y,
            tile_y & APB_FRONT_END_FRONTEND_REG_TILE_Y_TILE_Y_MASK);
}

gpu_status_t gpu_stream_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile) {
  const uint32_t vis = GPU_VIS_DMA_OFFSET;
  gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_VB_LOW, (uint32_t)(uintptr_t)frame->visibility);
  gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_VB_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->visibility >> 32));
  gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_TRI_LOW, (uint32_t)(uintptr_t)frame->triangles);
  gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_TRI_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->triangles >> 32));
  gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_TRI_COUNT, frame->triangle_count);
  gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_TILE_IDX, tile & AXI_VISIBILITY_DMA_REG_TILE_IDX_TILE_INDEX_MASK);
  // START alone: also clears IRQ_ENABLE and AUTO_ADV_EN, so the tile index is only the one written.
  gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_CTRL, BIT(AXI_VISIBILITY_DMA_REG_CTRL_START_SHIFT));

  for (uint32_t polls = 0; polls < GPU_POLL_LIMIT; polls++) {
    uint32_t status = gpu_read(gpu, vis + AXI_VISIBILITY_DMA_REG_STATUS);
    if (status & BIT(AXI_VISIBILITY_DMA_REG_STATUS_DONE_SHIFT)) {
      // DONE, ERROR and FRAME_DONE are write-1-to-clear.
      gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_STATUS,
                BIT(AXI_VISIBILITY_DMA_REG_STATUS_DONE_SHIFT) |
                    BIT(AXI_VISIBILITY_DMA_REG_STATUS_ERROR_SHIFT) |
                    BIT(AXI_VISIBILITY_DMA_REG_STATUS_FRAME_DONE_SHIFT));
      const uint32_t errors = BIT(AXI_VISIBILITY_DMA_REG_STATUS_ERROR_SHIFT) |
                              AXI_VISIBILITY_DMA_REG_STATUS_AXI_ERR_FLAG_MASK |
                              AXI_VISIBILITY_DMA_REG_STATUS_DM_ERR_FLAG_MASK;
      return (status & errors) ? GPU_VIS_DMA_ERROR : GPU_OK;
    }
  }
  return GPU_TIMEOUT;
}

gpu_status_t gpu_write_back_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile) {
  const uint32_t dma = GPU_TILE_DMA_OFFSET;
  const uint32_t tile_x = tile % frame->tiles_x, tile_y = tile / frame->tiles_x;
  gpu_write(gpu, dma + AXI_TILE_DMA_REG_BASE_LOW, (uint32_t)(uintptr_t)frame->frame);
  gpu_write(gpu, dma + AXI_TILE_DMA_REG_BASE_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->frame >> 32));
  gpu_write(gpu, dma + AXI_TILE_DMA_REG_STRIDE, frame->stride);
  gpu_write(gpu, dma + AXI_TILE_DMA_REG_TILES_X, frame->tiles_x);
  gpu_write(gpu, dma + AXI_TILE_DMA_REG_TILES_Y, frame->tiles_y);
  gpu_write(gpu, dma + AXI_TILE_DMA_REG_CUR_POS,
            (tile_y << AXI_TILE_DMA_REG_CUR_POS_CUR_TILE_Y_SHIFT) |
                (tile_x << AXI_TILE_DMA_REG_CUR_POS_CUR_TILE_X_SHIFT));
  gpu_write(gpu, dma + AXI_TILE_DMA_REG_CTRL, BIT(AXI_TILE_DMA_REG_CTRL_START_SHIFT));

  for (uint32_t polls = 0; polls < GPU_POLL_LIMIT; polls++) {
    uint32_t raw = gpu_read(gpu, dma + AXI_TILE_DMA_INTR_INT_RAW);
    if (raw & (BIT(AXI_TILE_DMA_INTR_INT_RAW_DONE_RAW_SHIFT) |
               BIT(AXI_TILE_DMA_INTR_INT_RAW_ERROR_RAW_SHIFT))) {
      gpu_write(gpu, dma + AXI_TILE_DMA_INTR_INT_RAW, raw);  // write 1 to clear
      uint32_t status = gpu_read(gpu, dma + AXI_TILE_DMA_REG_STATUS);
      int error = (raw & BIT(AXI_TILE_DMA_INTR_INT_RAW_ERROR_RAW_SHIFT)) ||
                  (status & AXI_TILE_DMA_REG_STATUS_LAST_BRESP_MASK);
      return error ? GPU_TILE_DMA_ERROR : GPU_OK;
    }
  }
  return GPU_TIMEOUT;
}

gpu_status_t gpu_frame(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile) {
  const uint32_t tiles = frame->tiles_x * frame->tiles_y;
  const uint32_t frame_bytes = frame->stride * frame->tiles_y * GPU_TILE_SIZE;

  // The GPU reads the scene and writes the frame behind the CPU's caches.
  Xil_DCacheFlushRange((UINTPTR)frame->triangles, frame->triangle_count * GPU_TRIANGLE_BYTES);
  Xil_DCacheFlushRange((UINTPTR)frame->visibility, frame->triangle_count * sizeof(uint64_t));
  Xil_DCacheFlushRange((UINTPTR)frame->frame, frame_bytes);

  for (uint32_t tile = 0; tile < tiles; tile++) {
    gpu_status_t status;
    *failed_tile = tile;
    gpu_set_tile(gpu, tile % frame->tiles_x, tile / frame->tiles_x);
    if ((status = gpu_stream_tile(gpu, frame, tile)) != GPU_OK) return status;
    if ((status = gpu_wait_idle(gpu)) != GPU_OK) return status;
    if ((status = gpu_write_back_tile(gpu, frame, tile)) != GPU_OK) return status;
  }

  Xil_DCacheInvalidateRange((UINTPTR)frame->frame, frame_bytes);
  return GPU_OK;
}

const char *gpu_status_name(gpu_status_t status) {
  switch (status) {
    case GPU_OK: return "ok";
    case GPU_TIMEOUT: return "timeout";
    case GPU_VIS_DMA_ERROR: return "visibility DMA error";
    case GPU_TILE_DMA_ERROR: return "tile DMA error";
  }
  return "unknown";
}
