# GPU SDK

Bare-metal software for the GPU on the ZCU104 (A53, standalone BSP).

- `include/`: the interface to the hardware
  - `gpu_triangle.h`: the 96-byte triangle record, generated with `rtl/generated/triangle_unpack.sv`
    by `scripts/create_triangle_layout.py`
  - `generated/<Name>/`: the register maps of the SpinalHDL blocks (C header, JSON, HTML), not
    tracked; the Vitis targets below, or `make spinal` at the top of the repo, write them
  - `gpu_map.h`: where each block sits in the control port, and the generated headers
- `src/gpu.c`, `src/gpu.h`: the driver. A frame is rendered one tile at a time: frontend tile,
  visibility DMA, wait for idle, tile DMA. The DMAs are polled, or their interrupts waited for.
- `src/dp.c`, `src/dp.h`: the PS's DisplayPort output (DP TX, AV buffer, DPDMA). It shows a frame
  buffer at 1280 x 720, 60 Hz, and follows hot-plug interrupts: link trained when a monitor is
  plugged in, stream stopped when it is pulled.
- `src/main.c`: the bring-up demo for `bd/dummy_test`. It shows a test pattern on the DisplayPort
  output until Enter is pressed on the UART. Then it builds a random scene and a visibility
  stream from the triangles' bounding boxes, renders a 1280 x 720 frame and checks every pixel
  against dummy_core's pattern, tests the DMAs' interrupts and renders the frame again on them,
  then shows the frame instead of the pattern.

## Build and run

In `bd/dummy_test`:

- `make vitis_gui` opens the Vitis workspace `build/vitis/dummy_test/`, made first if needed: the
  platform `dummy_test` from the XSA (standalone on `psu_cortexa53_0`; `make xsa` runs
  first if there is none) and the application `gpu_demo`. The application builds `src/` where it
  is, so edits in the IDE land in the repo.
- `make vitis_build` builds `gpu_demo.elf` without the IDE (not while the IDE has the workspace
  open: build there instead).
- The application lists every `.c` and `.h` of `src/` and `include/` (the generated headers too).
  A file added or removed outside the IDE is listed by the next `make vitis`, `vitis_gui` or
  `vitis_build`, with the IDE closed.
- After a hardware change, `make xsa` and then either target: the platform takes the new XSA.
  Until then, the targets warn in red that the XSA is out of date (older than the RTL, the
  constraints or the project's block design).
- `make vitis_clean` deletes the workspace.

Run `gpu_demo` on the board from the IDE and watch the PS UART (115200 8N1):

```
DisplayPort: test pattern, 1280 x 720 at 60 Hz; press Enter to run the GPU tests
DisplayPort: monitor plugged in
DisplayPort: 2 lane(s) at 5.40 Gb/s, 1280 x 720 at 60 Hz
register check: ok
scene: 512 triangles, ... triangle-tile pairs over 60 tiles
frame (polled): ... us
image: 0 of 983040 pixels wrong
interrupt lines: ok
frame (interrupts): ... us
image: 0 of 983040 pixels wrong
interrupts: 60 visibility DMA, 60 tile DMA (expected 60 each), 0 spurious
PASS
DisplayPort: showing the frame (1280 x 720) at 1280 x 720, 60 Hz; plug in or pull a monitor
```

The test pattern: eight bands of left-to-right ramps, top to bottom the hue wheel (two bands),
grey, red, green, blue, and red into blue with green rising downwards (two bands). The demo then
keeps running, following the monitor. On the screen, each 128 x 128 tile of
dummy_core's pattern gets redder to the right and greener downwards, with a little blue for its
triangle count.

The control port's address comes from the platform's `xparameters.h` (`XPAR_GPU_TOP_BD_0_BASEADDR`,
`0xA000_0000` in `bd/dummy_test`); the frame buffer (about 4 MB) and the scene are static arrays in
PS DDR.
