#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/regspec.typ": reg_spec


#set page(paper: "a4")



= Front-End Registers
#v(1em)

The *APBFrontendRegs* block holds the raster front-end's registers and the orchestrators status. The Bounding Box registers hold the position of the first nad last pixel of each dimension and needs to be programmed by either the CPU or the command processor. So triangles running past the tile dimensions are bounded in the the size of the current tile and addition on the screen resolution on edge tiles, so no work is wasted doing work on invisible pixels.

The registers run on the APB clock (`apb_clock`) and the front-end on the thread clock (`thread_clk`).

#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/APBFrontendRegs.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "APBFrontendRegs",
      h: auto,
      w: auto,
      ports-margins: (west: (5%, 5%)),
    )
  })
]

#v(2em)

== Register Map
#v(1em)

#let data = json("../sdk/include/generated/APBFrontendRegs/apb_front_end_regmap.json")
#reg_spec(data)
