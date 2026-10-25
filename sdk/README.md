# GPU SDK

Bare-metal software for the GPU on the ZCU104 (A53, standalone BSP), for `bd/gpu_test`.

- `include/`: the interface to the hardware
  - `gpu_triangle.h`: the 96-byte triangle record, generated with `rtl/generated/triangle_unpack.sv`
    by `scripts/create_triangle_layout.py`
  - `generated/<Name>/`: the register maps of the SpinalHDL blocks (C header, JSON, HTML), not
    tracked; `make xsa`, or `make spinal` at the top of the repo, writes them (the Vitis targets
    below only when they are missing, so they match the XSA)
  - `gpu_map.h`: where each block sits in the control port, and the generated headers
- `src/`: what applications share
  - `gpu.c`, `gpu.h`: the driver. A frame is rendered one tile at a time: z-buffers cleared,
    the frontend's tile box, visibility DMA, wait for idle, tile DMA. `gpu_set_mode` picks who
    does that: the CPU (the reset mode; the DMAs polled or their interrupts waited for), or the
    command processor in gpu_top (the driver sets the frame up at tile 0 and starts it; its end
    is the tile DMA's frame_done).
    `gpu_set_texture` puts a texture in the texture table.
  - `gpu_regs.h`: the driver's register accessors, one pair per block (`vis_dma_read_reg`,
    `cp_write_reg`, ...), by the offsets of the block's own register map
  - `dp.c`, `dp.h`: the PS's DisplayPort output (DP TX, AV buffer, DPDMA). It shows a frame
    buffer at 1280 x 720, 60 Hz, in the background: the hot-plug interrupt trains the link when a
    monitor is plugged in and stops the stream when it is pulled. `dp_show` switches to another
    frame buffer at the next vertical sync, `dp_wait_shown` waits for it.
  - `board.c`, `board.h`: start-up, with the interrupt controller and an assert printer
- `raster_test/main.c`: a demo of the raster core, driven from the UART console. The DP output
  runs from the start, showing a test pattern (color ramps made in the code). Keys choose who
  draws the frame (`1` the CPU tile by tile, `2` the command processor) and how one triangle made
  in the code (blue, red and green corners) is colored: `c` its corners' colors, `t` a 64 x 64
  checkerboard texture alone, `b` the texture modulating the colors; each starts drawing. The
  triangle is then drawn again for every frame, one per vertical sync (60 frames a second while a
  frame takes under 16.7 ms), double-buffered: into the buffer not on the screen, shown from the
  next vertical sync on. Once a second it prints the frame rate and the frame times. `r` draws
  again (after the test pattern or a frame that failed), `p` shows the test pattern, `?` lists the
  keys.

## Build and run

In `bd/gpu_test`:

- `make vitis_gui` opens the Vitis workspace `build/vitis/gpu_test/`, made first if needed: the
  platform `gpu_test` from the XSA (standalone on `psu_cortexa53_0`; `make xsa` runs first if
  there is none) and the application `raster_test`. The application builds `src/` and
  `raster_test/` where they are, so edits in the IDE land in the repo.
- `make vitis_build` builds `raster_test.elf` without the IDE (not while the IDE has the
  workspace open: build there instead).
- The application lists every `.c` and `.h` of `src/`, `raster_test/` and `include/` (the
  generated headers too). A file added or removed outside the IDE is listed by the next
  `make vitis`, `vitis_gui` or `vitis_build`, with the IDE closed.
- After a hardware change, `make xsa` and then either target: the platform, and the bitstream and
  `psu_init.tcl` the IDE's launch configurations use, take the new XSA. Until then, the targets
  warn in red that the XSA is out of date (older than the RTL, the SpinalHDL sources, the
  constraints or the project's block design).
- `make vitis_clean` deletes the workspace.

Run `raster_test` on the board from the IDE and use the PS UART (115200 8N1):

```
Raster demo: gpu_top's raster core at 0xa0000000
triangle: (640, 60) blue, (160, 660) red, (1120, 660) green; in 48 of 60 tiles
texture: 64 x 64 checkerboard at 0x...
DisplayPort: 1280 x 720 at 60 Hz, the test pattern; plug in or pull a monitor
keys: 1 CPU, 2 command processor; c color, t texture, b blend; r draw again; p test pattern; ? keys
CP, color
CP, color: 60.0 frames/s, frame ... us on average, ... us the longest
CP, color: 60.0 frames/s, frame ... us on average, ... us the longest
```

(`DisplayPort: monitor plugged in` and the link it trained come before the keys when a monitor is
plugged in at the start, otherwise whenever one is.)

The control port's address comes from the platform's `xparameters.h` (`XPAR_GPU_TOP_BD_0_BASEADDR`,
`0xA000_0000`); the two frame buffers (about 4 MB each), the texture and the triangle are static
arrays in PS DDR, the texture in the first 128 MiB (the texture caches' window).
