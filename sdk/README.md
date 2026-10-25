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
    buffer at 1280 x 720, 60 Hz, and follows hot-plug interrupts: link trained when a monitor is
    plugged in, stream stopped when it is pulled.
  - `board.c`, `board.h`: start-up, with the interrupt controller and an assert printer
- `raster_test/main.c`: tests of the raster core. It renders one triangle made in the code (blue,
  red and green corners, colors interpolated) at 1280 x 720, untextured and then with a 64 x 64
  checkerboard made in the code modulating it, each by the CPU and by the command processor,
  checks every pixel against the same triangle worked out in floating point, then shows the last
  frame.

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

Run `raster_test` on the board from the IDE and watch the PS UART (115200 8N1):

```
Raster test: gpu_top's raster core at 0xa0000000
triangle: (640, 60) blue, (160, 660) red, (1120, 660) green; in 48 of 60 tiles
color, CPU: frame ... us
color, CPU: inside 285606 pixels, 0 wrong (largest channel error 1, up to 3 allowed)
color, CPU: outside 692634 pixels, 0 not the clear color
color, CPU: 4800 pixels near an edge, not checked
color, CP: frame ... us
...
texture: 64 x 64 checkerboard at 0x...
texture, CPU: frame ... us
texture, CPU: inside 267780 pixels, 0 wrong (largest channel error 1, up to 3 allowed)
texture, CPU: outside 692634 pixels, 0 not the clear color
texture, CPU: 22626 pixels near an edge or a square's border, not checked
texture, CP: frame ... us
...
PASS
DisplayPort: showing the frame, 1280 x 720 at 60 Hz; plug in or pull a monitor
```

The control port's address comes from the platform's `xparameters.h` (`XPAR_GPU_TOP_BD_0_BASEADDR`,
`0xA000_0000`); the frame buffer (about 4 MB), the texture and the triangle are static arrays in PS
DDR, the texture in the first 128 MiB (the texture caches' window).
