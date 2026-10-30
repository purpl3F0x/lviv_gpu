# gpu_top and everything below it, and its block design wrapper (gpu_top_bd.v), for the Makefile of
# a block design in bd/<name>/ (the paths are from there).
GPU_TOP_RTL = ../../rtl/gpu_types_pkg.sv \
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
              ../../rtl/fp_depth_func.sv \
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
              $(SPINAL_GEN_DIR)/Axi4ToApbXbar.v \
              $(SPINAL_GEN_DIR)/CommandProcessor.v \
              $(SPINAL_GEN_DIR)/ApbClockCrossing.v \
              $(SPINAL_GEN_DIR)/AxiVisibilityDma.v \
              $(SPINAL_GEN_DIR)/AxiTileDma.v \
              ../../rtl/generated/triangle_unpack.sv \
              ../../rtl/triangle_stream_adapter.sv \
              ../../rtl/triangle_datamover.sv \
              ../../rtl/gpu_top.sv \
              ../gpu_top_bd.v
