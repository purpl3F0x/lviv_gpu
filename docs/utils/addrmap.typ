#import "struct.typ": bytes, gap, struct

// regions: the "regions" of an address_map.json, or one region's "subregions".
// A region is one box; its subregions are braces on the side.
#let addr_map(regions, ..args) = {
  let groups = regions
    .map(r => r.at("subregions", default: ()))
    .flatten()
    .map(s => (at: s.base, size: s.size, label: s.name))
  align(center, struct(
    ..regions.map(r => if r.kind == "reserved" {
      gap(r.size * 8, "Reserved")
    } else {
      bytes(r.size, r.name, at: r.base)
    }),
    width: 6cm,
    font: "Cascadia Mono",
    end-labels: false,
    groups: groups,
    ..args,
  ))
}
