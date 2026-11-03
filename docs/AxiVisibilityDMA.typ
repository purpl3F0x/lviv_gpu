#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/regspec.typ": reg_spec


#set page(paper: "a4")



= Visibility DMA
#v(1em)

The *AxiVisibilityDMA* is a DMA command engine that builds the triangle stream of a tile from the frame's visibility buffer, designed to offload the per-tile triangle selection. The visibility buffer holds one 64-bit word per triangle, with one bit per tile of the frame. For the active tile, the engine reads the buffer through a read-only AXI4 master (`m_axi_vb`), picks that tile's bit out of every word and filters two triangles per clock (600 Mtri/s at 300 MHz).

Consecutive visible triangles are merged into runs, and each run becomes a single command for an AMD AXI DataMover (`m_axis_datamover_cmd`), which fetches the triangles' geometry (96 B each by default) from memory and streams it to the raster core. A run is only split when it reaches the per-command limit set in `BTT_LIMIT` or the DataMover's byte count. The engine counts the status responses on `s_axis_datamover_sts` and finishes the tile once every command has been acknowledged, flagging AXI read errors and DataMover status errors.

Visibility reads are split into bursts that never cross a 4 KiB boundary, with a configurable number of outstanding reads, and a decoupling FIFO absorbs whole bursts. The DataMover command and status streams can run on their own clock, through dual-clock FIFOs, or on the engine's clock.

An APB3 slave (`s_apb`) allows runtime configuration of the 32/64-bit visibility buffer and triangle base addresses, the triangle count and the tile index. With auto-advance, the tile index moves on after each tile and wraps to 0 after `TILE_COUNT` tiles, raising frame-done. Interrupts signal tile completion, frame completion and errors, and a set of counters reports the visible triangles, the commands issued, the cycles per tile and the stall cycles of each stage.

#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/AxiVisibilityDma.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "AxiVisibilityDMA",
      h: auto, w: auto,
      ports-margins: (east: (5%, 5%),),
    )
  })
]

#v(2em)

== Register Map
#v(1em)

#let data = json("../sdk/include/generated/AxiVisibilityDma/axi_visibility_dma_regmap.json")
#reg_spec(data)
