#include "board.h"

#include "xil_assert.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xparameters.h"

// A failed assert in a driver stops the program where it is, silently: say where.
static void on_assert(const char8 *file, s32 line)
{
    xil_printf("assert failed: %s, line %d\r\n", file, (int)line);
}

int board_init(XScuGic *gic)
{
    Xil_AssertSetCallback(on_assert);
    XScuGic_Config *config = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    if (config == NULL || XScuGic_CfgInitialize(gic, config, config->CpuBaseAddress) != XST_SUCCESS)
        return -1;
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT, (Xil_ExceptionHandler)XScuGic_InterruptHandler, gic);
    Xil_ExceptionEnable();
    return 0;
}
