#include "dp.h"

#include <stdatomic.h>

#include "board.h"
#include "sleep.h"
#include "xavbuf.h"
#include "xavbuf_clk.h"
#include "xdpdma.h"
#include "xdppsu.h"
#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xpseudo_asm.h" // mfcpsr, mtcpsr

#define DP_BYTES_PER_PIXEL 4
#define DP_TRAINING_ATTEMPTS 3
#define DP_MMU_BLOCK 0x200000 // the standalone translation table maps DDR below 4 GB in 2 MB blocks
#define DP_CSC_ONE 0x1000     // 1.0 in the blender's color conversion matrices

static XDpPsu dp_tx;
static XAVBuf avbuf;
static XDpDma_FrameBuffer frame_buffer;

// The DPDMA reads its descriptors from memory, and its driver writes them into the XDpDma instance
// with no cache maintenance (AMD's example turns the data cache off): the instance gets an MMU block
// of its own, not cacheable.
static union {
    XDpDma instance;
    u8 block[DP_MMU_BLOCK];
} dpdma_block __attribute__((aligned(DP_MMU_BLOCK)));
static XDpDma *const dpdma = &dpdma_block.instance;

static XVidC_VideoMode mode; // DP_WIDTH x DP_HEIGHT at 60 Hz
static int dma_started;      // the DPDMA reads the frame from the first stream on, connected or not
static volatile int stream_on;

// The frame buffers, and by their index: the one the DPDMA reads, the one it takes at the next
// vertical sync, the one drawn waiting for that one to go, dp_back's (-1: none); the descriptor ID of
// the frame queued last. The vertical sync interrupt keeps them too: elsewhere, interrupts_off.
static uint32_t *buffers[DP_FRAMES];
static int screen, queued = -1, ready = -1, drawn = -1;
static u16 frame_id;
static volatile uint32_t shown; // the frames the DPDMA switched to, read with interrupts on

static void start(void);
static void stop(const char *why);

// One core: interrupts off is the lock against the vertical sync interrupt, and compiler fences
// (C11's, for a signal handler on the same thread) keep the accesses between off and restore.
static u32 interrupts_off(void)
{
    const u32 daif = mfcpsr();
    Xil_ExceptionDisable();
    atomic_signal_fence(memory_order_seq_cst);
    return daif;
}

static void interrupts_restore(u32 daif)
{
    atomic_signal_fence(memory_order_seq_cst);
    mtcpsr(daif);
}

// The hot-plug interrupt's: a monitor plugged in or pulled
static void on_hpd_event(void *ref)
{
    (void)ref;
    if (XDpPsu_IsConnected(&dp_tx))
    {
        xil_printf("DisplayPort: monitor plugged in\r\n");
        start();
    }
    else
    {
        stop("monitor pulled");
    }
}

// ... and the monitor asking for attention: retrained if the link was lost
static void on_hpd_pulse(void *ref)
{
    (void)ref;
    if (stream_on && XDpPsu_CheckLinkStatus(&dp_tx, dp_tx.LinkConfig.LaneCount) != XST_SUCCESS)
    {
        xil_printf("DisplayPort: link lost, retraining\r\n");
        start();
    }
}

// The DPDMA reading the frames: its channel triggered, at the first vertical sync of the first stream
static int dma_running(void)
{
    return dpdma->Gfx.Channel.Current != NULL && dpdma->Gfx.TriggerStatus == XDPDMA_TRIGGER_DONE;
}

// Frame buffer f taken by the DPDMA at the next vertical sync: the descriptor not in use set up for
// f, with an ID of its own, then the channel's start address pointed at it and the channel
// retriggered (XDpDma_DisplayGfxFrameBuffer would wait for the vertical sync interrupt, a frame
// more). As XDpDma_SetupChannel, but the descriptor whole in memory before the start address moves:
// a retrigger still pending may fetch it from then on. One at a time: the other one is being read.
static void queue(int f)
{
    XDpDma_Channel *const channel = &dpdma->Gfx.Channel;
    XDpDma_Descriptor *const desc =
        channel->Current == &channel->Descriptor0 ? &channel->Descriptor1 : &channel->Descriptor0;
    frame_buffer.Address = (u64)(uintptr_t)buffers[f];
    XDpDma_InitVideoDescriptor(desc, &frame_buffer);
    desc->DSCR_ID = ++frame_id;
    __asm__ __volatile__("dsb sy" ::: "memory"); // the BSP's dsb() does not hold the compiler back
    channel->Current = desc;
    XDpDma_WriteReg(dpdma->Config.BaseAddr, XDPDMA_CH3_DSCR_STRT_ADDRE, UPPER_32_BITS((UINTPTR)desc));
    XDpDma_WriteReg(dpdma->Config.BaseAddr, XDPDMA_CH3_DSCR_STRT_ADDR, LOWER_32_BITS((UINTPTR)desc));
    XDpDma_ReTrigger(dpdma, GraphicsChan);
    queued = f;
}

// The frame on its way, on the screen once the DPDMA has read its descriptor (the ID Linux's ZynqMP
// DPDMA driver follows too), the one it replaces free; then a frame waiting, sent. In the vertical
// sync interrupt or with interrupts off.
static void advance(void)
{
    if (!dma_running())
        return;
    if (queued >= 0 && (XDpDma_ReadReg(dpdma->Config.BaseAddr, XDPDMA_CH3_DSCR_ID) & 0xFFFF) == frame_id)
    {
        screen = queued;
        queued = -1;
        shown++;
    }
    if (queued < 0 && ready >= 0)
    {
        queue(ready);
        ready = -1;
    }
}

// At a vertical sync: advance (dp_back and dp_present do too: the descriptor may come in after the
// interrupt reads its ID). A frame not taken at it has its retrigger sent again: harmless while the
// first is pending (the same descriptor at the same start address), and the frame not stuck should
// one be lost.
static void on_vsync(void)
{
    const int waiting = queued;
    advance();
    if (queued >= 0 && queued == waiting)
        XDpDma_ReTrigger(dpdma, GraphicsChan);
}

// The DPDMA's interrupt: its driver's handler (the channel's first trigger, at a vertical sync), then
// the frame buffers' turns
static void on_dpdma_interrupt(void *ref)
{
    (void)ref;
    const u32 status = XDpDma_ReadReg(dpdma->Config.BaseAddr, XDPDMA_ISR);
    XDpDma_InterruptHandler(dpdma);
    if (status & XDPDMA_ISR_VSYNC_INT_MASK)
        on_vsync();
}

// The graphics layer's color conversion into the blender, for 0xAARRGGBB words (DRM's ARGB8888)
// read as RGBA8888: the identity XAVBuf_ConfigureGraphicsPipeline writes, with red and blue swapped,
// as Linux's ZynqMP display driver does for that format.
static void set_graphics_csc(u32 base)
{
    for (u32 i = 0; i < 9; i++)
        XAVBuf_WriteReg(base, XAVBUF_V_BLEND_IN2CSC_COEFF0 + 4 * i, i == 2 || i == 4 || i == 6 ? DP_CSC_ONE : 0);
}

int dp_init(XScuGic *gic, uint32_t *const frames[DP_FRAMES], uint32_t stride)
{
    XDpPsu_Config *dp_config = XDpPsu_LookupConfig(XPAR_XDPPSU_0_BASEADDR);
    XDpDma_Config *dma_config = XDpDma_LookupConfig(XPAR_XDPDMA_0_BASEADDR);
    mode = XVidC_GetVideoModeId(DP_WIDTH, DP_HEIGHT, XVIDC_FR_60HZ, FALSE);
    if (dp_config == NULL || dma_config == NULL || mode == XVIDC_VM_NOT_SUPPORTED)
        return -1;
    Xil_SetTlbAttributes((UINTPTR)&dpdma_block, NORM_NONCACHE);
    XDpPsu_CfgInitialize(&dp_tx, dp_config, dp_config->BaseAddr);
    XAVBuf_CfgInitialize(&avbuf, dp_config->BaseAddr);
    XDpDma_CfgInitialize(dpdma, dma_config);
    if (XDpPsu_InitializeTx(&dp_tx) != XST_SUCCESS)
        return -1;

    // The frame alone, on the graphics layer, opaque whatever its alpha. The AV buffer's RGBA8888 is
    // 0xAABBGGRR words (its ABGR8888 is 0xRRGGBBAA): set_graphics_csc swaps red and blue for ours.
    if (XDpDma_SetGraphicsFormat(dpdma, RGBA8888) != XST_SUCCESS ||
        XAVBuf_SetInputNonLiveGraphicsFormat(&avbuf, RGBA8888) != XST_SUCCESS)
        return -1;
    XDpDma_SetQOS(dpdma, 11);
    XAVBuf_EnableGraphicsBuffers(&avbuf, 1);
    XAVBuf_SetOutputVideoFormat(&avbuf, RGB_8BPC);
    XAVBuf_InputVideoSelect(&avbuf, XAVBUF_VIDSTREAM1_NONE, XAVBUF_VIDSTREAM2_NONLIVE_GFX);
    XAVBuf_ConfigureGraphicsPipeline(&avbuf);
    set_graphics_csc(dp_config->BaseAddr);
    XAVBuf_ConfigureOutputVideo(&avbuf);
    XAVBuf_SetBlenderAlpha(&avbuf, 0xFF, 1);
    XDpPsu_CfgMsaEnSynchClkMode(&dp_tx, 0);
    // Pixel clock from the PS's video PLL (set per stream, XAVBuf_SetPixelClock).
    XAVBuf_SetAudioVideoClkSrc(&avbuf, XAVBUF_PS_CLK, XAVBUF_PS_CLK);
    XAVBuf_SoftReset(&avbuf);

    frame_buffer.Stride = stride;
    frame_buffer.LineSize = DP_WIDTH * DP_BYTES_PER_PIXEL;
    frame_buffer.Size = stride * DP_HEIGHT;
    for (int f = 0; f < DP_FRAMES; f++)
        buffers[f] = frames[f];
    frame_buffer.Address = (u64)(uintptr_t)buffers[screen];

    // Hot-plug: HPD events (plugged in or pulled) and HPD pulses (the monitor asks for attention).
    // The DPDMA's vertical sync interrupt starts the frame (XDpDma_DisplayGfxFrameBuffer) and sends
    // the ones after.
    XDpPsu_WriteReg(dp_config->BaseAddr, XDPPSU_INTR_DIS, 0xFFFFFFFF);
    XDpPsu_WriteReg(dp_config->BaseAddr, XDPPSU_INTR_MASK, 0xFFFFFFFF);
    // The driver asserts a reference that is not NULL; the handlers do not use it.
    XDpPsu_SetHpdEventHandler(&dp_tx, on_hpd_event, &dp_tx);
    XDpPsu_SetHpdPulseHandler(&dp_tx, on_hpd_pulse, &dp_tx);
    if (board_connect_irq(gic, dp_config->IntrId, (Xil_InterruptHandler)XDpPsu_HpdInterruptHandler, &dp_tx) != 0 ||
        board_connect_irq(gic, dma_config->IntrId, on_dpdma_interrupt, dpdma) != 0)
        return -1;
    XDpDma_InterruptEnable(dpdma, XDPDMA_IEN_VSYNC_INT_MASK);

    // A monitor plugged in before now raised no event. Trained before the hot-plug interrupt is on,
    // so that it does not start again from inside.
    if (XDpPsu_IsConnected(&dp_tx))
    {
        xil_printf("DisplayPort: monitor plugged in\r\n");
        start();
    }
    XDpPsu_WriteReg(dp_config->BaseAddr, XDPPSU_INTR_EN, XDPPSU_INTR_HPD_IRQ_MASK | XDPPSU_INTR_HPD_EVENT_MASK);
    return 0;
}

uint32_t *dp_back(void)
{
    const u32 daif = interrupts_off();
    advance();
    int f = 0;
    while (f < DP_FRAMES && (f == screen || f == queued || f == ready))
        f++;
    if (f == DP_FRAMES) // none free: the one waiting, drawn over
    {
        f = ready;
        ready = -1;
    }
    drawn = f;
    interrupts_restore(daif);
    return buffers[f];
}

void dp_present(void)
{
    const u32 daif = interrupts_off();
    const int f = drawn;
    drawn = -1;
    if (f >= 0)
    {
        advance();
        if (!dma_running())
        {
            // Not read yet: the channel's first trigger takes the frame buffer as it is then
            screen = f;
            frame_buffer.Address = (u64)(uintptr_t)buffers[f];
        }
        else if (queued < 0)
        {
            queue(f);
        }
        else
        {
            ready = f; // for the vertical sync interrupt; one waiting before, dropped
        }
    }
    interrupts_restore(daif);
}

uint32_t dp_frames_shown(void)
{
    return shown;
}

// The link at the most both the monitor and the board take (the mode needs less).
static u32 train(void)
{
    XDpPsu_LinkConfig *link = &dp_tx.LinkConfig;
    u32 status = XDpPsu_GetRxCapabilities(&dp_tx);
    if (status != XST_SUCCESS)
        return status;
    if (XDpPsu_SetEnhancedFrameMode(&dp_tx, link->SupportEnhancedFramingMode ? 1 : 0) != XST_SUCCESS ||
        XDpPsu_SetLaneCount(&dp_tx, link->MaxLaneCount) != XST_SUCCESS ||
        XDpPsu_SetLinkRate(&dp_tx, link->MaxLinkRate) != XST_SUCCESS ||
        XDpPsu_SetDownspread(&dp_tx, link->SupportDownspreadControl) != XST_SUCCESS)
        return XST_FAILURE;
    return XDpPsu_EstablishLink(&dp_tx);
}

// The main stream: DP_WIDTH x DP_HEIGHT, 60 Hz, RGB 8 bits per color.
static void start_stream(void)
{
    const u32 base = dp_tx.Config.BaseAddr;

    XDpPsu_SetColorEncode(&dp_tx, XDPPSU_CENC_RGB);
    XDpPsu_CfgMsaSetBpc(&dp_tx, XVIDC_BPC_8);
    XDpPsu_CfgMsaUseStandardVideoMode(&dp_tx, mode);
    XAVBuf_SetPixelClock(dp_tx.MsaConfig.PixelClockHz);

    // The transmitter, then the AV buffer, reset for the new pixel clock.
    XDpPsu_WriteReg(base, XDPPSU_SOFT_RESET, 0x1);
    usleep(10);
    XDpPsu_WriteReg(base, XDPPSU_SOFT_RESET, 0x0);
    XDpPsu_SetMsaValues(&dp_tx);
    XDpPsu_WriteReg(base, XAVBUF_BUF_SRST_REG, 0x3);
    usleep(10);
    XDpPsu_WriteReg(base, XAVBUF_BUF_SRST_REG, 0x0);

    XDpPsu_EnableMainLink(&dp_tx, 1);
}

static void stop(const char *why)
{
    XDpPsu_EnableMainLink(&dp_tx, 0);
    if (stream_on)
        xil_printf("DisplayPort: %s, stream stopped\r\n", why);
    stream_on = 0;
}

static void start(void)
{
    XDpPsu_EnableMainLink(&dp_tx, 0);

    // Wake the monitor up: twice, as the first write may only wake its AUX channel.
    u8 power_on = 0x1;
    XDpPsu_AuxWrite(&dp_tx, XDPPSU_DPCD_SET_POWER_DP_PWR_VOLTAGE, 1, &power_on);
    XDpPsu_AuxWrite(&dp_tx, XDPPSU_DPCD_SET_POWER_DP_PWR_VOLTAGE, 1, &power_on);

    for (int attempt = 0; attempt < DP_TRAINING_ATTEMPTS; attempt++)
    {
        usleep(100000);
        u32 status = train();
        if (status == XST_DEVICE_NOT_FOUND)
        {
            stop("monitor pulled during training");
            return;
        }
        if (status != XST_SUCCESS)
            continue;

        if (!dma_started)
        {
            XDpDma_DisplayGfxFrameBuffer(dpdma, &frame_buffer);
            dma_started = 1;
        }
        start_stream();
        if (XDpPsu_CheckLinkStatus(&dp_tx, dp_tx.LinkConfig.LaneCount) == XST_SUCCESS)
        {
            // Link rate codes are in 0.27 Gb/s per lane.
            const int rate = dp_tx.LinkConfig.LinkRate * 27;
            xil_printf("DisplayPort: %d lane(s) at %d.%02d Gb/s, %d x %d at 60 Hz\r\n", dp_tx.LinkConfig.LaneCount,
                       rate / 100, rate % 100, DP_WIDTH, DP_HEIGHT);
            stream_on = 1;
            return;
        }
    }
    xil_printf("DisplayPort: link training failed\r\n");
    stop("training failed");
}

int dp_is_on(void)
{
    return stream_on;
}
