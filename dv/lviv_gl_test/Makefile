# lviv_gl on the host (gcc and g++; on Windows the ones raster_sw's g++ comes with): a glTF scene
# drawn as gl_test draws it. The GPU driver is replaced by the test's own gpu_frame, which keeps the
# frame to write and has the CPU draw it (sw_raster.c), to compare its speed with the GPU's.
#
#   make         build lviv_gl_test
#   make scenes  suzanne_gltf.hex (sdk/sdcard/suzanne.glb) in raster_sw's gpu_top scene format, for
#                tb/gpu_top +SCENE=
#   make bench   FRAMES frames of MODEL (300 of sdk/sdcard/suzanne.glb), turning as gl_test turns
#                it, and their times
#   make clean   delete them
#
# sw_raster's SIMD (sw_simd.h): on an x86-64 host AVX2 with FMA, SW_SIMD_FLAGS; for another, after
# make clean, e.g. SW_SIMD_FLAGS=-DSW_RASTER_SIMD=1 (GCC's vector extensions, NEON's 4 lanes) or 0
# (none). An AArch64 host has NEON as it is.

CC = gcc
CXX = g++
GLM = ../../sdk/third_party/glm
FASTGLTF = ../../sdk/third_party/fastgltf
SIMDJSON = ../../sdk/third_party/simdjson/singleheader
STB = ../../sdk/third_party/stb
INCLUDES = -I../../sdk/lviv_gl -I../../sdk/gltf -I../../sdk/src -I../../sdk/include -I$(GLM) \
           -I$(FASTGLTF)/include -I$(SIMDJSON) -I$(STB)
CFLAGS = -O2 -std=c11 -Wall -Wextra $(INCLUDES)
# GLM as the board's applications build it (bd/gpu_test/Makefile): its SIMD code, SSE here
CXXFLAGS = -O2 -std=c++17 -Wall -Wextra -fno-exceptions -DGLM_FORCE_INTRINSICS -DGLM_FORCE_DEFAULT_ALIGNED_GENTYPES \
           $(INCLUDES)
# The glTF loader (sdk/gltf) on fastgltf and simdjson, patched or not: their patches change nothing
# on the host; its textures' images decoded by stb_image (SSE2 here). The frames' PNGs written by
# stb_image_write, in main.c.
OBJS = main.o sw_raster.o gl_api.o lviv_geom.o gltf_scene.o stb_image.o fastgltf.o base64.o io.o simdjson.o
HDRS = ../../sdk/lviv_gl/lviv_geom.h ../../sdk/lviv_gl/lviv_gl.h ../../sdk/gltf/gltf_scene.h ../../sdk/src/gpu.h \
       sw_raster.h sw_simd.h
ifneq ($(findstring x86_64,$(shell $(CC) -dumpmachine)),)
SW_SIMD_FLAGS = -mavx2 -mfma
ifeq ($(OS),Windows_NT)
# GCC's AVX code takes the stack as 32-byte aligned, which 64-bit Windows does not keep (GCC bug
# 54412): the assembler makes its aligned moves unaligned ones
SW_SIMD_FLAGS += -Wa,-muse-unaligned-vector-move
endif
endif
sw_raster.o: CFLAGS += $(SW_SIMD_FLAGS)
FRAMES = 300
MODEL = ../../sdk/sdcard/suzanne.glb
SUBMODULES = $(GLM)/glm/glm.hpp $(FASTGLTF)/include/fastgltf/core.hpp $(SIMDJSON)/simdjson.h $(STB)/stb_image.h
CHECK_SUBMODULES = $(foreach f,$(SUBMODULES),$(if $(wildcard $(f)),,$(error $(f) is missing: git submodule update --init)))
vpath %.c ../../sdk/lviv_gl ../../sdk/gltf
vpath %.cpp ../../sdk/lviv_gl ../../sdk/gltf $(FASTGLTF)/src $(SIMDJSON)

ifeq ($(OS),Windows_NT)
TEST = lviv_gl_test.exe
# The C++ runtime linked in: another libstdc++-6.dll first in the PATH (MSYS2's) would not start it
LDFLAGS = -static
RM_OUTPUTS = powershell -NoProfile -Command "Remove-Item -Force -ErrorAction SilentlyContinue $(TEST), suzanne_gltf.hex, *.o; exit 0"
else
TEST = lviv_gl_test
RM_OUTPUTS = rm -f $(TEST) suzanne_gltf.hex *.o
endif

all: $(TEST)

$(TEST): $(OBJS)
	$(CXX) $(OBJS) $(LDFLAGS) -lm -o $@

%.o: %.c $(HDRS)
	$(CHECK_SUBMODULES)
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.cpp $(HDRS)
	$(CHECK_SUBMODULES)
	$(CXX) $(CXXFLAGS) -c $< -o $@

scenes: $(TEST)
	$(abspath $(TEST)) ../../sdk/sdcard/suzanne.glb suzanne_gltf.hex

bench: $(TEST)
	$(abspath $(TEST)) $(MODEL) - $(FRAMES)

clean:
	$(RM_OUTPUTS)

.PHONY: all scenes bench clean
