# gpu_top with dummy_core, on Verilator (run in WSL). The DataMover is its simulation model.
VERILATOR = verilator
MAGICK    = magick
OBJ_DIR   = obj_dir

include ../../scripts/spinal.mk

RTL_SRCS = ../../rtl/gpu_types_pkg.sv \
           ../../rtl/int_modules.sv \
           ../../rtl/delay_pipe.sv \
           ../../rtl/delay_pipe_fifo.sv \
           ../../rtl/axis_skid_buffer.sv \
           ../../rtl/sync_fifo.sv \
           ../../rtl/async_fifo.sv \
           ../../rtl/fp_wrappers.sv \
           $(SPINAL_GEN_DIR)/APBFrontendRegs.v \
           ../../rtl/raster_frontend.sv \
           ../../rtl/orchestrator_alu.sv \
           ../../rtl/thread_orchestrator.sv \
           ../../rtl/fp_cmp_le.sv \
           ../../rtl/fx_texture_interpolator.sv \
           ../../rtl/fx_color_interpolator.sv \
           ../../rtl/fragment_shader.sv \
           ../../rtl/blend_unit.sv \
           ../../rtl/z_buffer_ram.sv \
           ../../rtl/texture_address_generator.sv \
           ../../rtl/texture_cache.sv \
           $(SPINAL_GEN_DIR)/ApbThreadRegs.v \
           ../../rtl/thread.sv \
           ../../rtl/frame_buffer_ram.sv \
           $(SPINAL_GEN_DIR)/ApbLutRam.v \
           ../../rtl/raster_core.sv \
           ../../rtl/dummy_core.sv \
           $(SPINAL_GEN_DIR)/Axi4ToApbXbar.v \
           $(SPINAL_GEN_DIR)/AxiVisibilityDma.v \
           $(SPINAL_GEN_DIR)/AxiTileDma.v \
           ../../rtl/generated/triangle_unpack.sv \
           ../../rtl/triangle_stream_adapter.sv \
           ../../rtl/triangle_datamover.sv \
           ../../rtl/gpu_top.sv
TB_SRCS  = tb_gpu_top.sv ../common/axi_ram.v
DPI_SRCS = ../../dv/common/dpi_functions.cpp
INCLUDES = -I../../rtl -I../../rtl/generated

OUT ?= gpu_top.tga
PNG  = $(OUT:.tga=.png)

VERILATOR_FLAGS = --binary --timing -j 0 --top-module tb_gpu_top --Mdir $(OBJ_DIR) \
                  -Wno-SHORTREAL -Wno-WIDTH

.PHONY: all compile run png clean

all: run

compile: $(filter $(SPINAL_VERILOG),$(RTL_SRCS))
	$(VERILATOR) $(VERILATOR_FLAGS) $(INCLUDES) $(RTL_SRCS) $(TB_SRCS) $(DPI_SRCS)

run: compile
	$(OBJ_DIR)/Vtb_gpu_top +OUT=$(OUT)
	$(MAKE) png

png:
	$(MAGICK) $(OUT) $(PNG)

clean:
	rm -rf $(OBJ_DIR) $(OUT) $(PNG)
