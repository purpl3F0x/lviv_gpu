IVERILOG = iverilog
VVP      = vvp

SNAPSHOT = tb_sim

RTL_SRCS = ../../rtl/gpu_types_pkg.sv \
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
           ../../rtl/texture_cache.sv \
           ../../rtl/generated/ApbThreadRegs.v \
           ../../rtl/thread.sv
TB_SRCS  = tb_thread.sv ../common/axi_ram.v
INCLUDES = -I../../rtl -I../../rtl/generated

.PHONY: all compile run waves clean

all: run

compile: $(SNAPSHOT)

$(SNAPSHOT): $(RTL_SRCS) $(TB_SRCS)
	$(IVERILOG) -g2012 $(INCLUDES) -s tb_thread -o $(SNAPSHOT) $(RTL_SRCS) $(TB_SRCS)

run: $(SNAPSHOT)
	$(VVP) $(SNAPSHOT)

waves: $(SNAPSHOT)
	$(VVP) $(SNAPSHOT) +dump=1

clean:
	rm -f $(SNAPSHOT) waves.vcd
