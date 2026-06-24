VERILATOR = verilator

VFLAGS = -Wall --cc --sv --exe --build -O3 --assert \
         -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-SHORTREAL -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
         -Wno-SYNCASYNCNET -Wno-EOFNEWLINE -Wno-PINCONNECTEMPTY -Wno-IMPORTSTAR -Wno-VARHIDDEN -Wno-UNUSEDPARAM \
         -CFLAGS "-DVTOP=Vraster_core" \
         --trace-fst --timing \
         +incdir+../../rtl \
         -I../../rtl \
         --top-module raster_frontend --prefix Vraster_core

SRCS = tb_raster_core.cpp \
       ../../rtl/gpu_types_pkg.sv \
       ../../rtl/fp_wrappers.sv \
       ../../rtl/fp_min_max_2.sv \
       ../../rtl/fp_min_max_3.sv \
       ../../rtl/fp_rounding.sv \
       ../../rtl/fp_add_half_fast.sv \
       ../../rtl/tri_bb_min_max.sv \
       ../../rtl/int16_modules.sv \
       ../../rtl/raster_frontend.sv \
       ../../rtl/raster_core.sv

VFLAGS_TOP = -Wall --binary --sv -O3 --assert \
             -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-SHORTREAL -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
             -Wno-SYNCASYNCNET -Wno-EOFNEWLINE -Wno-PINCONNECTEMPTY -Wno-IMPORTSTAR -Wno-VARHIDDEN -Wno-UNUSEDPARAM \
             --trace-fst --timing \
             +incdir+../../rtl \
             -I../../rtl \
             --top-module tb_raster_core_top

SRCS_TOP = ../../rtl/gpu_types_pkg.sv ../../rtl/fp_wrappers.sv ../../rtl/thread_orchestrator.sv ../../rtl/raster_core.sv tb_raster_core_top.sv dpi_functions.cpp

all: run run_top

build:
	$(VERILATOR) $(VFLAGS) $(SRCS)

run: build
	obj_dir/Vraster_core

run_top:
	$(VERILATOR) $(VFLAGS_TOP) $(SRCS_TOP)
	obj_dir/Vtb_raster_core_top

waves:
	obj_dir/Vraster_core --trace
	surfer waves.fst

clean:
	rm -rf obj_dir ./waves.fst ./dump.vcd ./waves.vcd
