/*
 * 
 * Reg Interface C-Header [AUTOGENERATE by SpinalHDL]
 */

#ifndef __APB_THREAD_REGMAP_REGIF_H__
#define __APB_THREAD_REGMAP_REGIF_H__

#define THREAD_REG_STATUS                          0x0000
#define THREAD_REG_STATUS_BUSY_SHIFT                         0
#define THREAD_REG_STATUS_BUSY_MASK                          0x00000001 /* BUSY, RO, 1 bit */
#define THREAD_REG_ZBUF                            0x0004
#define THREAD_REG_ZBUF_ZBUF_CLEAR_SHIFT                     0
#define THREAD_REG_ZBUF_ZBUF_CLEAR_MASK                      0x00000001 /* ZBUF_CLEAR, RO, 1 bit */
#define THREAD_REG_CACHE                           0x0008
#define THREAD_REG_CACHE_CACHE_FLUSH_SHIFT                   0
#define THREAD_REG_CACHE_CACHE_FLUSH_MASK                    0x00000001 /* CACHE_FLUSH, WO, 1 bit */
#define THREAD_REG_RESERVED_0C                     0x000c
#define THREAD_REG_CACHE_HITS                      0x0010
#define THREAD_REG_CACHE_MISSES                    0x0014
#define THREAD_REG_CACHE_EVICTIONS                 0x0018
#define THREAD_REG_CACHE_STALL_CYCLES              0x001c



/**
  * @union       thread_reg_status_t
  * @address     0x0000
  * @brief       Thread Status and Soft Reset Register
  */
typedef union {
    u32 val;
    struct {
        u32 busy       :  1; /* RO, reset: 0x0, Read thread status (0: empty, 1: busy); write 1 to reset the thread core */
        u32 reserved_0 : 31; /* NA, reserved */
    } reg;
} thread_reg_status_t;
/**
  * @union       thread_reg_zbuf_t
  * @address     0x0004
  * @brief       Z-Buffer Control Register
  */
typedef union {
    u32 val;
    struct {
        u32 zbuf_clear :  1; /* RO, reset: 0x0, Write 1 to reset the Z-buffer; reads 1 while the reset is in progress */
        u32 reserved_0 : 31; /* NA, reserved */
    } reg;
} thread_reg_zbuf_t;
/**
  * @union       thread_reg_cache_t
  * @address     0x0008
  * @brief       Cache Control Register
  */
typedef union {
    u32 val;
    struct {
        u32 cache_flush :  1; /* WO, reset: 0x0, Write 1 to flush the cache */
        u32 reserved_0  : 31; /* NA, Reserved */
    } reg;
} thread_reg_cache_t;
/**
  * @union       thread_reg_reserved_0c_t
  * @address     0x000c
  * @brief       Reserved
  */
typedef union {
    u32 val;
    struct {
        u32 reserved_0 : 32; /* NA, Reserved */
    } reg;
} thread_reg_reserved_0c_t;
/**
  * @union       thread_reg_cache_hits_t
  * @address     0x0010
  * @brief       Reserved: cache hit counter (not implemented)
  */
typedef union {
    u32 val;
    struct {
        u32 reserved_0 : 32; /* NA, Reserved */
    } reg;
} thread_reg_cache_hits_t;
/**
  * @union       thread_reg_cache_misses_t
  * @address     0x0014
  * @brief       Reserved: cache miss counter (not implemented)
  */
typedef union {
    u32 val;
    struct {
        u32 reserved_0 : 32; /* NA, Reserved */
    } reg;
} thread_reg_cache_misses_t;
/**
  * @union       thread_reg_cache_evictions_t
  * @address     0x0018
  * @brief       Reserved: cache eviction counter (not implemented)
  */
typedef union {
    u32 val;
    struct {
        u32 reserved_0 : 32; /* NA, Reserved */
    } reg;
} thread_reg_cache_evictions_t;
/**
  * @union       thread_reg_cache_stall_cycles_t
  * @address     0x001c
  * @brief       Reserved: cache stall cycle counter (not implemented)
  */
typedef union {
    u32 val;
    struct {
        u32 reserved_0 : 32; /* NA, Reserved */
    } reg;
} thread_reg_cache_stall_cycles_t;


#endif /* __APB_THREAD_REGMAP_REGIF_H__ */
