#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/regspec.typ": reg_spec


= Visibility DMA
#v(1em)

The *AxiVisibilityDMA* is a DMA command engine that builds the triangle stream of a tile from the frame's visibility buffer, designed to offload the per-tile triangle selection, finding consecutive 1's and 0's. on the Visibility stream and building packets to sent to a triangle DMA accordingly. The visibility buffer holds one 64-bit word per triangle, with one bit per tile of the frame. For the active tile, the engine reads the buffer through a read-only AXI4 master (`m_axi_vb`), picks that tile's bit out of every word and filters two triangles per clock.

Consecutive visible triangles are merged into runs, and each run becomes a single command for an AMD AXI DataMover (`m_axis_datamover_cmd`), which fetches the triangles' geometry (96 B each by default) from memory and streams it to the raster core. A run is only split when it reaches the per-command limit set in `BTT_LIMIT` or the DataMover's byte count. The engine counts the status responses on `s_axis_datamover_sts` and finishes the tile once every command has been acknowledged, flagging AXI read errors and DataMover status errors.

An APB3 slave (`s_apb`) allows runtime configuration and a number of Low Overhead Performance Counters (LOPCs) are implemented in the engine, so it's performance can be assessed at runtime.

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
      h: auto,
      w: auto,
      ports-margins: (east: (5%, 5%)),
    )
  })
]

#v(2em)

== Performance
The visibility DMA can sustain 600 MTri/s at 300 MHz.
#v(2em)

== Register Map
#v(1em)

#let data = json("../sdk/include/generated/AxiVisibilityDma/axi_visibility_dma_regmap.json")
#reg_spec(data)
