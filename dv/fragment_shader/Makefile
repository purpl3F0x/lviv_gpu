VERILATOR = verilator

VFLAGS = -Wall --cc --sv --exe --build -O3 --assert \
         -Wno-WIDTHTRUNC -Wno-UNUSEDSIGNAL -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
         -Wno-SYNCASYNCNET -Wno-EOFNEWLINE -Wno-PINCONNECTEMPTY \
         -Wno-IMPORTSTAR -Wno-UNUSEDPARAM \
         -CFLAGS "-DVTOP=Vfragment_shader" \
         --trace --timing \
         +incdir+../verilaxi/tb \
         +incdir+../verilaxi/rtl \
         +incdir+../../rtl \
         -I../verilaxi/tb \
         -I../verilaxi/rtl \
         -I../../rtl \
         -I../../rtl \
         --top-module fragment_shader

VERILAXI_CPP = ../verilaxi/tb_cpp/sim_main.cpp

SRCS = ../../rtl/gpu_types_pkg.sv tb_fragment_shader.cpp ../../rtl/fragment_shader.sv

all: run

build:
	$(VERILATOR) $(VFLAGS) $(SRCS)

run: build
	obj_dir/Vfragment_shader

waves:
	obj_dir/Vfragment_shader --trace
	surfer waves.vcd

clean:
	rm -rf obj_dir ./waves.vcd
 