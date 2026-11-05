#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/regspec.typ": reg_spec
#import "utils/visibility.typ": vis_layout, vis_runs


= Visibility DMA
#v(1em)

The *AxiVisibilityDMA* is a DMA IP that builds the triangle stream of a tile from the frame's visibility bitmap, designed to offload the per-tile triangle selection, finding consecutive 1's and 0's on the visibility stream and building packets to send to a triangle DMA accordingly. The bitmap holds one bit per triangle per tile, in 4 KiB chunks of 32,768 triangles, every tile's first chunk first: chunk $c$ of tile $t$ is 4 KiB page $c dot #raw("TILE_COUNT") + t$ from the 4 KiB aligned `VB_BASE`. For the active tile, the engine reads only that tile's chunks through a read-only AXI4 master (`m_axi_vb`), one burst a chunk, 128 triangles per clock.

Each beat is turned into its edges, the bits where visibility changes. A run of visible triangles is what lies between two edges, so a beat without an edge, empty or inside a run, ends there; only the few beats with one are queued and scanned, a group of 8 edge bits at a time and then an edge at a time, so a run takes two clocks. Each run becomes a single command for an AMD AXI DataMover (`m_axis_datamover_cmd`), which fetches the triangles' geometry (96 B each by default) from memory and streams it to the raster core. A run past `BTT_LIMIT` triangles  is split into commands of that size. The engine counts the status responses on `s_axis_datamover_sts` and finishes the tile once every command has been acknowledged, flagging AXI read errors and DataMover status errors.

An APB3 slave (`s_apb`) allows runtime configuration and a number of Low Overhead Performance Counters are implemented in the engine, so it's performance can be assessed at runtime.

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

== Visibility Stream
#v(1em)

@vis_layout shows the bitmap in memory, a row of tiles for each chunk, with $T$ for `TILE_COUNT`. Each page is 256 beats of 128 bits, one AXI burst, so a tile's stream is its column, read downwards. @vis_runs follows four of those beats through the engine: a run may cross beats, and the beats between its edges are dropped with the empty ones, leaving two commands.

#figure(
  vis_layout(),
  caption: [The bitmap's 4 KiB pages, numbered from `VB_BASE`. Tile 1's are lit: its chunks are $T$ pages apart.],
)<vis_layout>

#v(1em)

#figure(
  vis_runs(),
  caption: [Four beats of a tile, with their triangles on the left. Visible triangles are colored and edges are red, with their triangle indices. Each run is the span between two edges and becomes one command.],
)<vis_runs>

#v(2em)

== Performance
The visibility DMA scans 128 triangles a clock, 42.7 GTri/s at 333 MHz, and a tile takes $ceil(N slash 128)$ beats whatever its visibility: 70,320 clocks for a frame of 150,000 triangles in 60 tiles.
#v(2em)

== Register Map
#v(1em)

#let data = json("../sdk/include/generated/AxiVisibilityDma/axi_visibility_dma_regmap.json")
#reg_spec(data)
