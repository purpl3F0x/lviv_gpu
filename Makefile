# Module schematics: `make <module>` elaborates the module in Vivado ("Open Elaborated Design")
# and exports its top-level schematic to build/schematic/<module>.svg.
# Uses the Vivado install from scripts/vivado/vivado.mk (override with VIVADO_BIN=...).
#
#   make list                       list the modules found under rtl/
#   make thread_orchestrator        build/schematic/thread_orchestrator.svg
#   make thread_orchestrator PART=xczu3eg-sbva484-1-e
#   make clean-schematic

include scripts/vivado/vivado.mk

PART ?= xczu7ev-ffvc1156-2-e
SCHEMATIC_DIR = $(REPO_ROOT)/build/schematic
PKG_SRCS := rtl/gpu_types_pkg.sv
RTL_SRCS := $(PKG_SRCS) $(filter-out $(PKG_SRCS),$(wildcard rtl/*.sv rtl/generated/*.v))

# Module names: the word after each `module` keyword in the RTL sources.
hash := \#
open_paren := (
src_words := $(foreach src,$(RTL_SRCS),$(file <$(src)))
word_pairs := $(join $(src_words),$(addprefix @@,$(wordlist 2,$(words $(src_words)),$(src_words))))
MODULES := $(sort $(foreach name,$(patsubst module@@%,%,$(filter module@@%,$(word_pairs))),\
             $(firstword $(subst $(open_paren), ,$(subst $(hash), ,$(subst ;, ,$(name)))))))

# Passed to Vivado as a Tcl file so paths never go through cmd.exe argument splitting.
define SCHEMATIC_ARGS_TCL
set part $(PART)
set top $(1)
set proj_dir $(SCHEMATIC_DIR)/$(1)
set svg $(SCHEMATIC_DIR)/$(1).svg
set sources [list $(abspath $(RTL_SRCS))]
set include_dirs [list $(REPO_ROOT)/rtl $(REPO_ROOT)/rtl/generated]
endef

.DEFAULT_GOAL := list
.PHONY: list clean-schematic $(MODULES)

list:
	@echo Modules: $(MODULES)
	@echo Usage: make MODULE  -  writes build/schematic/MODULE.svg

$(MODULES): %: $(SCHEMATIC_DIR)/%.svg

$(SCHEMATIC_DIR):
	$(call MKDIR,$@)

$(SCHEMATIC_DIR)/%.svg: $(RTL_SRCS) $(XILINX_IPS_TCL) $(VIVADO_MK_DIR)/schematic.tcl | $(SCHEMATIC_DIR)
	$(file >$(SCHEMATIC_DIR)/$*_args.tcl,$(call SCHEMATIC_ARGS_TCL,$*))
	cd $(SCHEMATIC_DIR) && $(VIVADO) -mode gui -nojournal -log $(SCHEMATIC_DIR)/$*.log -source $(VIVADO_MK_DIR)/schematic.tcl -tclargs $(SCHEMATIC_DIR)/$*_args.tcl

clean-schematic:
	$(call RMDIR,$(SCHEMATIC_DIR))
