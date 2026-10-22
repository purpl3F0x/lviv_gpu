# Verilator (make, make run) and Icarus (make icarus) run the same SystemVerilog testbench.
IVERILOG  = iverilog
VVP       = vvp
VERILATOR = verilator

include ../../scripts/spinal.mk

SNAPSHOT = tb_sim
OBJ_DIR  = obj_dir

RTL_SRCS = ../../rtl/gpu_types_pkg.sv \
           ../../rtl/int_modules.sv \
           ../../rtl/delay_pipe.sv \
           ../../rtl/delay_pipe_fifo.sv \
           ../../rtl/axis_skid_buffer.sv \
           ../../rtl/fp_wrappers.sv \
           $(SPINAL_GEN_DIR)/APBFrontendRegs.v \
           ../../rtl/raster_frontend.sv \
           ../../rtl/async_fifo.sv \
           ../../rtl/sync_fifo.sv \
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
           ../../rtl/raster_core.sv
TB_SRCS  = tb_raster_core.sv ../common/axi_ram.v
INCLUDES = -I../../rtl -I../../rtl/generated

MAGICK  = magick

INPUTS  ?= ../../dv/raster_sw/raster_core_inputs.csv
# Any image ImageMagick reads (square, a power of two, up to 256 x 256) becomes texture.tga here.
TEXTURE_SRC ?= ../../dv/raster_sw/texture_64x64.jpg
TEXTURE  = texture.tga
OUT     ?= raster_core.tga
PNG      = $(OUT:.tga=.png)
SIM_ARGS = +INPUTS=$(INPUTS) +TEXTURE=$(TEXTURE) +OUT=$(OUT)

# --binary generates main(); the only C++ is the FP bit-conversion DPI that fp_wrappers imports.
DPI_SRCS = ../../dv/common/dpi_functions.cpp
VERILATOR_FLAGS = --binary --timing -j 0 --top-module tb_raster_core --Mdir $(OBJ_DIR) \
                  -Wno-SHORTREAL -Wno-WIDTH

.PHONY: all compile run icarus_compile icarus png clean

all: run

# Verilator
compile: $(filter $(SPINAL_VERILOG),$(RTL_SRCS))
	$(VERILATOR) $(VERILATOR_FLAGS) $(INCLUDES) $(RTL_SRCS) $(TB_SRCS) $(DPI_SRCS)

run: compile $(TEXTURE)
	$(OBJ_DIR)/Vtb_raster_core $(SIM_ARGS)
	$(MAKE) png

# Icarus
icarus_compile: $(SNAPSHOT)

$(SNAPSHOT): $(RTL_SRCS) $(TB_SRCS)
	$(IVERILOG) -g2012 $(INCLUDES) -s tb_raster_core -o $(SNAPSHOT) $(RTL_SRCS) $(TB_SRCS)

icarus: $(SNAPSHOT) $(TEXTURE)
	$(VVP) -n $(SNAPSHOT) $(SIM_ARGS)
	$(MAKE) png

# Uncompressed 32-bit TGA; an image without alpha gets an opaque one, as stbi_load(..., 4) gives.
$(TEXTURE): $(TEXTURE_SRC)
	$(MAGICK) $< -alpha set -depth 8 -compress none $@

# Convert the last frame without re-running the simulation.
png:
	$(MAGICK) $(OUT) $(PNG)

clean:
	rm -rf $(SNAPSHOT) $(OBJ_DIR) $(OUT) $(PNG) $(TEXTURE)
