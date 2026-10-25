// The GPU driver's register accessors: one block's registers, by their offsets in its own map (the
// generated headers, gpu_map.h), over gpu_read and gpu_write.
#pragma once

#include "gpu.h"
#include "gpu_map.h"

static inline uint32_t vis_dma_read_reg(const gpu_t *gpu, uint32_t reg)
{
    return gpu_read(gpu, GPU_VIS_DMA_OFFSET + reg);
}

static inline void vis_dma_write_reg(const gpu_t *gpu, uint32_t reg, uint32_t value)
{
    gpu_write(gpu, GPU_VIS_DMA_OFFSET + reg, value);
}

static inline uint32_t tile_dma_read_reg(const gpu_t *gpu, uint32_t reg)
{
    return gpu_read(gpu, GPU_TILE_DMA_OFFSET + reg);
}

static inline void tile_dma_write_reg(const gpu_t *gpu, uint32_t reg, uint32_t value)
{
    gpu_write(gpu, GPU_TILE_DMA_OFFSET + reg, value);
}

// Either DMA, by its interrupt
static inline uint32_t dma_offset(gpu_irq_t irq)
{
    return irq == GPU_IRQ_VIS_DMA ? GPU_VIS_DMA_OFFSET : GPU_TILE_DMA_OFFSET;
}

static inline uint32_t dma_read_reg(const gpu_t *gpu, gpu_irq_t irq, uint32_t reg)
{
    return gpu_read(gpu, dma_offset(irq) + reg);
}

static inline void dma_write_reg(const gpu_t *gpu, gpu_irq_t irq, uint32_t reg, uint32_t value)
{
    gpu_write(gpu, dma_offset(irq) + reg, value);
}

static inline uint32_t cp_read_reg(const gpu_t *gpu, uint32_t reg)
{
    return gpu_read(gpu, GPU_CP_OFFSET + reg);
}

static inline void cp_write_reg(const gpu_t *gpu, uint32_t reg, uint32_t value)
{
    gpu_write(gpu, GPU_CP_OFFSET + reg, value);
}

static inline uint32_t frontend_read_reg(const gpu_t *gpu, uint32_t reg)
{
    return gpu_read(gpu, GPU_FRONTEND_OFFSET + reg);
}

static inline void frontend_write_reg(const gpu_t *gpu, uint32_t reg, uint32_t value)
{
    gpu_write(gpu, GPU_FRONTEND_OFFSET + reg, value);
}

static inline uint32_t thread_read_reg(const gpu_t *gpu, int thread, uint32_t reg)
{
    return gpu_read(gpu, GPU_THREAD_OFFSET(thread) + reg);
}

static inline void thread_write_reg(const gpu_t *gpu, int thread, uint32_t reg, uint32_t value)
{
    gpu_write(gpu, GPU_THREAD_OFFSET(thread) + reg, value);
}

// The texture table
static inline uint32_t lut_read_reg(const gpu_t *gpu, uint32_t reg)
{
    return gpu_read(gpu, GPU_LUT_OFFSET + reg);
}

static inline void lut_write_reg(const gpu_t *gpu, uint32_t reg, uint32_t value)
{
    gpu_write(gpu, GPU_LUT_OFFSET + reg, value);
}
