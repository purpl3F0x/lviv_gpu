// What the applications start with on the ZCU104's A53 (standalone BSP).
#pragma once

#include "xscugic.h"

#ifdef __cplusplus
extern "C"
{
#endif

// Failed driver asserts printed to the UART (they otherwise stop the program silently), and gic
// set up with the CPU's interrupts on, for the DP output's and the GPU's handlers, and the GDMA's
// (gdma_init). Returns 0, or -1 on failure.
int board_init(XScuGic *gic);

// A PS block's interrupt on gic, from the block's SDT interrupt ID (bits [11:0] the number, [15:12]
// the device tree trigger type), set up as XSetupInterruptSystem would set it on the BSP's own GIC
// instance. Returns 0, or -1 on failure.
int board_connect_irq(XScuGic *gic, u32 intr_id, Xil_InterruptHandler handler, void *ref);

#ifdef __cplusplus
}
#endif
