# triangle_stream_adapter on its own, on Verilator (run in WSL): full rate, then gaps and
# back-pressure. STRIDE=128 for the 128-byte stride.
VERILATOR = verilator
OBJ_DIR   = obj_dir
STRIDE   ?= 96

RTL_SRCS = ../../rtl/gpu_types_pkg.sv \
           ../../rtl/axis_skid_buffer.sv \
           ../../rtl/generated/triangle_unpack.sv \
           ../../rtl/triangle_stream_adapter.sv
TB_SRCS  = tb_triangle_stream_adapter.sv
INCLUDES = -I../../rtl -I../../rtl/generated

VERILATOR_FLAGS = --binary --timing -j 0 --top-module tb_triangle_stream_adapter --Mdir $(OBJ_DIR) \
                  -Wno-WIDTH -GTRIANGLE_STRIDE=$(STRIDE)

.PHONY: all compile run clean

all: run

compile:
	$(VERILATOR) $(VERILATOR_FLAGS) $(INCLUDES) $(RTL_SRCS) $(TB_SRCS)

run: compile
	$(OBJ_DIR)/Vtb_triangle_stream_adapter

clean:
	rm -rf $(OBJ_DIR)
