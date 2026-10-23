VERILATOR = verilator
RUN_ARGS ?=
include ../../scripts/spinal.mk
.RECIPEPREFIX := >

ROOT_DIR = $(abspath ../..)
RASTER_SW_DIR = $(ROOT_DIR)/dv/raster_sw
HLS_INCLUDE_DIR = $(RASTER_SW_DIR)/libs/xilinx_hls/include

BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj_dir

TOP = thread_verilator_wrap
TARGET = $(BUILD_DIR)/rasterizer_thread.exe

SV_SRCS = verilator.vlt \
          ../../rtl/gpu_types_pkg.sv \
          thread_verilator_wrap.sv \
          ../../tb/common/axi_ram.v \
          ../../rtl/fp_wrappers.sv \
          ../../rtl/fp_cmp_le.sv \
          ../../rtl/axis_skid_buffer.sv \
          ../../rtl/delay_pipe.sv \
          ../../rtl/fx_texture_interpolator.sv \
          ../../rtl/fx_color_interpolator.sv \
          ../../rtl/fragment_shader.sv \
          ../../rtl/blend_unit.sv \
          ../../rtl/z_buffer_ram.sv \
          ../../rtl/texture_address_generator.sv \
          $(SPINAL_GEN_DIR)/ApbLutRam.v \
          $(SPINAL_GEN_DIR)/ApbThreadRegs.v \
          ../../rtl/texture_cache.sv \
          ../../rtl/thread.sv

CPP_SRCS = ../../dv/raster_sw/main.cpp \
           ../../dv/raster_sw/geometry_engine.cpp \
           ../../dv/raster_sw/rasterizer.cpp \
           ../../dv/common/dpi_functions.cpp \
           thread_rasterizer.cpp

VERILATOR_CFLAGS = --CFLAGS -std=c++20 \
                   --CFLAGS -O2 \
                   --CFLAGS -DRASTERIZER_EXTERNAL_RASTERIZE_TRIANGLE \
                   --CFLAGS -I$(RASTER_SW_DIR) \
                   --CFLAGS -I$(HLS_INCLUDE_DIR) \
                   --CFLAGS -I$(ROOT_DIR)/sdk/include \
                   --CFLAGS -Wno-deprecated-enum-enum-conversion

VERILATOR_WARNINGS = -Wno-SHORTREAL
VERILATOR_INCLUDES = -I../../rtl/generated

.PHONY: all compile run clean

all: compile

compile: $(filter $(SPINAL_VERILOG),$(SV_SRCS))
>mkdir -p $(BUILD_DIR) && mkdir -p $(OBJ_DIR) && $(VERILATOR) --cc --exe --build --top-module $(TOP) --Mdir $(OBJ_DIR) -o rasterizer_thread $(VERILATOR_INCLUDES) $(SV_SRCS) $(CPP_SRCS) $(VERILATOR_WARNINGS) $(VERILATOR_CFLAGS)

run: compile
>$(OBJ_DIR)/rasterizer_thread $(RUN_ARGS)

clean:
>rm -rf $(BUILD_DIR)
