// Memory copies by the PS's FPD DMA (GDMA), split over its 8 channels, their ends signalled by
// their interrupts.
#pragma once

#include <stddef.h>
#include <stdint.h>

#include "xscugic.h"

#ifdef __cplusplus
extern "C"
{
#endif

// The channels' interrupts on gic (board_init does it). Returns 0, or -1 on failure.
int gdma_init(XScuGic *gic);

// bytes from src to dst (physical addresses), src out of the CPU's caches, sleeping (wfi) until the
// channels' interrupts; not from an interrupt handler. Returns 0, or -1 on an AXI error or before
// gdma_init.
int gdma_copy(uint64_t dst, uint64_t src, size_t bytes);

#ifdef __cplusplus
}
#endif
