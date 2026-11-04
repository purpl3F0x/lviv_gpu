// DisplayPort output of the Zynq UltraScale+ PS (DP TX, AV buffer manager, DPDMA), standalone BSP.
//
// Shows a frame buffer at DP_WIDTH x DP_HEIGHT, 60 Hz, whatever the monitor prefers, in the
// background: the hot-plug interrupt trains the link when a monitor is plugged in (or asks for it
// again) and stops the stream when it is pulled, a few hundred milliseconds in the interrupt each
// time, printing what it does to the UART.
//
// Triple buffered: one frame buffer on the screen, one on its way there (the DPDMA takes it at the
// next vertical sync, and only one can wait for it), one drawn into. Drawing never waits for the
// screen: a frame drawn while another is on its way waits for the vertical sync interrupt to send
// it, unless the next frame is drawn over it first.
#pragma once

#include <stdint.h>

#include "xscugic.h"

#ifdef __cplusplus
extern "C"
{
#endif

// The output's size from dp_init on: any standard 60 Hz mode (1280 x 720, 1920 x 1080, ...); dp_init
// fails on another. dp_set_mode changes it.
#define DP_WIDTH 1280
#define DP_HEIGHT 720

// The frame buffers it takes turns with
#define DP_FRAMES 3

// Sets up the DP subsystem for frames, DP_FRAMES frame buffers: DP_HEIGHT lines of DP_WIDTH 32-bit
// 0xAARRGGBB pixels (the alpha is not used), stride bytes apart; each frame and the stride 256-byte
// aligned. frames[0] is shown first. The DPDMA reads the frames behind the CPU's caches: memory the
// CPU does not cache (Xil_SetTlbAttributes NORM_NONCACHE on its 2 MiB blocks), or flushed by the
// caller before dp_present. Connects the DP and DPDMA interrupts to gic, which must be initialized;
// trains the link if a monitor is already plugged in. Returns 0, or -1 on failure.
int dp_init(XScuGic *gic, uint32_t *const frames[DP_FRAMES], uint32_t stride);

// The output at width x height, 60 Hz (a standard mode, as DP_WIDTH x DP_HEIGHT), from frames laid
// out as dp_init's for it: the DPDMA stopped, the link trained again and the stream restarted at the
// mode (a few hundred milliseconds, with a monitor in). frames[0], drawn first, is shown, the others
// free for dp_back. Returns 0, or -1 if there is no such mode (the mode so far kept).
int dp_set_mode(int width, int height, uint32_t *const frames[DP_FRAMES], uint32_t stride);

// The frame buffer to draw the next frame into, neither on the screen nor on its way there: the
// frame drawn last instead when it is still waiting to be sent (dropped). Never waits.
uint32_t *dp_back(void);

// The frame drawn into dp_back's buffer, sent to the screen: from the next vertical sync on, or when
// a frame is already on its way, once that one is shown (unless the next is drawn over it first).
// Never waits.
void dp_present(void);

// The frames the DPDMA has switched to since dp_init, one a vertical sync at most: those shown,
// while a monitor is on.
uint32_t dp_frames_shown(void);

// The stream is running to a monitor.
int dp_is_on(void);

#ifdef __cplusplus
}
#endif
