# Vivado project flow for a block design under bd/<name>/, and the Vitis workspace of its software.
#
# Include from its Makefile after setting BD_NAME, PART, BOARD_PART, RTL, BD_TCL and XDC, and for
# the Vitis targets VITIS_APPS (the applications' names), for each application <app>
# VITIS_APP_SRC_<app> (its source directories), VITIS_APP_INCLUDES_<app>,
# VITIS_APP_EXTERNAL_INCLUDES_<app> (libraries' include directories, such as git submodules: not
# listed) and VITIS_APP_LIBS_<app> (libraries it links, by name: m for libm), and for all of them
# VITIS_APP_OPTIMIZATION (-O0 to -Os, -O2 if not set) and VITIS_APP_CFLAGS (other compiler flags,
# for C and C++, which the link gets too).
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
#               the applications. Each builds its VITIS_APP_SRC_<app> where they are and lists
#               their .c, .cpp, .h and .hpp files and the headers of its VITIS_APP_INCLUDES_<app>
#               (again when one is added or removed); its include path is those and its
#               VITIS_APP_EXTERNAL_INCLUDES_<app> (an empty one stops it: a submodule not checked
#               out), it links its VITIS_APP_LIBS_<app>, and it is compiled with
#               VITIS_APP_OPTIMIZATION and VITIS_APP_CFLAGS, its C as C also next to C++ (all of it
#               set again when the Makefile or vitis_workspace.py changes)
#   vitis_gui   vitis, then open the workspace in the Vitis IDE
#   vitis_build vitis, then build the applications (<workspace>/<app>/build/<app>.elf);
#               vitis_build_<app> one of them
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
# newer XSA updates the platform); application $(1) lists its files, it built.
VITIS_STAMP = $(VITIS_WS)/.$(BD_NAME)_xsa
vitis_sources_stamp = $(VITIS_WS)/.$(1)_sources
vitis_built = $(VITIS_WS)/.$(1)_built
VITIS_SOURCES_STAMPS = $(foreach a,$(VITIS_APPS),$(call vitis_sources_stamp,$(a)))
VITIS_APP_OPTIMIZATION ?= -O2
# The design's Makefile and the script, which set the applications up: a change to either sets them
# up again.
VITIS_APP_SETUP := $(abspath $(firstword $(MAKEFILE_LIST))) $(VIVADO_MK_DIR)/vitis_workspace.py
# The directories application $(1)'s files are in, two levels down (include/generated/<Name>/): a
# file added or removed in one makes it newer than its sources stamp.
vitis_source_dirs = $(foreach d,$(abspath $(VITIS_APP_SRC_$(1)) $(VITIS_APP_INCLUDES_$(1))),\
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
VITIS_JSON_NAMES = [$(subst $(BD_SPACE),$(BD_COMMA) ,$(patsubst %,"%",$(1)))]
# Application $(1), then all of them, comma-separated
VITIS_APP_JSON = "$(1)": {"src": $(call VITIS_JSON_PATHS,$(VITIS_APP_SRC_$(1))), \
  "includes": $(call VITIS_JSON_PATHS,$(VITIS_APP_INCLUDES_$(1))), \
  "external_includes": $(call VITIS_JSON_PATHS,$(VITIS_APP_EXTERNAL_INCLUDES_$(1))), \
  "libs": $(call VITIS_JSON_NAMES,$(VITIS_APP_LIBS_$(1))), \
  "sources_stamp": "$(call vitis_sources_stamp,$(1))", "built": "$(call vitis_built,$(1))"}
VITIS_APPS_JSON = $(call VITIS_APP_JSON,$(firstword $(VITIS_APPS)))$(foreach a,$(wordlist 2,$(words $(VITIS_APPS)),$(VITIS_APPS)),$(BD_COMMA) $(call VITIS_APP_JSON,$(a)))
define VITIS_ARGS_JSON
{
  "workspace": "$(VITIS_WS)",
  "xsa": "$(XSA)",
  "platform": "$(VITIS_PLATFORM)",
  "cpu": "$(VITIS_CPU)",
  "domain": "$(VITIS_DOMAIN)",
  "stamp": "$(VITIS_STAMP)",
  "optimization": "$(VITIS_APP_OPTIMIZATION)",
  "cflags": "$(strip $(VITIS_APP_CFLAGS))",
  "apps": {$(VITIS_APPS_JSON)}
}
endef

VITIS_RUN = $(file >$(VITIS_ARGS),$(VITIS_ARGS_JSON))cd $(VITIS_WS) && $(VITIS) -s $(VIVADO_MK_DIR)/vitis_workspace.py $(VITIS_ARGS)

.PHONY: vitis vitis_gui vitis_build vitis_clean $(VITIS_APPS:%=vitis_build_%)
# One vitis run at a time: they share the workspace.
.NOTPARALLEL: vitis vitis_gui vitis_build

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

vitis: $(VITIS_SOURCES_STAMPS)

$(VITIS_STAMP): $(XSA) | $(VITIS_WS)
	$(VITIS_RUN) workspace
	$(call VITIS_CHECK,$@)

# Application $(1)'s files listed (the generated headers first, so they are listed too), and built.
define VITIS_APP_RULES
$(call vitis_sources_stamp,$(1)): $(VITIS_STAMP) $(VITIS_APP_SETUP) $(call vitis_source_dirs,$(1)) | $(VITIS_MISSING_HEADERS)
	$$(foreach d,$$(VITIS_APP_EXTERNAL_INCLUDES_$(1)),$$(if $$(wildcard $$(d)/*),,$$(error $$(d) is empty: git submodule update --init)))
	$$(VITIS_RUN) sources $(1)
	$$(call VITIS_CHECK,$$@)

vitis_build_$(1): $(call vitis_sources_stamp,$(1))
	$$(VITIS_RUN) build $(1)
	$$(call VITIS_CHECK,$(call vitis_built,$(1)))
endef
$(foreach a,$(VITIS_APPS),$(eval $(call VITIS_APP_RULES,$(a))))

vitis_build: $(VITIS_APPS:%=vitis_build_%)

vitis_gui: $(VITIS_SOURCES_STAMPS)
	cd $(VITIS_WS) && $(VITIS) -w $(VITIS_WS)

vitis_clean:
	$(call RMDIR,$(VITIS_WS))
	$(call RMDIR,$(VITIS_ARGS))
