#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/regspec.typ": reg_spec


#set page(paper: "a4")



= Thread Registers
#v(1em)

The *ApbThreadRegs* exposes a register interface for status control of a thread and it's L1 cache. Z-buffer clear functionality is also controlled through this interface. The registers run on the APB clock (`apb_clock`) and the thread on the thread clock (`thread_clk`).

#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/ApbThreadRegs.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "ApbThreadRegs",
      h: auto, w: auto,
      ports-margins: (west: (5%, 5%),),
    )
  })
]

#v(2em)

== Register Map
#v(1em)

#let data = json("../sdk/include/generated/ApbThreadRegs/apb_thread_regmap.json")
#reg_spec(data)
