# Shared Vivado xsim flow using the real Xilinx floating-point IP (no SIM_MODE behavioural models).
#
# Include from a tb's Makefile.vivado after setting RTL and the default goal, then give each
# target TOP, TB_SRCS and optionally SIM_ARGS (see tb/raster_frontend/Makefile.vivado).
#
#   build/vivado_ip/      IP sim models, generated once and shared by every tb
#   build/xsim/<tb>/      per-tb xsim work dir (xsim.dir, *.pb, *.jou, *.wdb)
#   <tb>/logs/            xvlog/xvhdl/xelab logs and one log per simulation top
#
# Works on Windows (PowerShell/cmd/bash; PowerShell for mkdir/rm) and Linux.

XSIM_MK_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(XSIM_MK_DIR)/../..)

ifeq ($(OS),Windows_NT)
VIVADO_BIN ?= C:/AMDDesignTools/2025.2/Vivado/bin
TOOL_EXT = .bat
MKDIR = powershell -NoProfile -Command "New-Item -ItemType Directory -Force -Path '$(1)' | Out-Null"
RMDIR = powershell -NoProfile -Command "Remove-Item -Recurse -Force -ErrorAction SilentlyContinue '$(1)'; exit 0"
else
VIVADO_BIN ?= /opt/Xilinx/Vivado/2025.2/bin
TOOL_EXT =
MKDIR = mkdir -p '$(1)'
RMDIR = rm -rf $(1)
endif

PART ?= xczu3eg-sbva484-1-e
VIVADO = $(VIVADO_BIN)/vivado$(TOOL_EXT)
XVLOG = $(VIVADO_BIN)/xvlog$(TOOL_EXT)
XVHDL = $(VIVADO_BIN)/xvhdl$(TOOL_EXT)
XELAB = $(VIVADO_BIN)/xelab$(TOOL_EXT)
XSIM = $(VIVADO_BIN)/xsim$(TOOL_EXT)

IP_DIR = $(REPO_ROOT)/build/vivado_ip
IP_TCL = $(XSIM_MK_DIR)/gen_sim_ips.tcl
IP_UNITS_TCL = $(XSIM_MK_DIR)/floatin_point_units.tcl
IP_STAMP = $(IP_DIR)/.generated
IP_SRCS = $(wildcard $(IP_DIR)/proj/sim_ips.gen/sources_1/ip/*/sim/*.vhd)
# Precompiled IP library mappings, taken from the exported elab options (expanded after IP generation).
IP_ELAB_OPTS = $(foreach opt,$(wildcard $(IP_DIR)/export/*/xsim/elab.opt),$(file <$(opt)))
IP_LIBS = $(sort $(patsubst -L:%,%,$(filter -L:%,$(subst -L ,-L:,$(IP_ELAB_OPTS)))))

TB_NAME := $(notdir $(CURDIR))
WORK_DIR = $(REPO_ROOT)/build/xsim/$(TB_NAME)
LOG_DIR = $(CURDIR)/logs
IP_COMPILED = $(WORK_DIR)/.ip_compiled

INCLUDES ?= -i $(REPO_ROOT)/rtl -i $(REPO_ROOT)/rtl/generated
SIM_ARGS ?=

.PHONY: ip compile run gui clean distclean

ip: $(IP_STAMP)

$(IP_STAMP): $(IP_TCL) $(IP_UNITS_TCL)
	$(call MKDIR,$(REPO_ROOT)/build)
	cd $(REPO_ROOT)/build && $(VIVADO) -mode batch -nojournal -nolog -source $(IP_TCL) -tclargs $(IP_DIR) $(PART)

$(IP_COMPILED): $(IP_STAMP)
	$(call MKDIR,$(WORK_DIR))
	$(call MKDIR,$(LOG_DIR))
	cd $(WORK_DIR) && $(XVHDL) --relax --work xil_defaultlib --log $(LOG_DIR)/xvhdl.log $(IP_SRCS) && echo compiled> .ip_compiled

compile: $(IP_COMPILED)
	$(call MKDIR,$(LOG_DIR))
	cd $(WORK_DIR) && $(XVLOG) -sv $(INCLUDES) --log $(LOG_DIR)/xvlog.log $(abspath $(RTL) $(TB_SRCS))
	cd $(WORK_DIR) && $(XELAB) -debug typical -relax $(addprefix -L ,$(IP_LIBS)) --log $(LOG_DIR)/xelab.log -s $(TOP)_snap $(TOP)

run: compile
	cd $(WORK_DIR) && $(XSIM) $(TOP)_snap -R --log $(LOG_DIR)/$(TOP).log $(SIM_ARGS)

gui: compile
	cd $(WORK_DIR) && $(XSIM) $(TOP)_snap -gui --log $(LOG_DIR)/$(TOP).log $(SIM_ARGS)

# Removes this tb's work dir and logs; the shared IP is kept.
clean:
	$(call RMDIR,$(WORK_DIR))
	$(call RMDIR,$(LOG_DIR))

# Also removes the shared generated IP (regenerated on next run, ~5 min).
distclean: clean
	$(call RMDIR,$(IP_DIR))
