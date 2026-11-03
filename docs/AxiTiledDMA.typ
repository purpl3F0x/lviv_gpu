
#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": gruvbox, google
#import "utils/regspec.typ": reg_spec


#set page(paper: "a4")



= 2D Tiled DMA
#v(1em)

The *AxiTiledDMA* is a high-performance, low-footprint DMA engine specialized in executing 2D transfers from on-chip tile RAM to an AXI4 bus, designed to offload the tiled frame-buffer write-back. It operates across two asynchronous clock domains, a high-frequency tile memory domain (`ram_clk`) and a system interconnect domain (`aclk`), with the tile data crossing between them through a dual-clock FIFO.

The module reads a rendered tile ($128 times 128$ pixels at 32 bpp by default) from the per-thread tile RAMs (`tile_ram_N`), interleaves the threads' pixels back into frame lines and writes them directly into a linear frame buffer in DRAM through a write-only AXI4 master (`m_axi`). Each tile line is written as fixed-length bursts that never cross a 4 KiB boundary, and bursts are issued ahead of the data up to a configurable number of outstanding transactions. The tile RAM read latency is configurable, so the RAM output registers can be used to reduce routing pressure. Every word read is overwritten with `CLEAR_VALUE`, which leaves the tile RAM cleared for the next tile, and a separate CLEAR command fills the RAM on its own.

An APB3 slave (`s_apb`) allows runtime configuration of the 32/64-bit frame base address, the row byte stride and the frame size in tiles. With auto-advance, the core computes the target address of the current tile itself and then moves on to the next tile in raster order, so a whole frame is written with one START per tile. Interrupts signal tile completion, frame completion and AXI write errors.

The `m_axi` data width follows the number of pixels per beat (128 bits by default), while the other AXI parameters, such as burst length and number of outstanding transactions, are configurable.

#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/AxiTileDma.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "AxiTileDMA",
      h: auto, w: auto,
      ports-margins: (east: (5%, 5%),),
    )
  })
]

#v(2em)

== Performance

On a 128-bit AXI bus at 300 MHz the theoretical peak is 16 bytes per cycle, or 4.47 GiB/s. In practice the DMA sustains more than 4 GiB/s, close to that peak.

== Register Map
#v(1em)

#let data = json("../sdk/include/generated/AxiTileDma/axi_tile_dma_regmap.json")
#reg_spec(data)
