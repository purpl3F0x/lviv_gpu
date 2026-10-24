#include "gpu.h"

#include "gpu_map.h"
#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"

// Register polls before a wait is declared hung (each is a round trip over the control port).
#define GPU_POLL_LIMIT 10000000u
// Spins on an interrupt count (in memory, so much faster than a poll) before an interrupt is
// declared lost: seconds.
#define GPU_SPIN_LIMIT 1000000000u

#define BIT(n) (1u << (n))

// Each DMA's register block, by gpu_irq_t.
static const uint32_t irq_block[GPU_IRQS] = {GPU_VIS_DMA_OFFSET, GPU_TILE_DMA_OFFSET};

void gpu_init(gpu_t *gpu, uintptr_t base)
{
    *gpu = (gpu_t){.base = base};
}

uint32_t gpu_read(const gpu_t *gpu, uint32_t offset)
{
    return Xil_In32(gpu->base + offset);
}

void gpu_write(const gpu_t *gpu, uint32_t offset, uint32_t value)
{
    Xil_Out32(gpu->base + offset, value);
}

static void handle_irq(gpu_t *gpu, gpu_irq_t irq)
{
    const uint32_t block = irq_block[irq];
    uint32_t pending = gpu_read(gpu, block + GPU_INT_STATUS);
    if (!pending)
    {
        gpu->irq_spurious[irq]++;
        return;
    }
    gpu_write(gpu, block + GPU_INT_RAW, pending); // write 1 to clear
    // Read back, so the line is low before the interrupt controller ends the interrupt.
    (void)gpu_read(gpu, block + GPU_INT_RAW);
    gpu->irq_events[irq] = pending;
    gpu->irq_count[irq]++;
}

void gpu_vis_dma_isr(void *gpu)
{
    handle_irq(gpu, GPU_IRQ_VIS_DMA);
}

void gpu_tile_dma_isr(void *gpu)
{
    handle_irq(gpu, GPU_IRQ_TILE_DMA);
}

// Until the DMA started after irqs interrupts has an event (done or error), which *events returns:
// its interrupt in interrupt mode, else INT_RAW polled and cleared, as the handler would.
static gpu_status_t wait_dma(const gpu_t *gpu, gpu_irq_t irq, uint32_t irqs, uint32_t *events)
{
    const uint32_t block = irq_block[irq];
    if (gpu->use_interrupts)
    {
        for (uint32_t spins = 0; spins < GPU_SPIN_LIMIT; spins++)
        {
            if (gpu->irq_count[irq] != irqs)
            {
                *events = gpu->irq_events[irq];
                return GPU_OK;
            }
        }
        return GPU_TIMEOUT;
    }
    for (uint32_t polls = 0; polls < GPU_POLL_LIMIT; polls++)
    {
        uint32_t raw = gpu_read(gpu, block + GPU_INT_RAW);
        if (raw & (GPU_INT_DONE | GPU_INT_ERROR))
        {
            gpu_write(gpu, block + GPU_INT_RAW, raw); // write 1 to clear, which drops the line
            *events = raw;
            return GPU_OK;
        }
    }
    return GPU_TIMEOUT;
}

static int core_idle(const gpu_t *gpu)
{
    const uint32_t idle = APB_FRONT_END_FRONTEND_REG_STATUS_EMPTY_MASK |
                          APB_FRONT_END_FRONTEND_REG_STATUS_ORCHESTRATOR_EMPTY_MASK |
                          APB_FRONT_END_FRONTEND_REG_STATUS_INPUT_FIFO_IDLE_MASK;
    uint32_t status = gpu_read(gpu, GPU_FRONTEND_OFFSET + APB_FRONT_END_FRONTEND_REG_STATUS);
    if ((status & idle) != idle)
        return 0;
    for (int n = 0; n < GPU_THREADS; n++)
        if (gpu_read(gpu, GPU_THREAD_OFFSET(n) + THREAD_REG_STATUS) & THREAD_REG_STATUS_BUSY_MASK)
            return 0;
    return 1;
}

gpu_status_t gpu_wait_idle(const gpu_t *gpu)
{
    // Twice in a row: a triangle still crossing a clock domain can hide for a few cycles.
    int streak = 0;
    for (uint32_t polls = 0; polls < GPU_POLL_LIMIT; polls++)
    {
        streak = core_idle(gpu) ? streak + 1 : 0;
        if (streak == 2)
            return GPU_OK;
    }
    return GPU_TIMEOUT;
}

uint32_t gpu_texel_index(uint32_t x, uint32_t y)
{
    uint32_t index = 0;
    for (int bit = 0; bit < GPU_TEXTURE_MAX_LOG2; bit++)
        index |= (x >> bit & 1u) << (2 * bit) | (y >> bit & 1u) << (2 * bit + 1);
    return index;
}

int gpu_set_texture(const gpu_t *gpu, uint32_t id, const uint32_t *texels, uint32_t log2_size)
{
    // Below the window, the offset wraps around to beyond it.
    const uint64_t offset = (uint64_t)(uintptr_t)texels - GPU_TEXTURE_WINDOW;
    const uint64_t bytes = 4ull << (2 * log2_size);
    if (id >= GPU_TEXTURES || log2_size > GPU_TEXTURE_MAX_LOG2 || offset % bytes != 0 ||
        offset + bytes > GPU_TEXTURE_WINDOW_BYTES)
        return -1;
    // The texture caches read it behind the CPU's caches.
    Xil_DCacheFlushRange((UINTPTR)texels, (INTPTR)bytes);
    gpu_write(gpu, GPU_LUT_BASE(id), (uint32_t)(offset / 4));
    gpu_write(gpu, GPU_LUT_SIZE(id), log2_size);
    return 0;
}

gpu_status_t gpu_clear_zbuffers(const gpu_t *gpu)
{
    for (int n = 0; n < GPU_THREADS; n++)
        gpu_write(gpu, GPU_THREAD_OFFSET(n) + THREAD_REG_ZBUF, THREAD_REG_ZBUF_ZBUF_CLEAR_MASK);
    // ZBUF_CLEAR reads 1 only once the clear has crossed into the thread clock and its busy back,
    // tens of nanoseconds; the clear itself takes a thread clock per entry (41 us at 100 MHz).
    usleep(1);
    for (int n = 0; n < GPU_THREADS; n++)
    {
        uint32_t polls = 0;
        while (gpu_read(gpu, GPU_THREAD_OFFSET(n) + THREAD_REG_ZBUF) & THREAD_REG_ZBUF_ZBUF_CLEAR_MASK)
            if (++polls == GPU_POLL_LIMIT)
                return GPU_TIMEOUT;
    }
    return GPU_OK;
}

void gpu_set_tile(const gpu_t *gpu, uint32_t tile_x, uint32_t tile_y)
{
    gpu_write(gpu, GPU_FRONTEND_OFFSET + APB_FRONT_END_FRONTEND_REG_TILE_X,
              tile_x & APB_FRONT_END_FRONTEND_REG_TILE_X_TILE_X_MASK);
    gpu_write(gpu, GPU_FRONTEND_OFFSET + APB_FRONT_END_FRONTEND_REG_TILE_Y,
              tile_y & APB_FRONT_END_FRONTEND_REG_TILE_Y_TILE_Y_MASK);
}

gpu_status_t gpu_stream_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile)
{
    const uint32_t vis = GPU_VIS_DMA_OFFSET;
    gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_VB_LOW, (uint32_t)(uintptr_t)frame->visibility);
    gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_VB_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->visibility >> 32));
    gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_TRI_LOW, (uint32_t)(uintptr_t)frame->triangles);
    gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_TRI_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->triangles >> 32));
    gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_TRI_COUNT, frame->triangle_count);
    gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_TILE_IDX, tile & AXI_VISIBILITY_DMA_REG_TILE_IDX_TILE_INDEX_MASK);
    const uint32_t irqs = gpu->irq_count[GPU_IRQ_VIS_DMA];
    // START alone: also clears IRQ_ENABLE and AUTO_ADV_EN, so the tile index is only the one written.
    // (IRQ_ENABLE only sets STATUS.IRQ_STATUS; the interrupt line comes from the INT_ registers.)
    gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_CTRL, BIT(AXI_VISIBILITY_DMA_REG_CTRL_START_SHIFT));

    uint32_t events;
    if (wait_dma(gpu, GPU_IRQ_VIS_DMA, irqs, &events) != GPU_OK)
        return GPU_TIMEOUT;
    uint32_t status = gpu_read(gpu, vis + AXI_VISIBILITY_DMA_REG_STATUS);
    // DONE, ERROR and FRAME_DONE are write-1-to-clear.
    gpu_write(gpu, vis + AXI_VISIBILITY_DMA_REG_STATUS,
              BIT(AXI_VISIBILITY_DMA_REG_STATUS_DONE_SHIFT) | BIT(AXI_VISIBILITY_DMA_REG_STATUS_ERROR_SHIFT) |
                  BIT(AXI_VISIBILITY_DMA_REG_STATUS_FRAME_DONE_SHIFT));
    const uint32_t errors = BIT(AXI_VISIBILITY_DMA_REG_STATUS_ERROR_SHIFT) |
                            AXI_VISIBILITY_DMA_REG_STATUS_AXI_ERR_FLAG_MASK |
                            AXI_VISIBILITY_DMA_REG_STATUS_DM_ERR_FLAG_MASK;
    return ((events & GPU_INT_ERROR) || (status & errors)) ? GPU_VIS_DMA_ERROR : GPU_OK;
}

gpu_status_t gpu_write_back_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile)
{
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
    const uint32_t irqs = gpu->irq_count[GPU_IRQ_TILE_DMA];
    gpu_write(gpu, dma + AXI_TILE_DMA_REG_CTRL, BIT(AXI_TILE_DMA_REG_CTRL_START_SHIFT));

    uint32_t events;
    if (wait_dma(gpu, GPU_IRQ_TILE_DMA, irqs, &events) != GPU_OK)
        return GPU_TIMEOUT;
    uint32_t status = gpu_read(gpu, dma + AXI_TILE_DMA_REG_STATUS);
    int error = (events & GPU_INT_ERROR) || (status & AXI_TILE_DMA_REG_STATUS_LAST_BRESP_MASK);
    return error ? GPU_TILE_DMA_ERROR : GPU_OK;
}

gpu_status_t gpu_clear_frame_buffers(const gpu_t *gpu, uint32_t color)
{
    const uint32_t dma = GPU_TILE_DMA_OFFSET;
    gpu_write(gpu, dma + AXI_TILE_DMA_REG_CLEAR_VALUE, color);
    gpu_write(gpu, dma + AXI_TILE_DMA_REG_CTRL, BIT(AXI_TILE_DMA_REG_CTRL_CLEAR_SHIFT));
    for (uint32_t polls = 0; polls < GPU_POLL_LIMIT; polls++)
        if (!(gpu_read(gpu, dma + AXI_TILE_DMA_REG_STATUS) & AXI_TILE_DMA_REG_STATUS_CLEAR_BUSY_MASK))
            return GPU_OK;
    return GPU_TIMEOUT;
}

gpu_status_t gpu_frame(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile)
{
    const uint32_t tiles = frame->tiles_x * frame->tiles_y;
    const uint32_t frame_bytes = frame->stride * frame->tiles_y * GPU_TILE_SIZE;

    // The GPU reads the scene and writes the frame behind the CPU's caches.
    Xil_DCacheFlushRange((UINTPTR)frame->triangles, frame->triangle_count * GPU_TRIANGLE_BYTES);
    Xil_DCacheFlushRange((UINTPTR)frame->visibility, frame->triangle_count * sizeof(uint64_t));
    Xil_DCacheFlushRange((UINTPTR)frame->frame, frame_bytes);

    *failed_tile = 0;
    gpu_status_t cleared = gpu_clear_frame_buffers(gpu, frame->clear_color);
    if (cleared != GPU_OK)
        return cleared;

    for (uint32_t tile = 0; tile < tiles; tile++)
    {
        gpu_status_t status;
        *failed_tile = tile;
        if ((status = gpu_clear_zbuffers(gpu)) != GPU_OK)
            return status;
        gpu_set_tile(gpu, tile % frame->tiles_x, tile / frame->tiles_x);
        if ((status = gpu_stream_tile(gpu, frame, tile)) != GPU_OK)
            return status;
        if ((status = gpu_wait_idle(gpu)) != GPU_OK)
            return status;
        if ((status = gpu_write_back_tile(gpu, frame, tile)) != GPU_OK)
            return status;
    }

    Xil_DCacheInvalidateRange((UINTPTR)frame->frame, frame_bytes);
    return GPU_OK;
}

const char *gpu_status_name(gpu_status_t status)
{
    switch (status)
    {
    case GPU_OK:
        return "ok";
    case GPU_TIMEOUT:
        return "timeout";
    case GPU_VIS_DMA_ERROR:
        return "visibility DMA error";
    case GPU_TILE_DMA_ERROR:
        return "tile DMA error";
    }
    return "unknown";
}
