#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/regspec.typ": reg_spec


= Command Processor
#v(1em)

The  purpose of the *CommandProcessor*  is to offload the CPU from the task of managing the rendering pipeline, doing in hardware what the CPU's driver otherwise would do for every tile. The CPU still sets the frame up (the DMAs' frame registers and interrupt masks, the buffer clears and the first tile's box) and then writes the frame size (as its last pixel, SIZE) and START. From there the command processor sequences the tiles as a second master on the APB crossbar (`m_axi`), using single-beat writes, one at a time. It never reads over the bus: it follows the units through their interrupt and idle signals.

For every tile it starts the visibility DMA, then waits until every unit of the pipeline (the triangle path, the front-end, the orchestrator and the threads) has finished working, for a number of consecutive cycles. It then starts the tile DMA to write-back the tile data, while also clearing the Z-Buffers before processing to the next tile.

The command processor runs on the crossbar's clock, while the signals it watches come from the `mem_clk` and `core_clk` domains; each crosses through its own synchroniser before they are combined.

A number of Low Overhead Performance Counters (LOPCs) are implemented in the command processor, so it's performance can be assessed at runtime.

#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/CommandProcessor.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "CommandProcessor",
      h: auto,
      w: auto,
      ports-margins: (west: (5%, 5%)),
    )
  })
]

#v(2em)

== Register Map
#v(1em)

#let data = json("../sdk/include/generated/CommandProcessor/command_processor_regmap.json")
#reg_spec(data)
