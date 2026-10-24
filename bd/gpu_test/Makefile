# Block design with gpu_top's raster core on the ZCU104 (gpu_test_bd.tcl), the CPU driving it.
# Usage: make [project|gui|synth|impl|bitstream|xsa|export_bd|clean]
#        make [vitis|vitis_gui|vitis_build|vitis_clean]; see scripts/vivado/bd.mk.

BD_NAME = gpu_test
PART = xczu7ev-ffvc1156-2-e
BOARD_PART = xilinx.com:zcu104:part0:1.1
BD_TCL = gpu_test_bd.tcl
XDC = gpu_test.xdc

include ../gpu_top.mk
RTL = $(GPU_TOP_RTL)

# The Vitis application: the raster core's tests in sdk/raster_test, on the drivers in sdk/src.
VITIS_APP = raster_test
VITIS_APP_SRC = ../../sdk/src ../../sdk/raster_test
VITIS_APP_INCLUDES = ../../sdk/include

.DEFAULT_GOAL := project
include ../../scripts/vivado/bd.mk
