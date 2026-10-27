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
    `gpu_set_texture` puts a texture in the texture table, once the GPU is not rendering a frame,
    and flushes the threads' texture caches (`gpu_flush_texture_caches`), which could hold the
    texels that were there before.
  - `gpu_regs.h`: the driver's register accessors, one pair per block (`vis_dma_read_reg`,
    `cp_write_reg`, ...), by the offsets of the block's own register map
  - `dp.c`, `dp.h`: the PS's DisplayPort output (DP TX, AV buffer, DPDMA). It shows a frame
    buffer at 1280 x 720, 60 Hz, in the background: the hot-plug interrupt trains the link when a
    monitor is plugged in and stops the stream when it is pulled. `dp_show` switches to another
    frame buffer at the next vertical sync, `dp_wait_shown` waits for it.
  - `board.c`, `board.h`: start-up, with the interrupt controller and an assert printer
  - `sd.c`, `sd.h`: the SD card (the ZCU104's slot, the PS's SD1) through the BSP's xilffs
    (FatFs): `sd_scan` goes through a directory of its FAT volume (`0:/`), `sd_read` reads a file
    whole into memory
- `lviv_gl/`: lviv_gl, a subset of OpenGL 1.x on the driver (`lviv_gl.h` lists what it takes),
  a C API for C and C++ applications. `gl_api.c` (C) is the API and its state; `lviv_geom.cpp`
  (C++ on GLM, behind the C interface of `lviv_geom.h`) the matrices of GL's matrix calls and
  the vertex transform, lighting, clipping and tile binning, ported from `dv/raster_sw`, into
  the driver's frame data. A frame is what is drawn after `glClear`; `lviv_gl_frame` renders it
  (the application keeps the display). `dv/lviv_gl_test` checks it on the host against
  raster_sw.
- `gltf/`: glTF 2.0 scenes for lviv_gl (`gltf_scene.h`, C++ on fastgltf behind a C interface),
  from a `.glb` or a `.gltf` with its buffers embedded, in memory: the triangle meshes, their
  metallic-roughness materials as GL's fixed-function ones with their base color textures
  (`KHR_texture_transform` too), the first camera and the `KHR_lights_punctual` lights (spot
  lights as point lights). No other textures, skins or morph targets. A texture is the GPU's own
  texels (ARGB in Morton order), copied from the file where `scripts/gltf_swizzle.py` put them,
  else its PNG or JPEG (in the file, not one of its own) decoded by stb_image (`stb_image.c`,
  NEON on the A53), at most 512 x 512, and swizzled; the largest are halved until all fit
  lviv_gl's 4 MiB. `dv/lviv_gl_test` draws a scene on the host as `gl_test` does.
- `third_party/`: git submodules (after a clone, `git submodule update --init`, or clone with
  `--recursive`): GLM 1.0.3; fastgltf v0.9.1 and simdjson v4.6.11, its JSON parser, which
  `fastgltf.patch` and `simdjson.patch` make build for the standalone BSP (no file system there;
  GCC's NEON types). `make vitis` applies them, once each; should one no longer apply,
  `git checkout .` in its submodule and `make vitis` again. stb (003501f, 2026-10-22), as it is:
  its `stb_image.h` (and `stb_image_write.h`, for `dv/raster_sw`).
- `sdcard/`: files for `gl_test`'s SD card (FAT32, its root): `suzanne.glb`, and `suzanne.gltf`
  the same with its buffer embedded (base64), raster_sw's Suzanne (`dv/raster_sw/objs/suzanne.obj`
  as it loads it) with its camera and its light as a directional light; `suzanne_textured.glb`,
  her with raster_sw's texture (`dv/raster_sw/texture_64x64.jpg`, the JPEG as it is), and
  `suzanne_swizzled.glb` the same through `scripts/gltf_swizzle.py`. That script makes any `.gltf` or `.glb` one `.glb` with everything in
  it, its base color textures also pre-swizzled (Pillow and NumPy; `--size`, 512 by default).
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
- `gl_test/main.cpp`: a demo of lviv_gl in C++, driven from the UART console: a glTF file from the
  SD card drawn with OpenGL 1.x calls (`gltf/`), with its camera and lights, from the start
  (`suzanne.gltf`, if the card has it) and again for every frame, double-buffered as in
  `raster_test`. `l` lists the card's glTF files, numbered; `o`, a number and Enter draws that
  one instead. The model is still until `s` turns it a degree a frame (`s` again stops
  it). `1` and `2` choose who draws the frame, as in `raster_test`; `r` draws again after a frame
  that failed, `?` lists the keys.
  Once a second it prints the frame rate, the frame time (the GPU's, mean and standard
  deviation), the front end's time (the GL calls on the A53, the mean), the triangles sent and,
  with the command processor, its cycle counter.

## Build and run

In `bd/gpu_test`:

- `make vitis_gui` opens the Vitis workspace `build/vitis/gpu_test/`, made first if needed: the
  platform `gpu_test` from the XSA (standalone on `psu_cortexa53_0`, its BSP with xilffs; `make
  xsa` runs first if there is none) and the applications `raster_test` and `gl_test`. Each builds
  its directories where they are (`src/` and `raster_test/`; `src/`, `lviv_gl/`, `gltf/` and
  `gl_test/` with fastgltf's and simdjson's sources, GLM's and stb's headers, libm and
  libstdc++), linked with xilffs, so edits in the IDE land in the repo. `gl_test` has a 64 MiB
  heap, for the glTF files and their scenes, and a 1 MiB stack (`VITIS_APP_LDFLAGS_gl_test`).
- Both compile with `VITIS_APP_OPTIMIZATION` and `VITIS_APP_CFLAGS` of `bd/gpu_test/Makefile`:
  `-O2 -flto -mcpu=cortex-a53 -fno-exceptions -DNDEBUG`, which the link gets too (link-time
  optimization), and GLM's NEON code (`-DGLM_FORCE_INTRINSICS -DGLM_FORCE_DEFAULT_ALIGNED_GENTYPES`).
- `make vitis_build` builds `raster_test.elf` and `gl_test.elf` without the IDE
  (`vitis_build_raster_test` or `vitis_build_gl_test` one of them; not while the IDE has the
  workspace open: build there instead).
- An application lists every `.c`, `.cpp`, `.h` and `.hpp` of its directories and the headers of
  `include/` (the generated ones too), not the submodules' headers. A file added or removed
  outside the IDE is listed by the next `make vitis`, `vitis_gui` or `vitis_build`, with the IDE
  closed; an application added to `VITIS_APPS` in `bd/gpu_test/Makefile` is made then too.
- After a hardware change, `make xsa` and then either target: the platform, and the bitstream and
  `psu_init.tcl` the IDE's launch configurations use, take the new XSA. Until then, the targets
  warn in red that the XSA is out of date (older than the RTL, the SpinalHDL sources, the
  constraints or the project's block design).
- `make vitis_clean` deletes the workspace.

Run `raster_test` or `gl_test` on the board from the IDE and use the PS UART (115200 8N1);
`gl_test` draws glTF files from the SD card: copy `sdcard/`'s, or others, to a FAT32 card's root.
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
lviv_gl: frame memory at 0x60000000, 256 MiB: 2581110 triangles a frame
DisplayPort: 1280 x 720 at 60 Hz; plug in or pull a monitor
keys: 1 CPU, 2 command processor; s turn the model or stop it; r draw again; l SD card; o open a model; ? keys
model: suzanne.gltf, 968 triangles, 0 textures, 1 light, its camera; 26341 bytes read in ... ms, parsed in ... ms
CPU, suzanne.gltf
CPU, suzanne.gltf: 60.0 frames/s, frame time ... ± ... us, front end ... us, 650 triangles
```

(`DisplayPort: monitor plugged in` and the link it trained come before the keys when a monitor is
plugged in at the start, otherwise whenever one is.)

The control port's address comes from the platform's `xparameters.h` (`XPAR_GPU_TOP_BD_0_BASEADDR`,
`0xA000_0000`); an application's two frame buffers (about 4 MB each), `raster_test`'s texture and
triangle, and lviv_gl's 4 MiB texture pool are static arrays in PS DDR, the textures in the first
128 MiB (the texture caches' window). The frame buffers are not cached (2 MiB blocks of their
own): the GPU and the DPDMA see them as they are, with no cache maintenance. `gl_test` gives
lviv_gl its frame memory, where the GPU reads each frame's triangles from, as a section of its
own: 256 MiB at `0x6000_0000`, about 2.58 million triangles (`gl_test/lviv_frame.ld`, a second
linker script).
