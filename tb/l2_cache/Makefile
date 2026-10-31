# L2Cache on its own, on Verilator (run in WSL): four L1-like masters and a DDR model; every beat
# checked, the counters against the testbench's counts (tb_l2_cache.sv).
#   make run [STALL=<percent>] [RSTALL=<percent>] [CORE_NS=<ns>] [MEM_NS=<ns>] [AXIL_NS=<ns>]
#            [LAT_MIN=] [LAT_MAX=] [INTERLEAVE=0|1] [REQS=]
#                                                   one configuration (the testbench's defaults:
#                                                   30, 20, the target's clocks, 20..80, 1)
#   make regress                                    each of REGRESS
#   make [NO_L2=1] scene SCENE=<.hex> [SCENE_ARGS=] [SCENE_TAG=]
#                                                   gpu_top rendering a scene through the L2
#                                                   (tb_l2_scene.sv; SCENE from lviv_gl_test, its
#                                                   _textures.hex next to it), or without one
# The L2 is L2CacheConfig's defaults; tb_l2_cache's parameters must match them.
# L2Cache's own assertions end the simulation with $finish, so a run passes only on PASS.
VERILATOR = verilator
OBJ_DIR   = obj_dir

include ../../scripts/spinal.mk

RTL_SRCS = $(SPINAL_GEN_DIR)/L2Cache.v
TB_SRCS  = tb_l2_cache.sv

SIM_ARGS = $(if $(STALL),+STALL=$(STALL)) $(if $(RSTALL),+RSTALL=$(RSTALL)) \
           $(if $(CORE_NS),+CORE_NS=$(CORE_NS)) $(if $(MEM_NS),+MEM_NS=$(MEM_NS)) \
           $(if $(AXIL_NS),+AXIL_NS=$(AXIL_NS)) \
           $(if $(LAT_MIN),+LAT_MIN=$(LAT_MIN)) $(if $(LAT_MAX),+LAT_MAX=$(LAT_MAX)) \
           $(if $(INTERLEAVE),+INTERLEAVE=$(INTERLEAVE)) $(if $(REQS),+REQS=$(REQS))

# STALL:RSTALL:CORE_NS:MEM_NS:AXIL_NS:INTERLEAVE. The target's clocks (500 / 300 / 133 MHz),
# AXI-Lite at 100 MHz and faster than core, core slower than mem, all at 100 MHz; DDR and the
# L1s never, sometimes and mostly stalling; beats in order.
REGRESS = 0:0:2:3.333:7.5:1 30:20:2:3.333:7.5:1 80:60:2:3.333:10:1 30:20:2:3.333:7.5:0 \
          30:20:5:3.333:3:1 30:20:10:10:10:1 80:0:2:3.333:7.5:0

VERILATOR_FLAGS = --binary --timing -j 0 --top-module tb_l2_cache --Mdir $(OBJ_DIR) -Wno-WIDTH

.PHONY: all compile run regress clean

all: run

compile: $(filter $(SPINAL_VERILOG),$(RTL_SRCS))
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL_SRCS) $(TB_SRCS)

# The scene testbench: gpu_top's sources as tb/gpu_top's Makefile lists them
GPU_SRCS = ../../rtl/gpu_types_pkg.sv ../../rtl/int_modules.sv ../../rtl/delay_pipe.sv \
           ../../rtl/delay_pipe_fifo.sv ../../rtl/axis_skid_buffer.sv ../../rtl/sync_fifo.sv \
           ../../rtl/async_fifo.sv ../../rtl/fp_wrappers.sv $(SPINAL_GEN_DIR)/APBFrontendRegs.v \
           ../../rtl/raster_frontend.sv ../../rtl/orchestrator_alu.sv ../../rtl/thread_orchestrator.sv \
           ../../rtl/fp_depth_func.sv ../../rtl/fx_texture_interpolator.sv ../../rtl/fx_color_interpolator.sv \
           ../../rtl/fragment_shader.sv ../../rtl/blend_unit.sv ../../rtl/z_buffer_ram.sv \
           ../../rtl/texture_address_generator.sv ../../rtl/texture_cache.sv $(SPINAL_GEN_DIR)/ApbThreadRegs.v \
           ../../rtl/thread.sv ../../rtl/frame_buffer_ram.sv $(SPINAL_GEN_DIR)/ApbLutRam.v \
           ../../rtl/raster_core.sv $(SPINAL_GEN_DIR)/Axi4ToApbXbar.v $(SPINAL_GEN_DIR)/CommandProcessor.v \
           $(SPINAL_GEN_DIR)/ApbClockCrossing.v $(SPINAL_GEN_DIR)/AxiVisibilityDma.v \
           $(SPINAL_GEN_DIR)/AxiTileDma.v ../../rtl/generated/triangle_unpack.sv \
           ../../rtl/triangle_stream_adapter.sv ../../rtl/triangle_datamover.sv ../../rtl/gpu_top.sv
SCENE_L2   = $(if $(NO_L2),,$(RTL_SRCS))
SCENE_DIR  = obj_scene_$(if $(NO_L2),none,default)
SCENE_TAG ?= scene
SCENE_FLAGS = --binary --timing -j 0 --top-module tb_l2_scene --Mdir $(SCENE_DIR) -Wno-SHORTREAL -Wno-WIDTH \
              -I../../rtl -I../../rtl/generated $(if $(NO_L2),-DNO_L2)

.PHONY: scene_compile scene

scene_compile: $(filter $(SPINAL_VERILOG),$(GPU_SRCS) $(SCENE_L2))
	$(VERILATOR) $(SCENE_FLAGS) $(GPU_SRCS) $(SCENE_L2) tb_l2_scene.sv ../common/axi_ram.v \
	  ../../dv/common/dpi_functions.cpp

scene: scene_compile
	$(SCENE_DIR)/Vtb_l2_scene +SCENE=$(SCENE) +OUT=$(SCENE_DIR)/$(SCENE_TAG).tga $(SCENE_ARGS) \
	  | tee $(SCENE_DIR)/$(SCENE_TAG).log
	@grep -q '^RESULT' $(SCENE_DIR)/$(SCENE_TAG).log

run: compile
	$(OBJ_DIR)/Vtb_l2_cache $(SIM_ARGS) | tee $(OBJ_DIR)/run.log
	@grep -q '^PASS' $(OBJ_DIR)/run.log

regress: compile
	@for c in $(REGRESS); do \
	  set -- $$(echo $$c | tr : ' '); \
	  $(OBJ_DIR)/Vtb_l2_cache +STALL=$$1 +RSTALL=$$2 +CORE_NS=$$3 +MEM_NS=$$4 +AXIL_NS=$$5 \
	    +INTERLEAVE=$$6 | tee $(OBJ_DIR)/run.log; \
	  grep -q '^PASS' $(OBJ_DIR)/run.log || exit 1; \
	done

clean:
	rm -rf obj_dir obj_scene_*
