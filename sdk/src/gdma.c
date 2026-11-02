#include "gdma.h"

#include "board.h"
#include "xil_exception.h"
#include "xil_io.h"
#include "xparameters.h"
#include "xzdma_hw.h"

// A channel's share of a copy: whole bursts (16 x 16 bytes), at least GDMA_MIN_SHARE
#define GDMA_BURST 256u
#define GDMA_MIN_SHARE 4096u
// XZDMA_CH_ISR_OFFSET and XZDMA_CH_IEN_OFFSET on the ZynqMP
#define GDMA_CH_ISR 0x100u
#define GDMA_CH_IEN 0x108u
#define GDMA_DONE XZDMA_IXR_DMA_DONE_MASK
#define GDMA_ERRORS (XZDMA_IXR_AXI_WR_DATA_MASK | XZDMA_IXR_AXI_RD_DATA_MASK)

static const struct
{
    UINTPTR base;
    u32 intr_id;
} channels[] = {
    {XPAR_XZDMA_0_BASEADDR, XPAR_XZDMA_0_INTERRUPTS}, {XPAR_XZDMA_1_BASEADDR, XPAR_XZDMA_1_INTERRUPTS},
    {XPAR_XZDMA_2_BASEADDR, XPAR_XZDMA_2_INTERRUPTS}, {XPAR_XZDMA_3_BASEADDR, XPAR_XZDMA_3_INTERRUPTS},
    {XPAR_XZDMA_4_BASEADDR, XPAR_XZDMA_4_INTERRUPTS}, {XPAR_XZDMA_5_BASEADDR, XPAR_XZDMA_5_INTERRUPTS},
    {XPAR_XZDMA_6_BASEADDR, XPAR_XZDMA_6_INTERRUPTS}, {XPAR_XZDMA_7_BASEADDR, XPAR_XZDMA_7_INTERRUPTS},
};
#define CHANNELS (sizeof channels / sizeof channels[0])

static int ready;
static volatile uint32_t events[CHANNELS]; // the copy's, from the channel's interrupt

static void on_interrupt(void *ref)
{
    const UINTPTR base = channels[(uintptr_t)ref].base;
    const uint32_t isr = Xil_In32(base + GDMA_CH_ISR);
    Xil_Out32(base + GDMA_CH_ISR, isr); // write 1 to clear
    (void)Xil_In32(base + GDMA_CH_ISR); // the line low before the GIC ends the interrupt
    events[(uintptr_t)ref] |= isr;
}

int gdma_init(XScuGic *gic)
{
    for (uintptr_t n = 0; n < CHANNELS; n++)
    {
        Xil_Out32(channels[n].base + GDMA_CH_ISR, XZDMA_IXR_ALL_INTR_MASK);
        Xil_Out32(channels[n].base + GDMA_CH_IEN, GDMA_DONE | GDMA_ERRORS);
        if (board_connect_irq(gic, channels[n].intr_id, on_interrupt, (void *)n) != 0)
            return -1;
    }
    ready = 1;
    return 0;
}

static void start(UINTPTR base, uint64_t dst, uint64_t src, uint32_t bytes)
{
    Xil_Out32(base + XZDMA_CH_CTRL0_OFFSET, XZDMA_CTRL0_RESET_VALUE); // simple mode, read then write
    Xil_Out32(base + XZDMA_CH_SRC_DSCR_WORD0_OFFSET, (uint32_t)src);
    Xil_Out32(base + XZDMA_CH_SRC_DSCR_WORD1_OFFSET, (uint32_t)(src >> 32));
    Xil_Out32(base + XZDMA_CH_SRC_DSCR_WORD2_OFFSET, bytes);
    Xil_Out32(base + XZDMA_CH_SRC_DSCR_WORD3_OFFSET, 0); // not coherent
    Xil_Out32(base + XZDMA_CH_DST_DSCR_WORD0_OFFSET, (uint32_t)dst);
    Xil_Out32(base + XZDMA_CH_DST_DSCR_WORD1_OFFSET, (uint32_t)(dst >> 32));
    Xil_Out32(base + XZDMA_CH_DST_DSCR_WORD2_OFFSET, bytes);
    Xil_Out32(base + XZDMA_CH_DST_DSCR_WORD3_OFFSET, 0);
    Xil_Out32(base + XZDMA_CH_CTRL2_OFFSET, XZDMA_CH_CTRL2_EN_MASK);
}

// Asleep until channel n's interrupt: 0 done, -1 an AXI error
static int wait_done(unsigned n)
{
    for (;;)
    {
        Xil_ExceptionDisable(); // so that the interrupt cannot come between the check and wfi
        const uint32_t e = events[n];
        if (e & (GDMA_DONE | GDMA_ERRORS))
        {
            Xil_ExceptionEnable();
            return (e & GDMA_ERRORS) ? -1 : 0;
        }
        __asm__ __volatile__("wfi"); // woken by the interrupt pending, taken once enabled
        Xil_ExceptionEnable();
    }
}

int gdma_copy(uint64_t dst, uint64_t src, size_t bytes)
{
    size_t share = (bytes + CHANNELS - 1) / CHANNELS;
    share = (share + GDMA_BURST - 1) / GDMA_BURST * GDMA_BURST;
    if (share < GDMA_MIN_SHARE)
        share = GDMA_MIN_SHARE;
    if (!ready || share > XZDMA_WORD2_SIZE_MASK)
        return -1;

    unsigned used = 0;
    for (size_t at = 0; at < bytes; at += share, used++)
    {
        events[used] = 0;
        start(channels[used].base, dst + at, src + at, (uint32_t)(bytes - at < share ? bytes - at : share));
    }
    int status = 0;
    for (unsigned n = 0; n < used; n++)
        status |= wait_done(n);
    return status;
}
