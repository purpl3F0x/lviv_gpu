IVERILOG = iverilog
VVP      = vvp

SNAPSHOT = tb_sim

RTL_SRCS = ../../rtl/gpu_types_pkg.sv \
           ../../rtl/fp_wrappers.sv \
           ../../rtl/fp_cmp_le.sv \
		   ../../rtl/axis_skid_buffer.sv \
		   ../../rtl/delay_pipe.sv \
		   ../../rtl/fx_2_23_fma.sv \
		   ../../rtl/fx_2_23_mul.sv \
		   ../../rtl/fx_2_23_to_fx_2_8.sv \
		   ../../rtl/fx_9_8_fma.sv \
		   ../../rtl/fx_9_8_mul.sv \
		   ../../rtl/fx_9_8_to_u8.sv \
		   ../../rtl/thread.sv
TB_SRCS  = tb_thread.sv

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
