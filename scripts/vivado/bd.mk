# Vivado project flow for a block design under bd/<name>/.
#
# Include from its Makefile after setting BD_NAME, PART, BOARD_PART, RTL, BD_TCL and XDC.
#
#   project     create the project in build/bd/<name>/ (once: edits made in the GUI stay in it;
#               `make clean project` rebuilds it from BD_TCL)
#   gui         open the project in the Vivado GUI
#   synth       synth_1
#   impl        impl_1 up to route_design
#   bitstream   impl_1 up to write_bitstream
#   xsa         bitstream, then build/bd/<name>/<name>.xsa (with the bitstream) for Vitis or PetaLinux
#   export_bd   write the block design, as it is now in the project, back to BD_TCL
#   clean       delete the project and the logs
# synth, impl, bitstream and xsa skip runs that are complete and up to date. The SpinalHDL Verilog
# in RTL is made first (scripts/spinal.mk); the project refers to it where it is, so it is not
# recreated when that changes.

include $(dir $(lastword $(MAKEFILE_LIST)))vivado.mk
include $(VIVADO_MK_DIR)/../spinal.mk

BD_DIR = $(REPO_ROOT)/build/bd/$(BD_NAME)
XPR = $(BD_DIR)/$(BD_NAME).xpr
XSA = $(BD_DIR)/$(BD_NAME).xsa
# Outside the project directory, which create_project -force may clear.
BD_ARGS = $(REPO_ROOT)/build/bd/$(BD_NAME)_args.tcl

# Passed to Vivado as a Tcl file so paths never go through cmd.exe argument splitting.
define BD_ARGS_TCL
set part $(PART)
set board_part $(BOARD_PART)
set proj_dir $(BD_DIR)
set proj_name $(BD_NAME)
set sources [list $(abspath $(RTL))]
set include_dirs [list $(REPO_ROOT)/rtl $(REPO_ROOT)/rtl/generated]
set bd_tcl $(abspath $(BD_TCL))
set xdc_files [list $(abspath $(XDC))]
set xsa $(XSA)
endef

# $(file) writes when make expands the recipe, so BD_DIR (and build/bd) comes from an order-only
# prerequisite, created before that.
define WRITE_BD_ARGS
$(file >$(BD_ARGS),$(BD_ARGS_TCL))
$(call MKDIR,$(LOG_DIR))
endef

.PHONY: project gui synth impl bitstream xsa export_bd clean

project: $(XPR)

BD_SPINAL_VERILOG = $(filter $(SPINAL_VERILOG),$(abspath $(RTL)))

$(BD_DIR):
	$(call MKDIR,$@)

# Only when it is missing, so the design edited in the GUI is never overwritten.
$(XPR): | $(BD_DIR) $(BD_SPINAL_VERILOG)
	$(WRITE_BD_ARGS)
	cd $(BD_DIR) && $(VIVADO) -mode batch -nojournal -log $(LOG_DIR)/create_$(BD_NAME).log -source $(VIVADO_MK_DIR)/bd_create.tcl -tclargs $(BD_ARGS)

gui: $(XPR)
	cd $(BD_DIR) && $(VIVADO) -mode gui -nojournal -log $(LOG_DIR)/gui_$(BD_NAME).log $(XPR)

synth impl bitstream xsa: $(BD_SPINAL_VERILOG)
synth impl bitstream xsa export_bd: $(XPR) | $(BD_DIR)
	$(WRITE_BD_ARGS)
	cd $(BD_DIR) && $(VIVADO) -mode batch -nojournal -log $(LOG_DIR)/$@_$(BD_NAME).log -source $(VIVADO_MK_DIR)/bd_flow.tcl -tclargs $(BD_ARGS) $@

clean:
	$(call RMDIR,$(BD_DIR))
	$(call RMDIR,$(BD_ARGS))
	$(call RMDIR,$(LOG_DIR))
