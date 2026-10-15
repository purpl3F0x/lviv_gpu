
IVERILOG = iverilog
VVP = vvp
RTL = ../../rtl/gpu_types_pkg.sv ../../rtl/int_modules.sv ../../rtl/delay_pipe.sv ../../rtl/axis_skid_buffer.sv ../../rtl/fp_wrappers.sv ../../rtl/raster_frontend.sv
INCLUDES = -I../../rtl -I../../rtl/generated

.PHONY: all simple csv clean

all: simple

simple:
	$(IVERILOG) -g2012 $(INCLUDES) -s tb_raster_frontend_smoke -o tb_simple $(RTL) tb_raster_frontend_smoke.sv
	$(VVP) tb_simple

csv:
	$(IVERILOG) -g2012 $(INCLUDES) -s tb_raster_frontend_csv -o tb_csv $(RTL) tb_raster_frontend_csv.sv
	$(VVP) tb_csv

clean:
	rm -f tb_simple tb_csv waves.vcd
