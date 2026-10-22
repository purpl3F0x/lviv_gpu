/*
 * 
 * Reg Interface C-Header [AUTOGENERATE by SpinalHDL]
 */

#ifndef __AXI_TILE_DMA_REGMAP_REGIF_H__
#define __AXI_TILE_DMA_REGMAP_REGIF_H__

#define AXI_TILE_DMA_REG_CTRL                                 0x0000
#define AXI_TILE_DMA_REG_CTRL_START_SHIFT                                0 /* START, W1P, 1 bit */
#define AXI_TILE_DMA_REG_CTRL_RESET_POS_SHIFT                            1 /* RESET_POS, W1P, 1 bit */
#define AXI_TILE_DMA_REG_CTRL_SOFT_RESET_SHIFT                           2 /* SOFT_RESET, W1P, 1 bit */
#define AXI_TILE_DMA_REG_STATUS                               0x0004
#define AXI_TILE_DMA_REG_STATUS_BUSY_SHIFT                               0
#define AXI_TILE_DMA_REG_STATUS_BUSY_MASK                                0x00000001 /* BUSY, RO, 1 bit */
#define AXI_TILE_DMA_REG_STATUS_LAST_BRESP_SHIFT                         1
#define AXI_TILE_DMA_REG_STATUS_LAST_BRESP_MASK                          0x00000006 /* LAST_BRESP, RO, 2 bit */
#define AXI_TILE_DMA_REG_STATUS_SOFT_RESET_PENDING_SHIFT                 3
#define AXI_TILE_DMA_REG_STATUS_SOFT_RESET_PENDING_MASK                  0x00000008 /* SOFT_RESET_PENDING, RO, 1 bit */
#define AXI_TILE_DMA_REG_BASE_LOW                             0x0008
#define AXI_TILE_DMA_REG_BASE_HIGH                            0x000c
#define AXI_TILE_DMA_REG_STRIDE                               0x0010
#define AXI_TILE_DMA_REG_TILES_X                              0x0014
#define AXI_TILE_DMA_REG_TILES_X_TILES_X_SHIFT                           0
#define AXI_TILE_DMA_REG_TILES_X_TILES_X_MASK                            0x0000ffff /* TILES_X, RW, 16 bit */
#define AXI_TILE_DMA_REG_TILES_Y                              0x0018
#define AXI_TILE_DMA_REG_TILES_Y_TILES_Y_SHIFT                           0
#define AXI_TILE_DMA_REG_TILES_Y_TILES_Y_MASK                            0x0000ffff /* TILES_Y, RW, 16 bit */
#define AXI_TILE_DMA_REG_CUR_POS                              0x001c
#define AXI_TILE_DMA_REG_CUR_POS_CUR_TILE_X_SHIFT                        0
#define AXI_TILE_DMA_REG_CUR_POS_CUR_TILE_X_MASK                         0x0000ffff /* CUR_TILE_X, RW, 16 bit */
#define AXI_TILE_DMA_REG_CUR_POS_CUR_TILE_Y_SHIFT                        16
#define AXI_TILE_DMA_REG_CUR_POS_CUR_TILE_Y_MASK                         0xffff0000 /* CUR_TILE_Y, RW, 16 bit */
#define AXI_TILE_DMA_REG_LINE                                 0x0020
#define AXI_TILE_DMA_REG_LINE_CURRENT_LINE_SHIFT                         0
#define AXI_TILE_DMA_REG_LINE_CURRENT_LINE_MASK                          0x000000ff /* CURRENT_LINE, RO, 8 bit */
#define AXI_TILE_DMA_REG_PERF                                 0x0024
#define AXI_TILE_DMA_INTR_INT_RAW                             0x0040
#define AXI_TILE_DMA_INTR_INT_RAW_DONE_RAW_SHIFT                         0 /* done_raw, W1C, 1 bit */
#define AXI_TILE_DMA_INTR_INT_RAW_ERROR_RAW_SHIFT                        1 /* error_raw, W1C, 1 bit */
#define AXI_TILE_DMA_INTR_INT_RAW_FRAME_DONE_RAW_SHIFT                   2 /* frame_done_raw, W1C, 1 bit */
#define AXI_TILE_DMA_INTR_INT_FORCE                           0x0044
#define AXI_TILE_DMA_INTR_INT_FORCE_DONE_RAW_SHIFT                       0 /* done_raw, W1S, 1 bit */
#define AXI_TILE_DMA_INTR_INT_FORCE_ERROR_RAW_SHIFT                      1 /* error_raw, W1S, 1 bit */
#define AXI_TILE_DMA_INTR_INT_FORCE_FRAME_DONE_RAW_SHIFT                 2 /* frame_done_raw, W1S, 1 bit */
#define AXI_TILE_DMA_INTR_INT_MASK                            0x0048
#define AXI_TILE_DMA_INTR_INT_MASK_DONE_MASK_SHIFT                       0
#define AXI_TILE_DMA_INTR_INT_MASK_DONE_MASK_MASK                        0x00000001 /* done_mask, RW, 1 bit */
#define AXI_TILE_DMA_INTR_INT_MASK_ERROR_MASK_SHIFT                      1
#define AXI_TILE_DMA_INTR_INT_MASK_ERROR_MASK_MASK                       0x00000002 /* error_mask, RW, 1 bit */
#define AXI_TILE_DMA_INTR_INT_MASK_FRAME_DONE_MASK_SHIFT                 2
#define AXI_TILE_DMA_INTR_INT_MASK_FRAME_DONE_MASK_MASK                  0x00000004 /* frame_done_mask, RW, 1 bit */
#define AXI_TILE_DMA_INTR_INT_STATUS                          0x004c
#define AXI_TILE_DMA_INTR_INT_STATUS_DONE_STATUS_SHIFT                   0
#define AXI_TILE_DMA_INTR_INT_STATUS_DONE_STATUS_MASK                    0x00000001 /* done_status, RO, 1 bit */
#define AXI_TILE_DMA_INTR_INT_STATUS_ERROR_STATUS_SHIFT                  1
#define AXI_TILE_DMA_INTR_INT_STATUS_ERROR_STATUS_MASK                   0x00000002 /* error_status, RO, 1 bit */
#define AXI_TILE_DMA_INTR_INT_STATUS_FRAME_DONE_STATUS_SHIFT             2
#define AXI_TILE_DMA_INTR_INT_STATUS_FRAME_DONE_STATUS_MASK              0x00000004 /* frame_done_status, RO, 1 bit */



/**
  * @union       axi_tile_dma_reg_ctrl_t
  * @address     0x0000
  * @brief       DMA Control Register
  */
typedef union {
    u32 val;
    struct {
        u32 start      :  1; /* W1P, reset: 0x0, Trigger 128x128 tile transfer to DRAM */
        u32 reset_pos  :  1; /* W1P, reset: 0x0, Reset tile coordinates (TileX=0, TileY=0) */
        u32 soft_reset :  1; /* W1P, reset: 0x0, Software reset for DMA FSM and tile position (deferred until the active transfer completes) */
        u32 reserved_0 : 29; /* NA, reserved */
    } reg;
} axi_tile_dma_reg_ctrl_t;
/**
  * @union       axi_tile_dma_reg_status_t
  * @address     0x0004
  * @brief       DMA Status Register
  */
typedef union {
    u32 val;
    struct {
        u32 busy               :  1; /* RO, reset: 0x0, DMA active transfer busy flag */
        u32 last_bresp         :  2; /* RO, reset: 0x0, Last AXI write response status */
        u32 soft_reset_pending :  1; /* RO, reset: 0x0, Soft reset requested, waiting for the active transfer to complete */
        u32 reserved_0         : 28; /* NA, reserved */
    } reg;
} axi_tile_dma_reg_status_t;
/**
  * @union       axi_tile_dma_reg_base_low_t
  * @address     0x0008
  * @brief       DRAM Frame Base Address (Lower 32 bits)
  */
typedef union {
    u32 val;
    struct {
        u32 base_addr_low : 32; /* RW, reset: 0x00000000, Lower 32 bits of Frame Destination Base Address (4KB aligned: bits 11..0 ignored) */
    } reg;
} axi_tile_dma_reg_base_low_t;
/**
  * @union       axi_tile_dma_reg_base_high_t
  * @address     0x000c
  * @brief       DRAM Frame Base Address (Upper 32 bits)
  */
typedef union {
    u32 val;
    struct {
        u32 base_addr_high : 32; /* RW, reset: 0x00000000, Upper 32 bits of Frame Base Address (64-bit DRAM space) */
    } reg;
} axi_tile_dma_reg_base_high_t;
/**
  * @union       axi_tile_dma_reg_stride_t
  * @address     0x0010
  * @brief       DRAM Frame Row Byte Stride
  */
typedef union {
    u32 val;
    struct {
        u32 stride     : 32; /* RW, reset: 0x00000000, Framebuffer row byte stride / pitch (multiple of 512 bytes, low bits ignored) */
    } reg;
} axi_tile_dma_reg_stride_t;
/**
  * @union       axi_tile_dma_reg_tiles_x_t
  * @address     0x0014
  * @brief       Horizontal Tiles Count
  */
typedef union {
    u32 val;
    struct {
        u32 tiles_x    : 16; /* RW, reset: 0x0001, Total number of horizontal tiles per frame row */
        u32 reserved_0 : 16; /* NA, reserved */
    } reg;
} axi_tile_dma_reg_tiles_x_t;
/**
  * @union       axi_tile_dma_reg_tiles_y_t
  * @address     0x0018
  * @brief       Vertical Tile Rows Count
  */
typedef union {
    u32 val;
    struct {
        u32 tiles_y    : 16; /* RW, reset: 0x0001, Total number of vertical tile rows per frame */
        u32 reserved_0 : 16; /* NA, reserved */
    } reg;
} axi_tile_dma_reg_tiles_y_t;
/**
  * @union       axi_tile_dma_reg_cur_pos_t
  * @address     0x001c
  * @brief       Current Tile Position
  */
typedef union {
    u32 val;
    struct {
        u32 cur_tile_x : 16; /* RW, reset: 0x0000, Current horizontal tile index (0..TILES_X-1) */
        u32 cur_tile_y : 16; /* RW, reset: 0x0000, Current vertical tile row index (0..TILES_Y-1) */
    } reg;
} axi_tile_dma_reg_cur_pos_t;
/**
  * @union       axi_tile_dma_reg_line_t
  * @address     0x0020
  * @brief       Current Line Progress
  */
typedef union {
    u32 val;
    struct {
        u32 current_line :  8; /* RO, reset: 0x00, Line index being issued on AXI AW within active tile (0..127) */
        u32 reserved_0   : 24; /* NA, reserved */
    } reg;
} axi_tile_dma_reg_line_t;
/**
  * @union       axi_tile_dma_reg_perf_t
  * @address     0x0024
  * @brief       Performance Cycle Counter
  */
typedef union {
    u32 val;
    struct {
        u32 perf_cycles : 32; /* RO, reset: 0x00000000, Elapsed clock cycles during active tile transfer */
    } reg;
} axi_tile_dma_reg_perf_t;
/**
  * @union       axi_tile_dma_intr_int_raw_t
  * @address     0x0040
  * @brief       DMA Interrupt Controller RFMS4-Raw status Register\n set when event \n clear raw when write 1
  */
typedef union {
    u32 val;
    struct {
        u32 done_raw       :  1; /* W1C, reset: 0x0, Tile done interrupt (1: unmasked/open) raw, default 0 */
        u32 error_raw      :  1; /* W1C, reset: 0x0, Error interrupt (1: unmasked/open) raw, default 0 */
        u32 frame_done_raw :  1; /* W1C, reset: 0x0, Frame done interrupt (1: unmasked/open) raw, default 0 */
        u32 reserved_0     : 29; /* NA, reserved */
    } reg;
} axi_tile_dma_intr_int_raw_t;
/**
  * @union       axi_tile_dma_intr_int_force_t
  * @address     0x0044
  * @brief       DMA Interrupt Controller RFMS4-Force Register\n for SW debug use \n write 1 set raw
  */
typedef union {
    u32 val;
    struct {
        u32 done_raw       :  1; /* W1S, reset: 0x0, Tile done interrupt (1: unmasked/open) force, write 1 set, debug use */
        u32 error_raw      :  1; /* W1S, reset: 0x0, Error interrupt (1: unmasked/open) force, write 1 set, debug use */
        u32 frame_done_raw :  1; /* W1S, reset: 0x0, Frame done interrupt (1: unmasked/open) force, write 1 set, debug use */
        u32 reserved_0     : 29; /* NA, reserved */
    } reg;
} axi_tile_dma_intr_int_force_t;
/**
  * @union       axi_tile_dma_intr_int_mask_t
  * @address     0x0048
  * @brief       DMA Interrupt Controller RFMS4-Mask Register\n1: int off\n0: int open\n default 1, int off
  */
typedef union {
    u32 val;
    struct {
        u32 done_mask       :  1; /* RW, reset: 0x0, Tile done interrupt (1: unmasked/open) mask, default 1, int off */
        u32 error_mask      :  1; /* RW, reset: 0x0, Error interrupt (1: unmasked/open) mask, default 1, int off */
        u32 frame_done_mask :  1; /* RW, reset: 0x0, Frame done interrupt (1: unmasked/open) mask, default 1, int off */
        u32 reserved_0      : 29; /* NA, reserved */
    } reg;
} axi_tile_dma_intr_int_mask_t;
/**
  * @union       axi_tile_dma_intr_int_status_t
  * @address     0x004c
  * @brief       DMA Interrupt Controller RFMS4-status Register\n status = raw && (!mask)
  */
typedef union {
    u32 val;
    struct {
        u32 done_status       :  1; /* RO, reset: 0x0, Tile done interrupt (1: unmasked/open) stauts default 0 */
        u32 error_status      :  1; /* RO, reset: 0x0, Error interrupt (1: unmasked/open) stauts default 0 */
        u32 frame_done_status :  1; /* RO, reset: 0x0, Frame done interrupt (1: unmasked/open) stauts default 0 */
        u32 reserved_0        : 29; /* NA, reserved */
    } reg;
} axi_tile_dma_intr_int_status_t;


#endif /* __AXI_TILE_DMA_REGMAP_REGIF_H__ */
