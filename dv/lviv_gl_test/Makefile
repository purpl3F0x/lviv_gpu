# lviv_gl on the host (gcc and g++; on Windows the ones raster_sw's g++ comes with), against
# dv/raster_sw. The GPU driver is replaced by the test's own gpu_frame, which writes the frame data.
#
#   make         build lviv_gl_test
#   make scenes  lviv_geom.hex (through lviv_geom, raster_sw's stream) and lviv_gl.hex (through the
#                GL API), in raster_sw's gpu_top scene format, for tb/gpu_top +SCENE=
#   make clean   delete them

CC = gcc
CXX = g++
GLM = ../../sdk/third_party/glm
INCLUDES = -I../../sdk/lviv_gl -I../../sdk/src -I../../sdk/include -I$(GLM)
CFLAGS = -O2 -std=c11 -Wall -Wextra $(INCLUDES)
# GLM as the board's applications build it (bd/gpu_test/Makefile): its SIMD code, SSE here
CXXFLAGS = -O2 -std=c++17 -Wall -Wextra -fno-exceptions -DGLM_FORCE_INTRINSICS -DGLM_FORCE_DEFAULT_ALIGNED_GENTYPES \
           $(INCLUDES)
OBJS = main.o gl_api.o lviv_geom.o
HDRS = ../../sdk/lviv_gl/lviv_geom.h ../../sdk/lviv_gl/lviv_gl.h ../../sdk/src/gpu.h \
       ../../sdk/include/models/suzanne.h
vpath %.c ../../sdk/lviv_gl
vpath %.cpp ../../sdk/lviv_gl

ifeq ($(OS),Windows_NT)
TEST = lviv_gl_test.exe
RM_OUTPUTS = powershell -NoProfile -Command "Remove-Item -Force -ErrorAction SilentlyContinue $(TEST), lviv_geom.hex, lviv_gl.hex, *.o; exit 0"
else
TEST = lviv_gl_test
RM_OUTPUTS = rm -f $(TEST) lviv_geom.hex lviv_gl.hex *.o
endif

all: $(TEST)

$(TEST): $(OBJS)
	$(CXX) $(OBJS) -lm -o $@

%.o: %.c $(HDRS)
	$(CC) $(CFLAGS) -c $< -o $@

%.o: %.cpp $(HDRS)
	$(if $(wildcard $(GLM)/glm/glm.hpp),,$(error $(GLM) is empty: git submodule update --init))
	$(CXX) $(CXXFLAGS) -c $< -o $@

scenes: $(TEST)
	$(abspath $(TEST)) geom lviv_geom.hex
	$(abspath $(TEST)) gl lviv_gl.hex

clean:
	$(RM_OUTPUTS)

.PHONY: all scenes clean
