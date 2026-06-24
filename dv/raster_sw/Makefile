VERILATOR = verilator
VFLAGS = -Wall --cc --sv --exe --build -O3 --assert \
         -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNUSEDSIGNAL -Wno-UNDRIVEN -Wno-SHORTREAL -Wno-DECLFILENAME -Wno-TIMESCALEMOD \
         -Wno-SYNCASYNCNET -Wno-EOFNEWLINE -Wno-PINCONNECTEMPTY -Wno-IMPORTSTAR -Wno-VARHIDDEN -Wno-UNUSEDPARAM \
         -CFLAGS "-O3 -std=c++20 -fopenmp" \
         -LDFLAGS "-fopenmp" \
         +incdir+../../rtl \
         --top-module raster_frontend --prefix Vraster_core \
         -o ../build/rasterizer.exe

RTL_SRCS = ../../rtl/gpu_types_pkg.sv \
           ../../rtl/fp_wrappers.sv \
           ../../rtl/fp_min_max_2.sv \
           ../../rtl/fp_min_max_3.sv \
           ../../rtl/fp_rounding.sv \
           ../../rtl/fp_add_half_fast.sv \
           ../../rtl/tri_bb_min_max.sv \
           ../../rtl/int16_modules.sv \
           ../../rtl/raster_frontend.sv
APP_SRCS = main.cpp rasterizer.cpp geometry_engine.cpp

TARGET = build/rasterizer.exe

all: $(TARGET)

$(TARGET): $(APP_SRCS) $(RTL_SRCS)
	mkdir -p build
	$(VERILATOR) $(VFLAGS) $(APP_SRCS) $(RTL_SRCS)

clean:
	rm -rf build obj_dir

run: $(TARGET)
	./$(TARGET)
