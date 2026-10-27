# Block design with gpu_top's raster core on the ZCU104 (gpu_test_bd.tcl), the CPU driving it.
# Usage: make [project|gui|synth|impl|bitstream|xsa|export_bd|clean]
#        make [vitis|vitis_gui|vitis_build|vitis_build_<app>|vitis_clean]; see scripts/vivado/bd.mk.

BD_NAME = gpu_test
PART = xczu7ev-ffvc1156-2-e
BOARD_PART = xilinx.com:zcu104:part0:1.1
BD_TCL = gpu_test_bd.tcl
XDC = gpu_test.xdc

include ../gpu_top.mk
RTL = $(GPU_TOP_RTL)

# The Vitis applications, on the drivers in sdk/src (the SD card's on the BSP's xilffs): raster_test,
# the raster core's tests in sdk/raster_test; gl_test, models from glTF files on the SD card drawn
# with OpenGL 1.x calls, in sdk/gl_test (C++): the files read by sdk/gltf (C++ on the submodules
# sdk/third_party/fastgltf and simdjson, patched for the BSP: VITIS_PATCHES; their textures'
# images decoded by the submodule sdk/third_party/stb's stb_image), drawn by lviv_gl in
# sdk/lviv_gl (C, its transform in C++ on GLM, the submodule sdk/third_party/glm; libm). libstdc++
# is linked with the BSP's libraries, whose system calls it needs (the link would search them
# before it otherwise).
VITIS_APPS = raster_test gl_test
VITIS_APP_SRC_raster_test = ../../sdk/src ../../sdk/raster_test
VITIS_APP_INCLUDES_raster_test = ../../sdk/include
VITIS_APP_LIBS_raster_test = xilffs
VITIS_APP_SRC_gl_test = ../../sdk/src ../../sdk/lviv_gl ../../sdk/gltf ../../sdk/gl_test \
                        ../../sdk/third_party/fastgltf/src ../../sdk/third_party/simdjson/singleheader/simdjson.cpp
VITIS_APP_INCLUDES_gl_test = ../../sdk/include
VITIS_APP_EXTERNAL_INCLUDES_gl_test = ../../sdk/third_party/glm ../../sdk/third_party/fastgltf/include \
                                      ../../sdk/third_party/simdjson/singleheader ../../sdk/third_party/stb
VITIS_APP_LIBS_gl_test = m xilffs stdc++
# lviv_gl's frame memory: a section of its own, 256 MiB at a fixed address (lviv_frame.ld); the
# heap, for the glTF files and what is made of them, 64 MiB; the stack, for the parsers, 1 MiB (the
# BSP's are 8 KiB)
VITIS_APP_LDFLAGS_gl_test = -Wl,-T,$(abspath ../../sdk/gl_test/lviv_frame.ld) \
                            -Wl,--defsym,_HEAP_SIZE=0x4000000 -Wl,--defsym,_STACK_SIZE=0x100000
VITIS_PATCHES = ../../sdk/third_party/fastgltf.patch ../../sdk/third_party/simdjson.patch
# Their compiler flags (the link gets them too): -O2 with link-time optimization, tuned for the
# A53, C++ without exceptions, and no assert() (GLM's index checks, which would bring in newlib's
# printf; the BSP's driver asserts are in its libraries). The A53's FPU and NEON (AArch64's
# Advanced SIMD) take no flag: GCC uses them already, and the BSP turns them on at their first
# use. GLM's own NEON code is on too (plain C++ otherwise), its vectors aligned: vec3 padded to 16
# bytes. Every file that includes GLM must see the same GLM settings, hence here.
VITIS_APP_OPTIMIZATION = -O2
VITIS_APP_CFLAGS = -flto=auto -mcpu=cortex-a53 -fno-exceptions -DNDEBUG \
                   -DGLM_FORCE_INTRINSICS -DGLM_FORCE_DEFAULT_ALIGNED_GENTYPES

.DEFAULT_GOAL := project
include ../../scripts/vivado/bd.mk
