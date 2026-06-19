
# Tool commands
IVERILOG = iverilog
VVP      = vvp

# Simulation binary name
SNAPSHOT = tb_sim

# Source files
RTL_SRCS = ../../rtl/fp_min_max_3.sv
TB_SRCS  = tb_fp_min_max_3.sv

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
