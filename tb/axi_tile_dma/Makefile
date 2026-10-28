# AxiTileDma on its own, on Verilator (run in WSL): its tile RAMs four frame_buffer_ram, DRAM an AXI
# slave that stalls at random; every pixel and burst checked (tb_axi_tile_dma.sv).
#   make run [STALL=<percent>] [ACLK_NS=<ns>] [RAM_NS=<ns>]   one configuration (the testbench's
#                                                            defaults: 30, the board's clocks)
#   make regress                                             each of REGRESS
VERILATOR = verilator
OBJ_DIR   = obj_dir

include ../../scripts/spinal.mk

RTL_SRCS = ../../rtl/frame_buffer_ram.sv \
           $(SPINAL_GEN_DIR)/AxiTileDma.v
TB_SRCS  = tb_axi_tile_dma.sv

SIM_ARGS = $(if $(STALL),+STALL=$(STALL)) $(if $(ACLK_NS),+ACLK_NS=$(ACLK_NS)) \
           $(if $(RAM_NS),+RAM_NS=$(RAM_NS))

# STALL:ACLK_NS:RAM_NS. The board's clocks (300 MHz, drifting), the target's (ram_clk 500 MHz),
# ram_clk faster than aclk, slower; DRAM never, sometimes and mostly stalling.
REGRESS = 0:3.334:3.332 30:3.334:3.332 80:3.334:3.332 0:3.334:2 30:3.334:2 80:3.334:2 0:10:7 \
          30:10:7 30:10:13 80:10:13

VERILATOR_FLAGS = --binary --timing -j 0 --top-module tb_axi_tile_dma --Mdir $(OBJ_DIR) -Wno-WIDTH

.PHONY: all compile run regress clean

all: run

compile: $(filter $(SPINAL_VERILOG),$(RTL_SRCS))
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL_SRCS) $(TB_SRCS)

run: compile
	$(OBJ_DIR)/Vtb_axi_tile_dma $(SIM_ARGS)

regress: compile
	@for c in $(REGRESS); do \
	  set -- $$(echo $$c | tr : ' '); \
	  $(OBJ_DIR)/Vtb_axi_tile_dma +STALL=$$1 +ACLK_NS=$$2 +RAM_NS=$$3 || exit 1; \
	done

clean:
	rm -rf $(OBJ_DIR)
