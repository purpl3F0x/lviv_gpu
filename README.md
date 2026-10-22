# LVIV GPU

A work-in-progress FPGA GPU in SystemVerilog, with a C++ reference rasterizer.

## Block Diagram
<p align="center">
<img src="raster_core_block_diagram.svg" alt="Raster core block diagram" style="width:100%;max-width: 400px">
</p>

## Rendering Demo

<img src="rendering_animation.gif">

## Layout

| Directory | Contents |
| --- | --- |
| `rtl/` | Hardware and generated pipelines |
| `rtl/spinalhdl/` | SpinalHDL sources of the register blocks, crossbar and DMAs |
| `scripts/` | Pipeline generators and Vivado scripts |
| `tb/` | Testbenches |
| `dv/raster_sw/` | C++ reference and CSV vectors |
| `docs/` | Design notes and diagrams |


## Tools needed
 - Python 3 with [ortools](https://pypi.org/project/ortools/)
 - [sbt](https://www.scala-sbt.org/) and JDK 11+ (SpinalHDL modules)
 - Vivado (tested on2025.2)
 - Verilator 5
 - ImageMagick