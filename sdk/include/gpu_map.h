// The GPU's control port: where each register block sits in its 4 KiB window (Axi4ToApbXbar,
// address_map.json), and the frontend registers.
//
// The frontend's generated apb_front_end_regmap.h does not compile (its five reserved registers
// share one name and one typedef), so its three registers are defined here, under the same names.
#pragma once

#define GPU_THREADS 4
#define GPU_TILE_SIZE 128

// Block offsets from the control port's base address
#define GPU_LUT_OFFSET 0x000  // texture table: 128 base words, then 128 size codes
#define GPU_LUT_BASE(id) (GPU_LUT_OFFSET + 0x000 + 4 * (id))
#define GPU_LUT_SIZE(id) (GPU_LUT_OFFSET + 0x200 + 4 * (id))
#define GPU_FRONTEND_OFFSET 0x800
#define GPU_THREAD_OFFSET(n) (0x820 + 0x20 * (n))
#define GPU_TILE_DMA_OFFSET 0xF00
#define GPU_VIS_DMA_OFFSET 0xF80

// Frontend (apb_front_end_regmap.h)
#define APB_FRONT_END_FRONTEND_REG_STATUS 0x0000
#define APB_FRONT_END_FRONTEND_REG_STATUS_EMPTY_MASK 0x00000001
#define APB_FRONT_END_FRONTEND_REG_STATUS_ORCHESTRATOR_EMPTY_MASK 0x00000002
#define APB_FRONT_END_FRONTEND_REG_STATUS_INPUT_FIFO_IDLE_MASK 0x00000004
#define APB_FRONT_END_FRONTEND_REG_STATUS_RESET_SHIFT 31  // W1P: soft reset pulse
#define APB_FRONT_END_FRONTEND_REG_TILE_X 0x0004
#define APB_FRONT_END_FRONTEND_REG_TILE_X_TILE_X_MASK 0x0000001f
#define APB_FRONT_END_FRONTEND_REG_TILE_Y 0x0008
#define APB_FRONT_END_FRONTEND_REG_TILE_Y_TILE_Y_MASK 0x0000001f
