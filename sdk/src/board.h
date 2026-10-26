// What the applications start with on the ZCU104's A53 (standalone BSP).
#pragma once

#include "xscugic.h"

#ifdef __cplusplus
extern "C"
{
#endif

// Failed driver asserts printed to the UART (they otherwise stop the program silently), and gic
// set up with the CPU's interrupts on, for the DP output's and the GPU's handlers. Returns 0, or -1
// on failure.
int board_init(XScuGic *gic);

#ifdef __cplusplus
}
#endif
