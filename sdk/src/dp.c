#include "dp.h"

#include "sleep.h"
#include "xavbuf.h"
#include "xavbuf_clk.h"
#include "xdpdma.h"
#include "xdppsu.h"
#include "xil_cache.h"
#include "xil_mmu.h"
#include "xil_printf.h"
#include "xinterrupt_wrap.h"
#include "xparameters.h"

#define DP_BYTES_PER_PIXEL 4
#define DP_TRAINING_ATTEMPTS 3
#define DP_MMU_BLOCK 0x200000 // the standalone translation table maps DDR below 4 GB in 2 MB blocks
#define DP_CSC_ONE 0x1000     // 1.0 in the blender's colour conversion matrices

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

// Set by the hot-plug interrupt, taken by dp_service.
static volatile int hpd_event; // a monitor was plugged in or pulled
static volatile int hpd_pulse; // the monitor asks for attention (link lost, ...)

static XVidC_VideoMode mode; // DP_WIDTH x DP_HEIGHT at 60 Hz
static int dma_started;      // the DPDMA reads the frame from the first stream on, connected or not
static int stream_on;

static void on_hpd_event(void *ref)
{
    (void)ref;
    hpd_event = 1;
}

static void on_hpd_pulse(void *ref)
{
    (void)ref;
    hpd_pulse = 1;
}

// A PS block's interrupt on the application's GIC, from the block's SDT interrupt ID (bits [11:0]
// the number, [15:12] the device tree trigger type), set up as XSetupInterruptSystem would set it
// on the BSP's own GIC instance.
static int connect_interrupt(XScuGic *gic, u32 intr_id, Xil_InterruptHandler handler, void *ref)
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

// The graphics layer's colour conversion into the blender, for 0xAARRGGBB words (DRM's ARGB8888)
// read as RGBA8888: the identity XAVBuf_ConfigureGraphicsPipeline writes, with red and blue swapped,
// as Linux's ZynqMP display driver does for that format.
static void set_graphics_csc(u32 base)
{
    for (u32 i = 0; i < 9; i++)
        XAVBuf_WriteReg(base, XAVBUF_V_BLEND_IN2CSC_COEFF0 + 4 * i, i == 2 || i == 4 || i == 6 ? DP_CSC_ONE : 0);
}

int dp_init(XScuGic *gic, const uint32_t *frame, uint32_t stride)
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
    dp_show(frame);

    // Hot-plug: HPD events (plugged in or pulled) and HPD pulses (the monitor asks for attention).
    // The DPDMA's vertical sync interrupt starts the frame (XDpDma_DisplayGfxFrameBuffer).
    XDpPsu_WriteReg(dp_config->BaseAddr, XDPPSU_INTR_DIS, 0xFFFFFFFF);
    XDpPsu_WriteReg(dp_config->BaseAddr, XDPPSU_INTR_MASK, 0xFFFFFFFF);
    // The driver asserts a reference that is not NULL; the handlers do not use it.
    XDpPsu_SetHpdEventHandler(&dp_tx, on_hpd_event, &dp_tx);
    XDpPsu_SetHpdPulseHandler(&dp_tx, on_hpd_pulse, &dp_tx);
    if (connect_interrupt(gic, dp_config->IntrId, (Xil_InterruptHandler)XDpPsu_HpdInterruptHandler, &dp_tx) != 0 ||
        connect_interrupt(gic, dma_config->IntrId, (Xil_InterruptHandler)XDpDma_InterruptHandler, dpdma) != 0)
        return -1;
    XDpPsu_WriteReg(dp_config->BaseAddr, XDPPSU_INTR_EN, XDPPSU_INTR_HPD_IRQ_MASK | XDPPSU_INTR_HPD_EVENT_MASK);
    XDpDma_InterruptEnable(dpdma, XDPDMA_IEN_VSYNC_INT_MASK);

    // A monitor plugged in before now raised no event: look on the first dp_service.
    hpd_event = 1;
    return 0;
}

void dp_show(const uint32_t *frame)
{
    // What the CPU wrote, in memory for the DPDMA.
    Xil_DCacheFlushRange((UINTPTR)frame, frame_buffer.Size);
    frame_buffer.Address = (u64)(uintptr_t)frame;
    // Taken at the next vertical sync; before the first stream, start() hands it over.
    if (dma_started)
        XDpDma_DisplayGfxFrameBuffer(dpdma, &frame_buffer);
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

void dp_service(void)
{
    if (hpd_event)
    {
        hpd_event = 0;
        hpd_pulse = 0;
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
    else if (hpd_pulse)
    {
        hpd_pulse = 0;
        if (stream_on && XDpPsu_CheckLinkStatus(&dp_tx, dp_tx.LinkConfig.LaneCount) != XST_SUCCESS)
        {
            xil_printf("DisplayPort: link lost, retraining\r\n");
            start();
        }
    }
}

int dp_is_on(void)
{
    return stream_on;
}
