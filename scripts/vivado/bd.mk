# Vivado project flow for a block design under bd/<name>/, and the Vitis workspace of its software.
#
# Include from its Makefile after setting BD_NAME, PART, BOARD_PART, RTL, BD_TCL and XDC, and for
# the Vitis targets VITIS_APP (name), VITIS_APP_SRC (its source directories) and VITIS_APP_INCLUDES.
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
#   vitis       the Vitis workspace build/vitis/<name>/: a platform from the XSA (made first when
#               missing, a red warning when out of date; given the new one after `make xsa`) and
#               the application, which builds VITIS_APP_SRC where they are and lists their .c and
#               .h files and the headers of VITIS_APP_INCLUDES (again when one is added or
#               removed); its include path is both
#   vitis_gui   vitis, then open the workspace in the Vitis IDE
#   vitis_build vitis, then build the application (<workspace>/<app>/build/<app>.elf)
#   vitis_clean delete the workspace
# synth, impl, bitstream and xsa skip runs that are complete and up to date. The SpinalHDL Verilog
# in RTL is made first (scripts/spinal.mk); the project refers to it where it is, so it is not
# recreated when that changes. The Vitis targets never run SpinalHDL, except to make the generated
# register map headers when they are missing.

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

# ---------------------------------------------------------------------------
# Vitis
# ---------------------------------------------------------------------------
VITIS_WS = $(REPO_ROOT)/build/vitis/$(BD_NAME)
# Short names: the BSP build nests about 200 characters below the workspace, and a Windows path
# that ends up over 260 fails the build.
VITIS_PLATFORM = $(BD_NAME)
VITIS_DOMAIN = standalone
VITIS_CPU ?= psu_cortexa53_0
# Written by vitis_workspace.py when a stage succeeds: the workspace is set up for the XSA (so a
# newer XSA updates the platform), the application lists its files, the application built.
VITIS_STAMP = $(VITIS_WS)/.$(BD_NAME)_xsa
VITIS_SOURCES_STAMP = $(VITIS_WS)/.$(VITIS_APP)_sources
VITIS_BUILT = $(VITIS_WS)/.$(VITIS_APP)_built
# The directories the application's files are in, two levels down (include/generated/<Name>/): a
# file added or removed in one makes it newer than the sources stamp.
VITIS_SOURCE_DIRS = $(foreach d,$(abspath $(VITIS_APP_SRC) $(VITIS_APP_INCLUDES)),\
                      $(d) $(patsubst %/,%,$(wildcard $(d)/*/ $(d)/*/*/)))
VITIS_ARGS = $(REPO_ROOT)/build/vitis/$(BD_NAME)_args.json
# The generated register map headers the application includes: made when missing (a fresh clone),
# otherwise left as `make xsa` last made them, matching the XSA.
VITIS_HEADERS = $(filter %.h,$(SPINAL_DOCS))
VITIS_MISSING_HEADERS = $(filter-out $(wildcard $(VITIS_HEADERS)),$(VITIS_HEADERS))

# vitis -s loses the script's exit code on Windows: fail when the stage's file is not there.
ifeq ($(OS),Windows_NT)
VITIS_CHECK = powershell -NoProfile -Command "if (-not (Test-Path '$(1)')) { Write-Host 'Vitis failed, see above'; exit 1 }"
else
VITIS_CHECK = test -f '$(1)'
endif

BD_COMMA := ,
BD_SPACE := $(subst ,, )
VITIS_JSON_PATHS = [$(subst $(BD_SPACE),$(BD_COMMA) ,$(patsubst %,"%",$(abspath $(1))))]
define VITIS_ARGS_JSON
{
  "workspace": "$(VITIS_WS)",
  "xsa": "$(XSA)",
  "platform": "$(VITIS_PLATFORM)",
  "cpu": "$(VITIS_CPU)",
  "domain": "$(VITIS_DOMAIN)",
  "app": "$(VITIS_APP)",
  "app_src": $(call VITIS_JSON_PATHS,$(VITIS_APP_SRC)),
  "app_includes": $(call VITIS_JSON_PATHS,$(VITIS_APP_INCLUDES)),
  "stamp": "$(VITIS_STAMP)",
  "sources_stamp": "$(VITIS_SOURCES_STAMP)",
  "built": "$(VITIS_BUILT)"
}
endef

VITIS_RUN = $(file >$(VITIS_ARGS),$(VITIS_ARGS_JSON))cd $(VITIS_WS) && $(VITIS) -s $(VIVADO_MK_DIR)/vitis_workspace.py $(VITIS_ARGS)

.PHONY: vitis vitis_gui vitis_build vitis_clean

# Set for processes VS Code starts; it turns the Vitis IDE (Electron) into plain Node, which exits.
unexport ELECTRON_RUN_AS_NODE

# Made only when it is missing; `make xsa` keeps it up to date. When it is older than what it is
# built from (the RTL, the constraints, the project's block design with the edits made in the GUI),
# the Vitis targets say so in red and go on with it. The SpinalHDL modules count by their Scala
# sources, so the Vitis targets never regenerate their Verilog: only the XSA needs it.
XSA_INPUTS = $(filter-out $(SPINAL_VERILOG),$(abspath $(RTL) $(XDC))) $(call spinal_sources,$(BD_SPINAL_VERILOG)) \
             $(wildcard $(BD_DIR)/$(BD_NAME).srcs/sources_1/bd/*/*.bd)
# $? is the inputs newer than the XSA.
XSA_OLD_BAR = ================================================================================
XSA_OLD_1 = WARNING: $(notdir $(XSA)) is out of date, older than:
XSA_OLD_2 = $(notdir $(wordlist 1,8,$?))$(if $(word 9,$?), and $(words $(wordlist 9,$(words $?),$?)) more)
XSA_OLD_3 = Vitis gets the hardware as it was. Run make xsa to rebuild it.
ifeq ($(OS),Windows_NT)
XSA_OLD_RED = Write-Host -ForegroundColor Red
XSA_OLD = powershell -NoProfile -Command "$(XSA_OLD_RED) '$(XSA_OLD_BAR)'; $(XSA_OLD_RED) '  $(XSA_OLD_1)'; $(XSA_OLD_RED) '    $(XSA_OLD_2)'; $(XSA_OLD_RED) '  $(XSA_OLD_3)'; $(XSA_OLD_RED) '$(XSA_OLD_BAR)'"
else
XSA_OLD = printf '\033[1;31m%s\033[0m\n' '$(XSA_OLD_BAR)' '  $(XSA_OLD_1)' '    $(XSA_OLD_2)' '  $(XSA_OLD_3)' '$(XSA_OLD_BAR)'
endif

$(XSA): $(XSA_INPUTS)
	$(if $(wildcard $@),@$(XSA_OLD),$(MAKE) xsa)

$(VITIS_WS):
	$(call MKDIR,$@)

vitis: $(VITIS_SOURCES_STAMP)

$(VITIS_STAMP): $(XSA) | $(VITIS_WS)
	$(VITIS_RUN) workspace
	$(call VITIS_CHECK,$@)

# The generated headers first, so they are listed too.
$(VITIS_SOURCES_STAMP): $(VITIS_STAMP) $(VITIS_SOURCE_DIRS) | $(VITIS_MISSING_HEADERS)
	$(VITIS_RUN) sources
	$(call VITIS_CHECK,$@)

vitis_build: $(VITIS_SOURCES_STAMP)
	$(VITIS_RUN) build
	$(call VITIS_CHECK,$(VITIS_BUILT))

vitis_gui: $(VITIS_SOURCES_STAMP)
	cd $(VITIS_WS) && $(VITIS) -w $(VITIS_WS)

vitis_clean:
	$(call RMDIR,$(VITIS_WS))
	$(call RMDIR,$(VITIS_ARGS))
