# Vivado xsim simulation flow using the real Xilinx floating-point IP (no SIM_MODE behavioural models).
#
# Include from a tb's Makefile.vivado after setting RTL and the default goal, then give each
# target TOP, TB_SRCS and optionally SIM_ARGS (see tb/raster_frontend/Makefile.vivado).
#
#   build/vivado_ip/      IP sim models, generated once and shared by every tb
#   build/xsim/<tb>/      per-tb xsim work dir (xsim.dir, *.pb, *.jou, *.wdb)
#   <tb>/logs/            xvlog/xvhdl/xelab logs and one log per simulation top

include $(dir $(lastword $(MAKEFILE_LIST)))vivado.mk

# Part only matters for IP generation; simulation results do not depend on it.
PART ?= xczu3eg-sbva484-1-e

IP_DIR = $(REPO_ROOT)/build/vivado_ip
IP_TCL = $(VIVADO_MK_DIR)/gen_sim_ips.tcl
IP_STAMP = $(IP_DIR)/.generated
# Both files are written by gen_sim_ips.tcl. Read them directly rather than globbing the IP
# folders: GNU make on Linux caches directory listings and misses files created mid-run.
IP_PRJ = $(IP_DIR)/ip_vhdl.prj
# Precompiled IP library mappings (expanded after IP generation).
IP_LIBS = $(file <$(IP_DIR)/ip_libs.txt)

TB_NAME := $(notdir $(CURDIR))
WORK_DIR = $(REPO_ROOT)/build/xsim/$(TB_NAME)
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
	cd $(WORK_DIR) && $(XVHDL) --relax --log $(LOG_DIR)/xvhdl.log -prj $(IP_PRJ) && echo compiled> .ip_compiled

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

# Also removes the shared generated IP (regenerated on next run, ~1-5 min).
distclean: clean
	$(call RMDIR,$(IP_DIR))
