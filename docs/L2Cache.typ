#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/regspec.typ": reg_spec


= L2 Texture Cache
#v(1em)

The *L2Cache* is a read-only texture cache in URAM, shared by the threads' L1 texture caches. Each L1 connects to its own 128-bit AXI4 slave port (`s_axi_N`) and asks for one 256 B block (an $8 times 8$ block of 32-bit texels) at a time, returned as a 16-beat burst. The cache is set-associative (1 MiB, 2 ways and 1 KiB lines by default) with LRU replacement and tags in BRAM, and fetches missing lines from DDR through a single 512-bit AXI4 master (`m_axi`).

A round-robin arbiter serves commands from the L1 caches. Ports asking for the same block at the same time join the granted request and are served together. A miss allocates an MSHR (Miss Status/Handler Registers) and reads the whole line from DDR. Requests for a line that is already on its way join its MSHR instead of reading it again, and each port gets its block as soon as that part of the line has arrived. Up to two lines per port can be in flight, with `m_axi` issuing up to 8 outstanding transactions to the main memory.

The cache runs on `core_clk`, the DDR master on `mem_clk` and the AXI4-Lite register interface (`s_axil`) on `ctrl_clk`, with the DDR read path crossing through LUTRAM FIFOs. 

A number of Low Overhead Performance Counters are implemented in the cache, so it's performance can be assessed at runtime.

#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/L2Cache.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "L2Cache",
      h: auto, w: auto,
      ports-margins: (west: (5%, 5%),),
    )
  })
]

#v(2em)

== Register Map
#v(1em)

#let data = json("../sdk/include/generated/L2Cache/l2_cache_regmap.json")
#reg_spec(data)
