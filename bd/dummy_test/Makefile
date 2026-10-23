# Block design to bring up gpu_top with dummy_core on the ZCU104 from the CPU (dummy_test_bd.tcl).
# Usage: make [project|gui|synth|impl|bitstream|xsa|export_bd|clean]
#        make [vitis|vitis_gui|vitis_build|vitis_clean]; see scripts/vivado/bd.mk.

BD_NAME = dummy_test
PART = xczu7ev-ffvc1156-2-e
BOARD_PART = xilinx.com:zcu104:part0:1.1
BD_TCL = dummy_test_bd.tcl
XDC = dummy_test.xdc

# gpu_top and everything below it, raster_core included so DUMMY_CORE can be switched off.
RTL = ../../rtl/gpu_types_pkg.sv \
      ../../rtl/int_modules.sv \
      ../../rtl/delay_pipe.sv \
      ../../rtl/delay_pipe_fifo.sv \
      ../../rtl/axis_skid_buffer.sv \
      ../../rtl/sync_fifo.sv \
      ../../rtl/async_fifo.sv \
      ../../rtl/fp_wrappers.sv \
      $(SPINAL_GEN_DIR)/APBFrontendRegs.v \
      ../../rtl/raster_frontend.sv \
      ../../rtl/orchestrator_alu.sv \
      ../../rtl/thread_orchestrator.sv \
      ../../rtl/fp_cmp_le.sv \
      ../../rtl/fx_texture_interpolator.sv \
      ../../rtl/fx_color_interpolator.sv \
      ../../rtl/fragment_shader.sv \
      ../../rtl/blend_unit.sv \
      ../../rtl/z_buffer_ram.sv \
      ../../rtl/texture_address_generator.sv \
      ../../rtl/texture_cache.sv \
      $(SPINAL_GEN_DIR)/ApbThreadRegs.v \
      ../../rtl/thread.sv \
      ../../rtl/frame_buffer_ram.sv \
      $(SPINAL_GEN_DIR)/ApbLutRam.v \
      ../../rtl/raster_core.sv \
      ../../rtl/dummy_core.sv \
      $(SPINAL_GEN_DIR)/Axi4ToApbXbar.v \
      $(SPINAL_GEN_DIR)/AxiVisibilityDma.v \
      $(SPINAL_GEN_DIR)/AxiTileDma.v \
      ../../rtl/generated/triangle_unpack.sv \
      ../../rtl/triangle_stream_adapter.sv \
      ../../rtl/triangle_datamover.sv \
      ../../rtl/gpu_top.sv \
      gpu_top_bd.v

# The Vitis application: the bring-up demo in sdk/.
VITIS_APP = gpu_demo
VITIS_APP_SRC = ../../sdk/src
VITIS_APP_INCLUDES = ../../sdk/include

.DEFAULT_GOAL := project
include ../../scripts/vivado/bd.mk
