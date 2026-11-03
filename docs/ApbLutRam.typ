#import "@local/circuiteria:0.2.1": *
#import "@preview/splash:0.5.0": google
#import "utils/struct.typ": bytes, struct


#set page(paper: "a4")



= Texture LUT
#v(1em)

The *ApbLutRam* holds the texture lookup tables. First 128 entries hold the Base address of that index's texture, which is the drivers/ programmer's responsibility to be correctly aligned according to texture's size. The next 128 entries hold the textures' size as power of two, int he 4 LSB's of the address, as given in @texture_size_encoding.


#v(2em)

#[
  #set align(center)
  #set text(font: "Cascadia Mono", size: 10pt)
  #circuit({
    verilog.block(
      read("../rtl/generated/ApbLutRam.v"),
      fill: google.dark-yellow-1.lighten(40%),
      radius: 0.1em,
      name: "ApbLutRam",
      h: auto,
      w: auto,
      ports-margins: (east: (5%, 5%)),
    )
  })
]

#v(2em)

== Texture Field Encoding

#figure(
  table(
    columns: 2,
    fill: (x, y) => if y == 0 { rgb("BBB") } else { none },
    table.header[*Value*][*Texture Dimensions*],
    [0], [1x1],
    [1], [2x2],
    [2], [4x4],
    [3], [8x8],
    [4], [16x16],
    [5], [32x32],
    [6], [64x64],
    [7], [128x128],
    [8], [256x256],
    [9], [512x512],
    [10], [1024x1024],
    [11], [2048x2048],
    [12], [Invalid],
    [13], [Invalid],
    [14], [Invalid],
    [15], [Invalid],
  ),
  caption: "Texture size encoding",
)<texture_size_encoding>

As an example a 64x64 textrure will need to have it's address aligned to $log_2(64) = 6$ resulting in #raw("0bXXXX_XXXX_XXXX_XXXX_XXXX_XXXX XX00_0000", lang: "python") as a valid address.

== Address Map
#v(1em)

#let xbar = json("../sdk/include/generated/Axi4ToApbXbar/address_map.json")


#figure(
  struct(
    bytes(512, "Base Address"),
    bytes(512, "Texture Size", used: (4, 32), fill: luma(200)),
    width: 6cm,
    byte-height: 0.12pt,
    max-height: 100pt,
    font: "Cascadia Mono",
    end-labels: false,
  ),
  caption: "Texture LUT address map",
)
