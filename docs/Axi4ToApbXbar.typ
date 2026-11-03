#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/addrmap.typ": addr_map


= AXI4 to APB Crossbar
#v(1em)

The *Axi4ToApbXbar* connects the system's AXI4 masters to the GPU's APB3 register blocks. It has two AXI4 slave ports, one for the CPU and one for the command processor, each with request FIFOs that absorb bursts of single-beat accesses. A round-robin arbiter picks between them and a bridge drives a single APB3 bus with a 4 KiB address space.
Internally only 1 Read/Write transaction is allowed at a time. The GPU's address map can be found in  @gpu_address_map.

#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/Axi4ToApbXbar.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "Axi4ToApbXbar",
      h: auto,
      w: auto,
      ports-margins: (east: (5%, 5%)),
    )
  })
]

#v(2em)

== Address Map
#v(1em)
#let data = json("../sdk/include/generated/Axi4ToApbXbar/address_map.json")
#figure(
  addr_map(data.regions),
  caption: "GPU Address Map",
)<gpu_address_map>
