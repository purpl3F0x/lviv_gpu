VERILATOR ?= verilator
IN_HALF_PERIOD ?= 10
.RECIPEPREFIX := >

ROOT_DIR := $(abspath ../..)
OBJ_DIR := $(CURDIR)/obj_dir
SV_SRCS := $(ROOT_DIR)/rtl/gpu_types_pkg.sv \
           $(ROOT_DIR)/rtl/fp_wrappers.sv \
           $(ROOT_DIR)/rtl/orchestrator_alu.sv \
           $(ROOT_DIR)/rtl/async_fifo.sv \
           $(ROOT_DIR)/rtl/sync_fifo.sv \
           $(ROOT_DIR)/rtl/thread_orchestrator.sv \
           $(CURDIR)/tb_thread_orchestrator.sv

.PHONY: compile run clean

compile:
>$(VERILATOR) --binary --timing --top-module tb_thread_orchestrator -GIN_HALF_PERIOD=$(IN_HALF_PERIOD) --Mdir $(OBJ_DIR) -Wno-SHORTREAL -Wno-WIDTH $(SV_SRCS) $(ROOT_DIR)/dv/common/dpi_functions.cpp

run: compile
>$(OBJ_DIR)/Vtb_thread_orchestrator

clean:
>rm -rf $(OBJ_DIR)