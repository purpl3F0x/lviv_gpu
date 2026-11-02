#include "board.h"

#include "gdma.h"
#include "xil_assert.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xinterrupt_wrap.h"
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
    return gdma_init(gic);
}

int board_connect_irq(XScuGic *gic, u32 intr_id, Xil_InterruptHandler handler, void *ref)
{
    const u32 id = XGet_IntrId(intr_id) + XGet_IntrOffset(intr_id);
    const u8 trigger = (XGet_TriggerType(intr_id) == 1 || XGet_TriggerType(intr_id) == 2) ? XINTR_IS_EDGE_TRIGGERED
                                                                                          : XINTR_IS_LEVEL_TRIGGERED;
    XScuGic_SetPriorityTriggerType(gic, id, XINTERRUPT_DEFAULT_PRIORITY, trigger);
    if (XScuGic_Connect(gic, id, handler, ref) != XST_SUCCESS)
        return -1;
    XScuGic_Enable(gic, id);
    return 0;
}
