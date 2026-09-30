VERILATOR = verilator
RUN_ARGS ?=
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
          ../../rtl/fx_texture_mul.sv \
          ../../rtl/fx_texture_fma.sv \
          ../../rtl/fx_color_mul.sv \
          ../../rtl/fx_color_fma.sv \
          ../../rtl/fx_color_to_u8.sv \
          ../../rtl/fragment_shader.sv \
          ../../rtl/blend_unit.sv \
          ../../rtl/z_buffer_ram.sv \
          ../../rtl/texture_address_generator.sv \
          ../../rtl/generated/ApbLutRam.v \
          ../../rtl/texture_cache.sv \
          ../../rtl/thread.sv

CPP_SRCS = ../../dv/raster_sw/main.cpp \
           ../../dv/raster_sw/geometry_engine.cpp \
           ../../dv/raster_sw/rasterizer.cpp \
           ../../dv/raster_core/dpi_functions.cpp \
           thread_rasterizer.cpp

VERILATOR_CFLAGS = --CFLAGS -std=c++20 \
                   --CFLAGS -O2 \
                   --CFLAGS -DRASTERIZER_EXTERNAL_RASTERIZE_TRIANGLE \
                   --CFLAGS -I$(RASTER_SW_DIR) \
                   --CFLAGS -I$(HLS_INCLUDE_DIR) \
                   --CFLAGS -Wno-deprecated-enum-enum-conversion

VERILATOR_WARNINGS = -Wno-SHORTREAL

.PHONY: all compile run clean

all: compile

compile:
>mkdir -p $(BUILD_DIR) && mkdir -p $(OBJ_DIR) && $(VERILATOR) --cc --exe --build --top-module $(TOP) --Mdir $(OBJ_DIR) -o rasterizer_thread $(SV_SRCS) $(CPP_SRCS) $(VERILATOR_WARNINGS) $(VERILATOR_CFLAGS)

run: compile
>$(OBJ_DIR)/rasterizer_thread $(RUN_ARGS)

clean:
>rm -rf $(BUILD_DIR)
