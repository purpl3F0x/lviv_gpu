
IVERILOG = iverilog
VVP = vvp
VERILATOR ?= verilator
RTL = ../../rtl/gpu_types_pkg.sv ../../rtl/int_modules.sv ../../rtl/delay_pipe.sv ../../rtl/delay_pipe_fifo.sv ../../rtl/axis_skid_buffer.sv ../../rtl/fp_wrappers.sv ../../rtl/generated/APBFrontendRegs.v ../../rtl/raster_frontend.sv
INCLUDES = -I../../rtl -I../../rtl/generated

VERILATOR_FLAGS ?= --lint-only --timing -Wall -Wno-fatal -Wno-MODMISSING
LINT_RTL = $(filter-out ../../rtl/generated/APBFrontendRegs.v,$(RTL))
LINT_INCLUDES = -I../../rtl

.PHONY: all simple csv lint clean

all: simple

lint:
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module raster_frontend $(LINT_INCLUDES) $(LINT_RTL)

simple:
	$(IVERILOG) -g2012 $(INCLUDES) -s tb_raster_frontend_smoke -o tb_simple $(RTL) tb_raster_frontend_smoke.sv
	$(VVP) tb_simple

csv:
	$(IVERILOG) -g2012 $(INCLUDES) -s tb_raster_frontend_csv -o tb_csv $(RTL) tb_raster_frontend_csv.sv
	$(VVP) tb_csv

clean:
	rm -f tb_simple tb_csv waves.vcd
