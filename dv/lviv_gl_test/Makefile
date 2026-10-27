# lviv_gl on the host (gcc and g++; on Windows the ones raster_sw's g++ comes with), against
# dv/raster_sw. The GPU driver is replaced by the test's own gpu_frame, which writes the frame data.
#
#   make         build lviv_gl_test
#   make scenes  lviv_geom.hex (through lviv_geom, raster_sw's stream) and lviv_gl.hex (through the
#                GL API) of raster_sw's objs/suzanne.obj, and suzanne_gltf.hex
#                (sdk/sdcard/suzanne.glb, as gl_test draws it), in raster_sw's gpu_top scene
#                format, for tb/gpu_top +SCENE=
#   make clean   delete them

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
# on the host; its textures' images decoded by stb_image (SSE2 here)
OBJS = main.o gl_api.o lviv_geom.o gltf_scene.o stb_image.o fastgltf.o base64.o io.o simdjson.o
HDRS = ../../sdk/lviv_gl/lviv_geom.h ../../sdk/lviv_gl/lviv_gl.h ../../sdk/gltf/gltf_scene.h ../../sdk/src/gpu.h
SUBMODULES = $(GLM)/glm/glm.hpp $(FASTGLTF)/include/fastgltf/core.hpp $(SIMDJSON)/simdjson.h $(STB)/stb_image.h
CHECK_SUBMODULES = $(foreach f,$(SUBMODULES),$(if $(wildcard $(f)),,$(error $(f) is missing: git submodule update --init)))
vpath %.c ../../sdk/lviv_gl ../../sdk/gltf
vpath %.cpp ../../sdk/lviv_gl ../../sdk/gltf $(FASTGLTF)/src $(SIMDJSON)

ifeq ($(OS),Windows_NT)
TEST = lviv_gl_test.exe
# The C++ runtime linked in: another libstdc++-6.dll first in the PATH (MSYS2's) would not start it
LDFLAGS = -static
RM_OUTPUTS = powershell -NoProfile -Command "Remove-Item -Force -ErrorAction SilentlyContinue $(TEST), lviv_geom.hex, lviv_gl.hex, suzanne_gltf.hex, *.o; exit 0"
else
TEST = lviv_gl_test
RM_OUTPUTS = rm -f $(TEST) lviv_geom.hex lviv_gl.hex suzanne_gltf.hex *.o
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
	$(abspath $(TEST)) geom ../raster_sw/objs/suzanne.obj lviv_geom.hex
	$(abspath $(TEST)) gl ../raster_sw/objs/suzanne.obj lviv_gl.hex
	$(abspath $(TEST)) gltf ../../sdk/sdcard/suzanne.glb suzanne_gltf.hex

clean:
	$(RM_OUTPUTS)

.PHONY: all scenes clean
