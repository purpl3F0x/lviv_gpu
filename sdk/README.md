# GPU SDK

Bare-metal software for the GPU on the ZCU104 (A53, standalone BSP), for `bd/gpu_test`.

- `include/`: the interface to the hardware
  - `gpu_triangle.h`: the 96-byte triangle record, generated with `rtl/generated/triangle_unpack.sv`
    by `scripts/create_triangle_layout.py`
  - `generated/<Name>/`: the register maps of the SpinalHDL blocks (C header, JSON, HTML), not
    tracked; `make xsa`, or `make spinal` at the top of the repo, writes them (the Vitis targets
    below only when they are missing, so they match the XSA)
  - `gpu_map.h`: where each block sits in the control port, and the generated headers
  - `models/`: models as C arrays for `glDrawArrays(GL_TRIANGLES, ...)`: `suzanne.h`, made once
    from `dv/raster_sw/objs/suzanne.obj` as raster_sw loads it
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
- `lviv_gl/`: lviv_gl, a subset of OpenGL 1.x on the driver (`lviv_gl.h` lists what it takes),
  a C API for C and C++ applications. `gl_api.c` (C) is the API and its state; `lviv_geom.cpp`
  (C++ on GLM, behind the C interface of `lviv_geom.h`) the matrices of GL's matrix calls and
  the vertex transform, lighting, clipping and tile binning, ported from `dv/raster_sw`, into
  the driver's frame data. A frame is what is drawn after `glClear`; `lviv_gl_frame` renders it
  (the application keeps the display). `dv/lviv_gl_test` checks it on the host against
  raster_sw.
- `third_party/glm/`: GLM 1.0.3, a git submodule: after a clone, `git submodule update --init`
  (or clone with `--recursive`)
- `raster_test/main.c`: a demo of the raster core, driven from the UART console. The DP output
  runs from the start, showing a test pattern (color ramps made in the code). Keys choose who
  draws the frame (`1` the CPU tile by tile, `2` the command processor) and how one triangle made
  in the code (blue, red and green corners) is colored: `c` its corners' colors, `t` a 64 x 64
  checkerboard texture alone, `b` the texture modulating the colors; each starts drawing. The
  triangle is then drawn again for every frame, one per vertical sync (60 frames a second while a
  frame takes under 16.7 ms), double-buffered: into the buffer not on the screen, shown from the
  next vertical sync on. Once a second it prints the frame rate, the frame time (mean and standard
  deviation) and, with the command processor, its cycle counter (`FRAME_CYCLES`, the mean). `r`
  draws again (after the test pattern or a frame that failed), `p` shows the test pattern, `?`
  lists the keys.
- `gl_test/main.cpp`: a demo of lviv_gl in C++, driven from the UART console: Suzanne
  (`include/models/suzanne.h`) drawn with OpenGL 1.x calls in raster_sw's scene (its camera, light
  and material), from the start and again for every frame, double-buffered as in `raster_test`.
  It is still, as in `dv/raster_sw/gpu_top_ref.png`, until `s` turns it a degree a frame (`s`
  again stops it). `1` and `2` choose who draws the frame, as in `raster_test`; `r` draws again
  after a frame that failed, `?` lists the keys. Once a second it prints the frame rate, the frame
  time (the GPU's, mean and standard deviation), the front end's time (the GL calls on the A53,
  the mean), the triangles sent and, with the command processor, its cycle counter.

## Build and run

In `bd/gpu_test`:

- `make vitis_gui` opens the Vitis workspace `build/vitis/gpu_test/`, made first if needed: the
  platform `gpu_test` from the XSA (standalone on `psu_cortexa53_0`; `make xsa` runs first if
  there is none) and the applications `raster_test` and `gl_test`. Each builds its directories
  where they are (`src/` and `raster_test/`; `src/`, `lviv_gl/` and `gl_test/`, with GLM's
  headers and libm), so edits in the IDE land in the repo.
- Both compile with `VITIS_APP_OPTIMIZATION` and `VITIS_APP_CFLAGS` of `bd/gpu_test/Makefile`:
  `-O2 -flto -mcpu=cortex-a53 -fno-exceptions -DNDEBUG`, which the link gets too (link-time
  optimization), and GLM's NEON code (`-DGLM_FORCE_INTRINSICS -DGLM_FORCE_DEFAULT_ALIGNED_GENTYPES`).
  The FPU and NEON take no flag on the A53's AArch64: GCC uses them already, and the BSP turns
  them on at their first use (a trap, once). After a change to the Makefile, the next
  `make vitis`, `vitis_gui` or `vitis_build` sets the applications up again, over what was changed
  in the IDE.
- `make vitis_build` builds `raster_test.elf` and `gl_test.elf` without the IDE
  (`vitis_build_raster_test` or `vitis_build_gl_test` one of them; not while the IDE has the
  workspace open: build there instead).
- An application lists every `.c`, `.cpp`, `.h` and `.hpp` of its directories and the headers of
  `include/` (the generated ones too), not GLM's. A file added or removed outside the IDE is
  listed by the next `make vitis`, `vitis_gui` or `vitis_build`, with the IDE closed; an
  application added to `VITIS_APPS` in `bd/gpu_test/Makefile` is made then too.
- After a hardware change, `make xsa` and then either target: the platform, and the bitstream and
  `psu_init.tcl` the IDE's launch configurations use, take the new XSA. Until then, the targets
  warn in red that the XSA is out of date (older than the RTL, the SpinalHDL sources, the
  constraints or the project's block design).
- `make vitis_clean` deletes the workspace.

Run `raster_test` or `gl_test` on the board from the IDE and use the PS UART (115200 8N1).
`raster_test`:

```
Raster demo: gpu_top's raster core at 0xa0000000
triangle: (640, 60) blue, (160, 660) red, (1120, 660) green; in 48 of 60 tiles
texture: 64 x 64 checkerboard at 0x...
DisplayPort: 1280 x 720 at 60 Hz, the test pattern; plug in or pull a monitor
keys: 1 CPU, 2 command processor; c color, t texture, b blend; r draw again; p test pattern; ? keys
CP, color
CP, color: 60.0 frames/s, frame time ... ± ... us (CP cycle counter: ...)
CP, color: 60.0 frames/s, frame time ... ± ... us (CP cycle counter: ...)
```

`gl_test`:

```
lviv_gl demo: gpu_top's raster core at 0xa0000000
model: suzanne, 968 triangles
DisplayPort: 1280 x 720 at 60 Hz; plug in or pull a monitor
keys: 1 CPU, 2 command processor; s turn the model or stop it; r draw again; ? keys
CPU, suzanne
CPU, suzanne: 60.0 frames/s, frame time ... ± ... us, front end ... us, 650 triangles
```

(`DisplayPort: monitor plugged in` and the link it trained come before the keys when a monitor is
plugged in at the start, otherwise whenever one is.)

The control port's address comes from the platform's `xparameters.h` (`XPAR_GPU_TOP_BD_0_BASEADDR`,
`0xA000_0000`); an application's two frame buffers (about 4 MB each), `raster_test`'s texture and
triangle, and lviv_gl's frame data (up to 16384 triangles) and 4 MiB texture pool are static
arrays in PS DDR, the textures in the first 128 MiB (the texture caches' window). The frame
buffers are not cached (2 MiB blocks of their own): the GPU and the DPDMA see them as they are,
with no cache maintenance.
