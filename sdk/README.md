# GPU SDK

Bare-metal software for the GPU on the ZCU104 (A53, standalone BSP).

- `include/`: the interface to the hardware
  - `gpu_triangle.h`: the 96-byte triangle record, generated with `rtl/generated/triangle_unpack.sv`
    by `scripts/create_triangle_layout.py`
  - `generated/<Name>/`: the register maps of the SpinalHDL blocks (C header, JSON, HTML), not
    tracked; `make spinal` at the top of the repo writes them
  - `gpu_map.h`: where each block sits in the control port, and the generated headers
- `src/gpu.c`, `src/gpu.h`: the driver. A frame is rendered one tile at a time: frontend tile,
  visibility DMA, wait for idle, tile DMA.
- `src/main.c`: the bring-up demo for `bd/dummy_test`. It builds a random scene and a visibility
  stream from the triangles' bounding boxes, renders a 1280 x 720 frame and checks every pixel
  against dummy_core's pattern.

## Build and run

1. `make xsa` in `bd/dummy_test` writes `build/bd/dummy_test/dummy_test.xsa`, and `make spinal`
   at the top of the repo the register maps in `include/generated/`.
2. In Vitis, create a platform from the XSA (standalone, `psu_cortexa53_0`) and an empty
   application on it.
3. Add `src/` to the application's sources and `include/` to its include paths.
4. Build, program the board, and watch the PS UART (115200 8N1):

```
register check: ok
scene: 512 triangles, ... triangle-tile pairs over 60 tiles
frame: ... us
image: 0 of 983040 pixels wrong
PASS
```

The control port is at `0xA000_0000` (`GPU_BASEADDR`); the frame buffer (about 4 MB) and the scene
are static arrays in PS DDR.
