#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google


#set page(paper: "a4")



= APB Clock Crossing
#v(1em)

The *ApbClockCrossing* carries an APB3 bus from the crossbar's clock (`s_clk`) into the clock of a slave whose registers run with its engine (`m_clk`), such as the DMAs on `aclk`. It wraps SpinalHDL's `Apb3CC`: each access crosses into the slave's clock by toggle synchronisation, with its address and data held in registers on the way, and the response comes back the same way. An access therefore takes a few cycles of each clock, with `PREADY` held low in the meantime. Both resets are active-low and synchronous.

#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/ApbClockCrossing.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "ApbClockCrossing",
      h: auto, w: auto,
      ports-margins: (east: (5%, 5%),),
    )
  })
]
