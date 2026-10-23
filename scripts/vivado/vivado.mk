# Common Vivado setup shared by every Vivado flow (simulation, OOC synth/impl, top-level project).
# Defines tool paths, repo paths and portable mkdir/rm; adds no targets.
#
# Works on Windows (PowerShell/cmd/bash; PowerShell for mkdir/rm) and Linux.
# Override the install location with VIVADO_BIN=<vivado>/bin.

VIVADO_MK_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(VIVADO_MK_DIR)/../..)

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

VIVADO = $(VIVADO_BIN)/vivado$(TOOL_EXT)
XVLOG = $(VIVADO_BIN)/xvlog$(TOOL_EXT)
XVHDL = $(VIVADO_BIN)/xvhdl$(TOOL_EXT)
XELAB = $(VIVADO_BIN)/xelab$(TOOL_EXT)
XSIM = $(VIVADO_BIN)/xsim$(TOOL_EXT)

# Vitis of the same release, next to Vivado in the install (override with VITIS_BIN=<vitis>/bin).
VITIS_BIN ?= $(abspath $(VIVADO_BIN)/../../Vitis/bin)
VITIS = $(VITIS_BIN)/vitis$(TOOL_EXT)

# Xilinx IP configuration (FP units, DSP macro), used by both the simulation and synthesis flows.
XILINX_IPS_TCL = $(VIVADO_MK_DIR)/xilinx_ips.tcl

# Logs of every flow go next to the Makefile that runs it.
LOG_DIR = $(CURDIR)/logs
