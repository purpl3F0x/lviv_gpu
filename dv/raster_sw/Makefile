CXX = g++
CXXFLAGS = -O3 -std=c++20 -march=native -Ilibs/xilinx_hls/include -I../../sdk/include -Wno-deprecated-enum-enum-conversion -MMD -MP -fopenmp

TARGET = build/rasterizer.exe
SRCS = main.cpp rasterizer.cpp geometry_engine.cpp
OBJS = $(patsubst %.cpp,build/%.o,$(SRCS))
DEPS = $(OBJS:.o=.d)

all: $(TARGET)

build:
	if not exist build mkdir build

build/%.o: %.cpp | build
	$(CXX) $(CXXFLAGS) -c $< -o $@

$(TARGET): $(OBJS) | build
	$(CXX) $(CXXFLAGS) $(OBJS) -o $(TARGET)

-include $(DEPS)

clean:
	rmdir /S /Q build

run: $(TARGET)
	$(subst /,\,$(TARGET))

# tb/gpu_top's scene (make run DUMMY=0 there): untextured, with its reference image.
gpu_top_scene: $(TARGET)
	$(subst /,\,$(TARGET)) --no-texture --gpu-top-scene gpu_top_scene.hex --ref-png gpu_top_ref.png
