/*
 * 
 * Reg Interface C-Header [AUTOGENERATE by SpinalHDL]
 */

#ifndef __AXI_VISIBILITY_DMA_REGMAP_REGIF_H__
#define __AXI_VISIBILITY_DMA_REGMAP_REGIF_H__

#define AXI_VISIBILITY_DMA_REG_CTRL                                             0x0000
#define AXI_VISIBILITY_DMA_REG_CTRL_START_SHIFT                                      0 /* START, W1P, 1 bit */
#define AXI_VISIBILITY_DMA_REG_CTRL_SOFT_RESET_SHIFT                                 1 /* SOFT_RESET, W1P, 1 bit */
#define AXI_VISIBILITY_DMA_REG_CTRL_IRQ_ENABLE_SHIFT                                 2
#define AXI_VISIBILITY_DMA_REG_CTRL_IRQ_ENABLE_MASK                                  0x00000004 /* IRQ_ENABLE, RW, 1 bit */
#define AXI_VISIBILITY_DMA_REG_CTRL_AUTO_ADV_EN_SHIFT                                3
#define AXI_VISIBILITY_DMA_REG_CTRL_AUTO_ADV_EN_MASK                                 0x00000008 /* AUTO_ADV_EN, RW, 1 bit */
#define AXI_VISIBILITY_DMA_REG_STATUS                                           0x0004
#define AXI_VISIBILITY_DMA_REG_STATUS_BUSY_SHIFT                                     0
#define AXI_VISIBILITY_DMA_REG_STATUS_BUSY_MASK                                      0x00000001 /* BUSY, RO, 1 bit */
#define AXI_VISIBILITY_DMA_REG_STATUS_DONE_SHIFT                                     1 /* DONE, W1C, 1 bit */
#define AXI_VISIBILITY_DMA_REG_STATUS_ERROR_SHIFT                                    2 /* ERROR, W1C, 1 bit */
#define AXI_VISIBILITY_DMA_REG_STATUS_IRQ_STATUS_SHIFT                               3 /* IRQ_STATUS, W1C, 1 bit */
#define AXI_VISIBILITY_DMA_REG_STATUS_FRAME_DONE_SHIFT                               4 /* FRAME_DONE, W1C, 1 bit */
#define AXI_VISIBILITY_DMA_REG_STATUS_AXI_ERR_FLAG_SHIFT                             5
#define AXI_VISIBILITY_DMA_REG_STATUS_AXI_ERR_FLAG_MASK                              0x00000020 /* AXI_ERR_FLAG, RO, 1 bit */
#define AXI_VISIBILITY_DMA_REG_STATUS_DM_ERR_FLAG_SHIFT                              6
#define AXI_VISIBILITY_DMA_REG_STATUS_DM_ERR_FLAG_MASK                               0x00000040 /* DM_ERR_FLAG, RO, 1 bit */
#define AXI_VISIBILITY_DMA_REG_VB_LOW                                           0x0008
#define AXI_VISIBILITY_DMA_REG_VB_LOW_VB_BASE_LOW_SHIFT                              4
#define AXI_VISIBILITY_DMA_REG_VB_LOW_VB_BASE_LOW_MASK                               0xfffffff0 /* VB_BASE_LOW, RW, 28 bit */
#define AXI_VISIBILITY_DMA_REG_VB_HIGH                                          0x000c
#define AXI_VISIBILITY_DMA_REG_TRI_LOW                                          0x0010
#define AXI_VISIBILITY_DMA_REG_TRI_LOW_TRI_BASE_LOW_SHIFT                            5
#define AXI_VISIBILITY_DMA_REG_TRI_LOW_TRI_BASE_LOW_MASK                             0xffffffe0 /* TRI_BASE_LOW, RW, 27 bit */
#define AXI_VISIBILITY_DMA_REG_TRI_HIGH                                         0x0014
#define AXI_VISIBILITY_DMA_REG_TRI_COUNT                                        0x0018
#define AXI_VISIBILITY_DMA_REG_TILE_IDX                                         0x001c
#define AXI_VISIBILITY_DMA_REG_TILE_IDX_TILE_INDEX_SHIFT                             0
#define AXI_VISIBILITY_DMA_REG_TILE_IDX_TILE_INDEX_MASK                              0x0000003f /* TILE_INDEX, RW, 6 bit */
#define AXI_VISIBILITY_DMA_REG_BTT_LIMIT                                        0x0020
#define AXI_VISIBILITY_DMA_REG_BTT_LIMIT_BTT_LIMIT_TRI_SHIFT                         0
#define AXI_VISIBILITY_DMA_REG_BTT_LIMIT_BTT_LIMIT_TRI_MASK                          0x0001ffff /* BTT_LIMIT_TRI, RW, 17 bit */
#define AXI_VISIBILITY_DMA_REG_STAT_VIS                                         0x0024
#define AXI_VISIBILITY_DMA_REG_STAT_CMD                                         0x0028
#define AXI_VISIBILITY_DMA_REG_STAT_STS                                         0x002c
#define AXI_VISIBILITY_DMA_REG_DM_LAST                                          0x0030
#define AXI_VISIBILITY_DMA_REG_DM_LAST_DM_LAST_STS_SHIFT                             0
#define AXI_VISIBILITY_DMA_REG_DM_LAST_DM_LAST_STS_MASK                              0x000000ff /* DM_LAST_STS, RO, 8 bit */
#define AXI_VISIBILITY_DMA_REG_PERF                                             0x0034
#define AXI_VISIBILITY_DMA_INTR_INT_RAW                                         0x0040
#define AXI_VISIBILITY_DMA_INTR_INT_RAW_DONE_RAW_SHIFT                               0 /* done_raw, W1C, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_RAW_ERROR_RAW_SHIFT                              1 /* error_raw, W1C, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_RAW_FRAME_DONE_RAW_SHIFT                         2 /* frame_done_raw, W1C, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_FORCE                                       0x0044
#define AXI_VISIBILITY_DMA_INTR_INT_FORCE_DONE_RAW_SHIFT                             0 /* done_raw, W1S, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_FORCE_ERROR_RAW_SHIFT                            1 /* error_raw, W1S, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_FORCE_FRAME_DONE_RAW_SHIFT                       2 /* frame_done_raw, W1S, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_MASK                                        0x0048
#define AXI_VISIBILITY_DMA_INTR_INT_MASK_DONE_MASK_SHIFT                             0
#define AXI_VISIBILITY_DMA_INTR_INT_MASK_DONE_MASK_MASK                              0x00000001 /* done_mask, RW, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_MASK_ERROR_MASK_SHIFT                            1
#define AXI_VISIBILITY_DMA_INTR_INT_MASK_ERROR_MASK_MASK                             0x00000002 /* error_mask, RW, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_MASK_FRAME_DONE_MASK_SHIFT                       2
#define AXI_VISIBILITY_DMA_INTR_INT_MASK_FRAME_DONE_MASK_MASK                        0x00000004 /* frame_done_mask, RW, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_STATUS                                      0x004c
#define AXI_VISIBILITY_DMA_INTR_INT_STATUS_DONE_STATUS_SHIFT                         0
#define AXI_VISIBILITY_DMA_INTR_INT_STATUS_DONE_STATUS_MASK                          0x00000001 /* done_status, RO, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_STATUS_ERROR_STATUS_SHIFT                        1
#define AXI_VISIBILITY_DMA_INTR_INT_STATUS_ERROR_STATUS_MASK                         0x00000002 /* error_status, RO, 1 bit */
#define AXI_VISIBILITY_DMA_INTR_INT_STATUS_FRAME_DONE_STATUS_SHIFT                   2
#define AXI_VISIBILITY_DMA_INTR_INT_STATUS_FRAME_DONE_STATUS_MASK                    0x00000004 /* frame_done_status, RO, 1 bit */



/**
  * @union       axi_visibility_dma_reg_ctrl_t
  * @address     0x0000
  * @brief       DMA Control Register
  */
typedef union {
    u32 val;
    struct {
        u32 start       :  1; /* W1P, reset: 0x0, Trigger visibility scan and command generation */
        u32 soft_reset  :  1; /* W1P, reset: 0x0, Software reset for engine and internal FIFOs */
        u32 irq_enable  :  1; /* RW, reset: 0x1, Global Interrupt Enable (1: enabled) */
        u32 auto_adv_en :  1; /* RW, reset: 0x1, Enable auto-advancing tile index */
        u32 reserved_0  : 28; /* NA, reserved */
    } reg;
} axi_visibility_dma_reg_ctrl_t;
/**
  * @union       axi_visibility_dma_reg_status_t
  * @address     0x0004
  * @brief       DMA Status Register
  */
typedef union {
    u32 val;
    struct {
        u32 busy         :  1; /* RO, reset: 0x0, Engine active busy status */
        u32 done         :  1; /* W1C, reset: 0x0, Tile processing complete (Write 1 to clear) */
        u32 error        :  1; /* W1C, reset: 0x0, Error detected on AXI read or DataMover (Write 1 to clear) */
        u32 irq_status   :  1; /* W1C, reset: 0x0, Interrupt pending (Write 1 to clear) */
        u32 frame_done   :  1; /* W1C, reset: 0x0, All 60 tiles completed / wrapped (Write 1 to clear) */
        u32 axi_err_flag :  1; /* RO, reset: 0x0, AXI Read Master Bus Error */
        u32 dm_err_flag  :  1; /* RO, reset: 0x0, DataMover Status Error */
        u32 reserved_0   : 25; /* NA, reserved */
    } reg;
} axi_visibility_dma_reg_status_t;
/**
  * @union       axi_visibility_dma_reg_vb_low_t
  * @address     0x0008
  * @brief       Visibility Buffer Base Address [31:0] (8-byte aligned)
  */
typedef union {
    u32 val;
    struct {
        u32 reserved_0  :  4; /* NA, Reserved */
        u32 vb_base_low : 28; /* RW, reset: 0x0000000, Visibility Buffer Base Address [31:3] */
    } reg;
} axi_visibility_dma_reg_vb_low_t;
/**
  * @union       axi_visibility_dma_reg_vb_high_t
  * @address     0x000c
  * @brief       Visibility Buffer Base Address [63:32]
  */
typedef union {
    u32 val;
    struct {
        u32 vb_base_high : 32; /* RW, reset: 0x00000000, Upper 32 bits of Visibility Buffer Base Address */
    } reg;
} axi_visibility_dma_reg_vb_high_t;
/**
  * @union       axi_visibility_dma_reg_tri_low_t
  * @address     0x0010
  * @brief       Triangle Geometry Base Address [31:0] (32-byte aligned)
  */
typedef union {
    u32 val;
    struct {
        u32 reserved_0   :  5; /* NA, Reserved */
        u32 tri_base_low : 27; /* RW, reset: 0x0000000, Triangle Geometry Base Address [31:5] */
    } reg;
} axi_visibility_dma_reg_tri_low_t;
/**
  * @union       axi_visibility_dma_reg_tri_high_t
  * @address     0x0014
  * @brief       Triangle Geometry Base Address [63:32]
  */
typedef union {
    u32 val;
    struct {
        u32 tri_base_high : 32; /* RW, reset: 0x00000000, Upper 32 bits of Triangle Geometry Base Address */
    } reg;
} axi_visibility_dma_reg_tri_high_t;
/**
  * @union       axi_visibility_dma_reg_tri_count_t
  * @address     0x0018
  * @brief       Triangle Count (N elements)
  */
typedef union {
    u32 val;
    struct {
        u32 tri_count  : 32; /* RW, reset: 0x00000000, Total number of triangle visibility elements to evaluate */
    } reg;
} axi_visibility_dma_reg_tri_count_t;
/**
  * @union       axi_visibility_dma_reg_tile_idx_t
  * @address     0x001c
  * @brief       Active Tile Index (0..59)
  */
typedef union {
    u32 val;
    struct {
        u32 tile_index :  6; /* RW, reset: 0x00, Tile selection bit index (0..59) in 64-bit visibility word */
        u32 reserved_0 : 26; /* NA, reserved */
    } reg;
} axi_visibility_dma_reg_tile_idx_t;
/**
  * @union       axi_visibility_dma_reg_btt_limit_t
  * @address     0x0020
  * @brief       Max Triangles per DataMover Command
  */
typedef union {
    u32 val;
    struct {
        u32 btt_limit_tri : 17; /* RW, reset: 0x15555, Max triangles per command (BTT = count * 96 B; 0 = 87381) */
        u32 reserved_0    : 15; /* NA, reserved */
    } reg;
} axi_visibility_dma_reg_btt_limit_t;
/**
  * @union       axi_visibility_dma_reg_stat_vis_t
  * @address     0x0024
  * @brief       Visible Triangle Counter
  */
typedef union {
    u32 val;
    struct {
        u32 stat_vis   : 32; /* RO, reset: 0x00000000, Total visible triangles encountered in current tile */
    } reg;
} axi_visibility_dma_reg_stat_vis_t;
/**
  * @union       axi_visibility_dma_reg_stat_cmd_t
  * @address     0x0028
  * @brief       DataMover Commands Issued Counter
  */
typedef union {
    u32 val;
    struct {
        u32 stat_cmd   : 32; /* RO, reset: 0x00000000, Total DataMover command packets sent */
    } reg;
} axi_visibility_dma_reg_stat_cmd_t;
/**
  * @union       axi_visibility_dma_reg_stat_sts_t
  * @address     0x002c
  * @brief       DataMover Status Received Counter
  */
typedef union {
    u32 val;
    struct {
        u32 stat_sts   : 32; /* RO, reset: 0x00000000, Total DataMover status responses received */
    } reg;
} axi_visibility_dma_reg_stat_sts_t;
/**
  * @union       axi_visibility_dma_reg_dm_last_t
  * @address     0x0030
  * @brief       Last DataMover Status Byte
  */
typedef union {
    u32 val;
    struct {
        u32 dm_last_sts :  8; /* RO, reset: 0x00, Last received raw status byte from DataMover */
        u32 reserved_0  : 24; /* NA, reserved */
    } reg;
} axi_visibility_dma_reg_dm_last_t;
/**
  * @union       axi_visibility_dma_reg_perf_t
  * @address     0x0034
  * @brief       Performance Cycle Counter
  */
typedef union {
    u32 val;
    struct {
        u32 perf_cycles : 32; /* RO, reset: 0x00000000, Elapsed clock cycles during active tile scan */
    } reg;
} axi_visibility_dma_reg_perf_t;
/**
  * @union       axi_visibility_dma_intr_int_raw_t
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
} axi_visibility_dma_intr_int_raw_t;
/**
  * @union       axi_visibility_dma_intr_int_force_t
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
} axi_visibility_dma_intr_int_force_t;
/**
  * @union       axi_visibility_dma_intr_int_mask_t
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
} axi_visibility_dma_intr_int_mask_t;
/**
  * @union       axi_visibility_dma_intr_int_status_t
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
} axi_visibility_dma_intr_int_status_t;


#endif /* __AXI_VISIBILITY_DMA_REGMAP_REGIF_H__ */
