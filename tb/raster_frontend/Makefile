
# Tool commands
IVERILOG = iverilog
VVP      = vvp

# Simulation binary name
SNAPSHOT = tb_sim

# Source files
RTL_SRCS = ../../rtl/gpu_types_pkg.sv ../../rtl/fp_rounding.sv ../../rtl/fp_wrappers.sv ../../rtl/fp_add_half_fast.sv ../../rtl/tri_bb_min_max.sv ../../rtl/raster_frontend.sv ../../rtl/fp_min_max_3.sv ../../rtl/fp_min_max_2.sv  
TB_SRCS  = tb_raster_frontend_simple.sv

.PHONY: all compile run waves clean

# Default target
all: run

# 1. Compilation
compile: $(SNAPSHOT)

$(SNAPSHOT): $(RTL_SRCS) $(TB_SRCS)
	$(IVERILOG) -g2012 -o $(SNAPSHOT) $(RTL_SRCS) $(TB_SRCS)

# 2. Execution
run: $(SNAPSHOT)
	$(VVP) $(SNAPSHOT)

# 3. Waveform Generation
waves: $(SNAPSHOT)
	$(VVP) $(SNAPSHOT) +dump

# 4. Cleanup
clean:
	rm -f $(SNAPSHOT) waves.vcd
