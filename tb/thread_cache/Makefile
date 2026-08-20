IVERILOG = iverilog
VVP      = vvp

SNAPSHOT = tb_sim

RTL_SRCS = ../../rtl/gpu_types_pkg.sv \
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
           ../../rtl/texture_address_generator.sv \
           ../../rtl/texture_cache.sv \
           ../../rtl/z_buffer_ram.sv \
           ../../rtl/thread.sv \
           ../common/axi_ram.v

TB_SRCS = tb_thread_cache.sv

.PHONY: all compile run waves clean

all: run

compile: $(SNAPSHOT)

$(SNAPSHOT): $(RTL_SRCS) $(TB_SRCS)
	$(IVERILOG) -g2012 -o $(SNAPSHOT) $(RTL_SRCS) $(TB_SRCS)

run: $(SNAPSHOT)
	$(VVP) $(SNAPSHOT)

waves: $(SNAPSHOT)
	$(VVP) $(SNAPSHOT) +dump=1

clean:
	rm -f $(SNAPSHOT) waves.vcd