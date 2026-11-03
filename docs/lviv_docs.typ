#import "utils/addrmap.typ": addr_map


#set page("a4", numbering: "1")
#let main = 1

== Address Map
#v(1em)
#let data = json("../sdk/include/generated/Axi4ToApbXbar/address_map.json")
#figure(
  addr_map(data.regions),
  caption: "GPU Address Map",
)<gpu_address_map>

#pagebreak()
#include "CommandProcessor.typ"
#pagebreak()
#include "Axi4ToApbXbar.typ"
#pagebreak()
#include "AxiTiledDMA.typ"
#pagebreak()
#include "AxiVisibilityDMA.typ"
#pagebreak()
#include "L2Cache.typ"
#pagebreak()
#include "APBFrontendRegs.typ"
