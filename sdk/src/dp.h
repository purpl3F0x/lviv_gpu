// DisplayPort output of the Zynq UltraScale+ PS (DP TX, AV buffer manager, DPDMA), standalone BSP.
//
// Shows a frame buffer at DP_WIDTH x DP_HEIGHT, 60 Hz, whatever the monitor prefers. The link is
// brought up when a monitor is plugged in and down when it is pulled: the hot-plug interrupt only
// records the event, and dp_service, called from the main loop, does the link training.
#pragma once

#include <stdint.h>

#include "xscugic.h"

// The output's size: any standard 60 Hz mode (1280 x 720, 1920 x 1080, ...); dp_init fails on another.
// Open issue: at 1280 x 720 the picture shows 30 to 40 pixels to the right on the monitor tried, black
// on the left and its right edge cut; 1920 x 1080 is right.
#define DP_WIDTH 1280
#define DP_HEIGHT 720

// Sets up the DP subsystem for frame: DP_HEIGHT lines of DP_WIDTH 32-bit 0xAARRGGBB pixels (the
// alpha is not used), stride bytes apart; the frame and the stride 256-byte aligned. Connects the
// DP and DPDMA interrupts to gic, which must be initialized. Returns 0, or -1 on failure.
int dp_init(XScuGic *gic, const uint32_t *frame, uint32_t stride);

// Shows frame instead, laid out as the first one, from the next vertical sync on. Flushes it from
// the data cache first, so what the CPU wrote is what is shown.
void dp_show(const uint32_t *frame);

// Handles the hot-plug events since the last call: on a monitor plugged in, trains the link and
// starts the stream; on one pulled, stops it; on a request from the monitor, retrains if the link
// was lost. Prints what it does to the UART.
void dp_service(void);

// The stream is running to a monitor.
int dp_is_on(void);
