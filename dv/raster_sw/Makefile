CXX = g++
CXXFLAGS = -O3 -std=c++20 -march=native -Ilibs/xilinx_hls/include -Wno-deprecated-enum-enum-conversion -MMD -MP -fopenmp 

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
