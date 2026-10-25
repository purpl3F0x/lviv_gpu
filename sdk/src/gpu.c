#include "gpu.h"

#include "gpu_map.h"
#include "gpu_regs.h"
#include "sleep.h"
#include "xil_cache.h"
#include "xil_io.h"

// Register polls before a wait is declared hung (each is a round trip over the control port).
#define GPU_POLL_LIMIT 10000000u
// Spins on an interrupt count (in memory, so much faster than a poll) before an interrupt is
// declared lost: seconds.
#define GPU_SPIN_LIMIT 1000000000u

#define BIT(n) (1u << (n))

// The command processor's STATUS.CAUSE (ControlModules/CommandProcessor.scala)
enum
{
    CP_CAUSE_VIS_DMA = 1,
    CP_CAUSE_TILE_DMA = 2,
    CP_CAUSE_BUS = 3,
    CP_CAUSE_SIZE = 4,
};

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

void gpu_set_mode(gpu_t *gpu, gpu_mode_t mode)
{
    const int cp = mode == GPU_MODE_CP;
    gpu->mode = mode;
    cp_write_reg(gpu, CP_REG_MODE, cp);
    // With the command processor the per-tile done events are its own.
    vis_dma_write_reg(gpu, GPU_INT_MASK, cp ? GPU_INT_DONE | GPU_INT_FRAME_DONE : 0);
    tile_dma_write_reg(gpu, GPU_INT_MASK, cp ? GPU_INT_DONE : 0);
}

void gpu_cp_soft_reset(const gpu_t *gpu)
{
    cp_write_reg(gpu, CP_REG_CTRL, BIT(CP_REG_CTRL_SOFT_RESET_SHIFT));
}

uint32_t gpu_tiles_x(const gpu_frame_t *frame)
{
    return (frame->width + GPU_TILE_SIZE - 1) / GPU_TILE_SIZE;
}

uint32_t gpu_tiles_y(const gpu_frame_t *frame)
{
    return (frame->height + GPU_TILE_SIZE - 1) / GPU_TILE_SIZE;
}

static void handle_irq(gpu_t *gpu, gpu_irq_t irq)
{
    uint32_t pending = dma_read_reg(gpu, irq, GPU_INT_STATUS);
    if (!pending)
    {
        gpu->irq_spurious[irq]++;
        return;
    }
    dma_write_reg(gpu, irq, GPU_INT_RAW, pending); // write 1 to clear
    // Read back, so the line is low before the interrupt controller ends the interrupt.
    (void)dma_read_reg(gpu, irq, GPU_INT_RAW);
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
        uint32_t raw = dma_read_reg(gpu, irq, GPU_INT_RAW);
        if (raw & (GPU_INT_DONE | GPU_INT_ERROR))
        {
            dma_write_reg(gpu, irq, GPU_INT_RAW, raw); // write 1 to clear, which drops the line
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
    uint32_t status = frontend_read_reg(gpu, APB_FRONT_END_FRONTEND_REG_STATUS);
    if ((status & idle) != idle)
        return 0;
    for (int n = 0; n < GPU_THREADS; n++)
        if (thread_read_reg(gpu, n, THREAD_REG_STATUS) & THREAD_REG_STATUS_BUSY_MASK)
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
    lut_write_reg(gpu, GPU_LUT_BASE(id), (uint32_t)(offset / 4));
    lut_write_reg(gpu, GPU_LUT_SIZE(id), log2_size);
    return 0;
}

gpu_status_t gpu_clear_zbuffers(const gpu_t *gpu)
{
    for (int n = 0; n < GPU_THREADS; n++)
        thread_write_reg(gpu, n, THREAD_REG_ZBUF, THREAD_REG_ZBUF_ZBUF_CLEAR_MASK);
    // ZBUF_CLEAR reads 1 only once the clear has crossed into the thread clock and its busy back,
    // tens of nanoseconds; the clear itself takes a thread clock per entry (41 us at 100 MHz).
    usleep(1);
    for (int n = 0; n < GPU_THREADS; n++)
    {
        uint32_t polls = 0;
        while (thread_read_reg(gpu, n, THREAD_REG_ZBUF) & THREAD_REG_ZBUF_ZBUF_CLEAR_MASK)
            if (++polls == GPU_POLL_LIMIT)
                return GPU_TIMEOUT;
    }
    return GPU_OK;
}

// The last pixel of tile t's box: the tile's own, or the frame's when the tile runs past it.
static uint32_t box_end(uint32_t t, uint32_t size)
{
    const uint32_t end = (t + 1) * GPU_TILE_SIZE - 1;
    return end < size - 1 ? end : size - 1;
}

void gpu_set_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile_x, uint32_t tile_y)
{
    frontend_write_reg(gpu, APB_FRONT_END_FRONTEND_REG_BB_MIN_X, tile_x * GPU_TILE_SIZE);
    frontend_write_reg(gpu, APB_FRONT_END_FRONTEND_REG_BB_MIN_Y, tile_y * GPU_TILE_SIZE);
    frontend_write_reg(gpu, APB_FRONT_END_FRONTEND_REG_BB_MAX_X, box_end(tile_x, frame->width));
    frontend_write_reg(gpu, APB_FRONT_END_FRONTEND_REG_BB_MAX_Y, box_end(tile_y, frame->height));
}

gpu_status_t gpu_stream_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile)
{
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_VB_LOW, (uint32_t)(uintptr_t)frame->visibility);
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_VB_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->visibility >> 32));
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TRI_LOW, (uint32_t)(uintptr_t)frame->triangles);
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TRI_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->triangles >> 32));
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TRI_COUNT, frame->triangle_count);
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TILE_IDX, tile & AXI_VISIBILITY_DMA_REG_TILE_IDX_TILE_INDEX_MASK);
    vis_dma_write_reg(gpu, GPU_INT_RAW, GPU_INT_DONE); // one left behind, e.g. by the command processor
    const uint32_t irqs = gpu->irq_count[GPU_IRQ_VIS_DMA];
    // START alone: also clears IRQ_ENABLE and AUTO_ADV_EN, so the tile index is only the one written.
    // (IRQ_ENABLE only sets STATUS.IRQ_STATUS; the interrupt line comes from the INT_ registers.)
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_CTRL, BIT(AXI_VISIBILITY_DMA_REG_CTRL_START_SHIFT));

    uint32_t events;
    if (wait_dma(gpu, GPU_IRQ_VIS_DMA, irqs, &events) != GPU_OK)
        return GPU_TIMEOUT;
    uint32_t status = vis_dma_read_reg(gpu, AXI_VISIBILITY_DMA_REG_STATUS);
    // DONE, ERROR and FRAME_DONE are write-1-to-clear.
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_STATUS,
                      BIT(AXI_VISIBILITY_DMA_REG_STATUS_DONE_SHIFT) | BIT(AXI_VISIBILITY_DMA_REG_STATUS_ERROR_SHIFT) |
                          BIT(AXI_VISIBILITY_DMA_REG_STATUS_FRAME_DONE_SHIFT));
    const uint32_t errors = BIT(AXI_VISIBILITY_DMA_REG_STATUS_ERROR_SHIFT) |
                            AXI_VISIBILITY_DMA_REG_STATUS_AXI_ERR_FLAG_MASK |
                            AXI_VISIBILITY_DMA_REG_STATUS_DM_ERR_FLAG_MASK;
    return ((events & GPU_INT_ERROR) || (status & errors)) ? GPU_VIS_DMA_ERROR : GPU_OK;
}

gpu_status_t gpu_write_back_tile(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t tile)
{
    const uint32_t tile_x = tile % gpu_tiles_x(frame), tile_y = tile / gpu_tiles_x(frame);
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_BASE_LOW, (uint32_t)(uintptr_t)frame->frame);
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_BASE_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->frame >> 32));
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_STRIDE, frame->stride);
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_TILES_X, gpu_tiles_x(frame));
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_TILES_Y, gpu_tiles_y(frame));
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_CUR_POS,
                       (tile_y << AXI_TILE_DMA_REG_CUR_POS_CUR_TILE_Y_SHIFT) |
                           (tile_x << AXI_TILE_DMA_REG_CUR_POS_CUR_TILE_X_SHIFT));
    tile_dma_write_reg(gpu, GPU_INT_RAW, GPU_INT_DONE); // one left behind, e.g. by the command processor
    const uint32_t irqs = gpu->irq_count[GPU_IRQ_TILE_DMA];
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_CTRL, BIT(AXI_TILE_DMA_REG_CTRL_START_SHIFT));

    uint32_t events;
    if (wait_dma(gpu, GPU_IRQ_TILE_DMA, irqs, &events) != GPU_OK)
        return GPU_TIMEOUT;
    uint32_t status = tile_dma_read_reg(gpu, AXI_TILE_DMA_REG_STATUS);
    int error = (events & GPU_INT_ERROR) || (status & AXI_TILE_DMA_REG_STATUS_LAST_BRESP_MASK);
    return error ? GPU_TILE_DMA_ERROR : GPU_OK;
}

gpu_status_t gpu_clear_frame_buffers(const gpu_t *gpu, uint32_t color)
{
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_CLEAR_VALUE, color);
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_CTRL, BIT(AXI_TILE_DMA_REG_CTRL_CLEAR_SHIFT));
    for (uint32_t polls = 0; polls < GPU_POLL_LIMIT; polls++)
        if (!(tile_dma_read_reg(gpu, AXI_TILE_DMA_REG_STATUS) & AXI_TILE_DMA_REG_STATUS_CLEAR_BUSY_MASK))
            return GPU_OK;
    return GPU_TIMEOUT;
}

// GPU_MODE_CPU: tile by tile.
static gpu_status_t cpu_frame(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile)
{
    const uint32_t tiles_x = gpu_tiles_x(frame), tiles = tiles_x * gpu_tiles_y(frame);
    gpu_status_t cleared = gpu_clear_frame_buffers(gpu, frame->clear_color);
    if (cleared != GPU_OK)
        return cleared;

    for (uint32_t tile = 0; tile < tiles; tile++)
    {
        gpu_status_t status;
        *failed_tile = tile;
        if ((status = gpu_clear_zbuffers(gpu)) != GPU_OK)
            return status;
        gpu_set_tile(gpu, frame, tile % tiles_x, tile / tiles_x);
        if ((status = gpu_stream_tile(gpu, frame, tile)) != GPU_OK)
            return status;
        if ((status = gpu_wait_idle(gpu)) != GPU_OK)
            return status;
        if ((status = gpu_write_back_tile(gpu, frame, tile)) != GPU_OK)
            return status;
    }
    return GPU_OK;
}

// GPU_MODE_CP: the frame set up here, at tile 0 (the DMAs' events cleared, their frame registers
// and tile counts, the frame buffers and z-buffers cleared, tile 0's box, the frame size), the
// tiles in the command processor; then its end: the tile DMA's frame_done or an error
// (interrupts), or BUSY low.
static gpu_status_t cp_frame(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile)
{
    const uint32_t events = GPU_INT_DONE | GPU_INT_ERROR | GPU_INT_FRAME_DONE;
    vis_dma_write_reg(gpu, GPU_INT_RAW, events); // write 1 to clear: each comes as a new edge
    tile_dma_write_reg(gpu, GPU_INT_RAW, events);
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_VB_LOW, (uint32_t)(uintptr_t)frame->visibility);
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_VB_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->visibility >> 32));
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TRI_LOW, (uint32_t)(uintptr_t)frame->triangles);
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TRI_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->triangles >> 32));
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TRI_COUNT, frame->triangle_count);
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TILE_IDX, 0);
    // The command processor starts it with AUTO_ADV_EN: it moves on by itself, back to 0 after these.
    vis_dma_write_reg(gpu, AXI_VISIBILITY_DMA_REG_TILE_COUNT, gpu_tiles_x(frame) * gpu_tiles_y(frame));
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_BASE_LOW, (uint32_t)(uintptr_t)frame->frame);
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_BASE_HIGH, (uint32_t)((uint64_t)(uintptr_t)frame->frame >> 32));
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_STRIDE, frame->stride);
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_TILES_X, gpu_tiles_x(frame));
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_TILES_Y, gpu_tiles_y(frame));
    tile_dma_write_reg(gpu, AXI_TILE_DMA_REG_CTRL, BIT(AXI_TILE_DMA_REG_CTRL_RESET_POS_SHIFT)); // tile (0, 0)
    gpu_status_t cleared = gpu_clear_frame_buffers(gpu, frame->clear_color);
    if (cleared == GPU_OK)
        cleared = gpu_clear_zbuffers(gpu);
    if (cleared != GPU_OK)
        return cleared;
    gpu_set_tile(gpu, frame, 0, 0);
    cp_write_reg(gpu, CP_REG_SIZE, frame->height << CP_REG_SIZE_HEIGHT_SHIFT | frame->width);

    const uint32_t vis_irqs = gpu->irq_count[GPU_IRQ_VIS_DMA], tile_irqs = gpu->irq_count[GPU_IRQ_TILE_DMA];
    cp_write_reg(gpu, CP_REG_CTRL, BIT(CP_REG_CTRL_START_SHIFT));
    if (gpu->use_interrupts)
    {
        for (uint32_t spins = 0; spins < GPU_SPIN_LIMIT; spins++)
            if (gpu->irq_count[GPU_IRQ_TILE_DMA] != tile_irqs || gpu->irq_count[GPU_IRQ_VIS_DMA] != vis_irqs)
                break;
    }
    // BUSY low follows the events at once; polled, it is the end.
    uint32_t status = CP_REG_STATUS_BUSY_MASK;
    for (uint32_t polls = 0; polls < GPU_POLL_LIMIT && (status & CP_REG_STATUS_BUSY_MASK); polls++)
        status = cp_read_reg(gpu, CP_REG_STATUS);
    *failed_tile = (status & CP_REG_STATUS_TILE_MASK) >> CP_REG_STATUS_TILE_SHIFT;
    if (status & CP_REG_STATUS_BUSY_MASK)
    {
        gpu_cp_soft_reset(gpu);
        return GPU_TIMEOUT;
    }
    if (!gpu->use_interrupts)
        tile_dma_write_reg(gpu, GPU_INT_RAW, GPU_INT_FRAME_DONE); // the CPU's, as its handler would
    if (status & BIT(CP_REG_STATUS_DONE_SHIFT))
        return GPU_OK;
    switch ((status & CP_REG_STATUS_CAUSE_MASK) >> CP_REG_STATUS_CAUSE_SHIFT)
    {
    case CP_CAUSE_VIS_DMA:
        return GPU_VIS_DMA_ERROR;
    case CP_CAUSE_TILE_DMA:
        return GPU_TILE_DMA_ERROR;
    case CP_CAUSE_BUS:
        return GPU_BUS_ERROR;
    case CP_CAUSE_SIZE:
        return GPU_BAD_SIZE;
    }
    return GPU_TIMEOUT;
}

gpu_status_t gpu_frame(const gpu_t *gpu, const gpu_frame_t *frame, uint32_t *failed_tile)
{
    const uint32_t tiles_x = gpu_tiles_x(frame), tiles_y = gpu_tiles_y(frame);
    const uint32_t frame_bytes = frame->stride * tiles_y * GPU_TILE_SIZE;

    *failed_tile = 0;
    if (tiles_x == 0 || tiles_y == 0 || tiles_x * tiles_y > GPU_MAX_TILES)
        return GPU_BAD_SIZE;

    // The GPU reads the scene and writes the frame behind the CPU's caches.
    Xil_DCacheFlushRange((UINTPTR)frame->triangles, frame->triangle_count * GPU_TRIANGLE_BYTES);
    Xil_DCacheFlushRange((UINTPTR)frame->visibility, frame->triangle_count * sizeof(uint64_t));
    Xil_DCacheFlushRange((UINTPTR)frame->frame, frame_bytes);

    gpu_status_t status =
        gpu->mode == GPU_MODE_CP ? cp_frame(gpu, frame, failed_tile) : cpu_frame(gpu, frame, failed_tile);
    if (status == GPU_OK)
        Xil_DCacheInvalidateRange((UINTPTR)frame->frame, frame_bytes);
    return status;
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
    case GPU_BUS_ERROR:
        return "command processor bus error";
    case GPU_BAD_SIZE:
        return "bad frame size";
    }
    return "unknown";
}
