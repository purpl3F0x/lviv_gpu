// DisplayPort output of the Zynq UltraScale+ PS (DP TX, AV buffer manager, DPDMA), standalone BSP.
//
// Shows a frame buffer at DP_WIDTH x DP_HEIGHT, 60 Hz, whatever the monitor prefers, in the
// background: the hot-plug interrupt trains the link when a monitor is plugged in (or asks for it
// again) and stops the stream when it is pulled, a few hundred milliseconds in the interrupt each
// time, printing what it does to the UART.
#pragma once

#include <stdint.h>

#include "xscugic.h"

#ifdef __cplusplus
extern "C"
{
#endif

// The output's size: any standard 60 Hz mode (1280 x 720, 1920 x 1080, ...); dp_init fails on another.
#define DP_WIDTH 1280
#define DP_HEIGHT 720

// Sets up the DP subsystem for frame: DP_HEIGHT lines of DP_WIDTH 32-bit 0xAARRGGBB pixels (the
// alpha is not used), stride bytes apart; the frame and the stride 256-byte aligned. The DPDMA
// reads the frames behind the CPU's caches: memory the CPU does not cache (Xil_SetTlbAttributes
// NORM_NONCACHE on its 2 MiB blocks), or flushed by the caller before dp_show. Connects the
// DP and DPDMA interrupts to gic, which must be initialized; trains the link if a monitor is
// already plugged in. Returns 0, or -1 on failure.
int dp_init(XScuGic *gic, const uint32_t *frame, uint32_t stride);

// Shows frame instead, laid out as the first one, from the next vertical sync on. One frame per
// vertical sync: dp_wait_shown before the next.
void dp_show(const uint32_t *frame);

// Until the frame of the last dp_show is the one being read, so the one before is free to draw
// into: at most a frame. Returns 0, or -1 if no frame is being read (no stream since dp_init) or
// the switch did not come within two frames.
int dp_wait_shown(void);

// The stream is running to a monitor.
int dp_is_on(void);

#ifdef __cplusplus
}
#endif
