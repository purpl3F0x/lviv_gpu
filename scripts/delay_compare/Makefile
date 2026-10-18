# Delay line comparison: synthesizes delay_pipe (shift registers) and delay_pipe_fifo (dual and
# single pointer) out of context for each WIDTHxSTAGES config and prints LUT / LUTRAM / SRL / FF use.
#
# Usage: make [CONFIGS="461x11 309x51"] [IN_REG=1] [PERIOD=1.4] [PART=...]
#   CONFIGS  list of WIDTHxSTAGES, STAGES = delay in cycles (as in both modules)
#   IN_REG   input register of delay_pipe_fifo
# Output and CSV in build/delay_compare, Vivado log in build/delay_compare/compare.log.

SCRIPT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
include $(SCRIPT_DIR)/../vivado/vivado.mk

# Default: the thread orchestrator passthrough delay line (PipeLatency = 11).
CONFIGS ?= 461x11
IN_REG ?= 1
PERIOD ?= 1.4
PART ?= xczu7ev-ffvc1156-2-e

OUT_DIR = $(REPO_ROOT)/build/delay_compare
ARGS = $(OUT_DIR)/args.tcl

# Passed to Vivado as a Tcl file so paths never go through cmd.exe argument splitting.
define ARGS_TCL
set part $(PART)
set period $(PERIOD)
set in_reg $(IN_REG)
set configs {$(CONFIGS)}
set sources [list $(REPO_ROOT)/rtl/delay_pipe.sv $(REPO_ROOT)/rtl/delay_pipe_fifo.sv $(SCRIPT_DIR)/delay_pipe_top.sv]
set out_dir $(OUT_DIR)
endef

.PHONY: run clean
.DEFAULT_GOAL := run

$(OUT_DIR):
	$(call MKDIR,$@)

run: | $(OUT_DIR)
	$(file >$(ARGS),$(ARGS_TCL))
	cd $(OUT_DIR) && $(VIVADO) -mode batch -nojournal -log $(OUT_DIR)/compare.log -source $(SCRIPT_DIR)/compare.tcl -tclargs $(ARGS)

clean:
	$(call RMDIR,$(OUT_DIR))
