#import "@preview/circuiteria:0.2.0"

#set page(width: auto, height: auto, margin: 1cm)

#let stud_len = 2em;

#align(center)[
  #circuiteria.circuit({
    import circuiteria: *

    element.block(
      x: 0,
      y: 0,
      w: 16,
      h: 8,
      id: "shader",
      fill: util.colors.green,
      name: [
        #text("Fragment Shader \n (Wasabi)", size: 16pt, weight: "bold") \
        #text("5-stage pipline", size: 12pt, weight: "thin") \
        // #v(0.5em)
        // #align(left)[
        //   _Operations:_ \
        //   • *REPLACE*: Ct \
        //   • *MODULATE*: Cf $times$ Ct \
        //   • *DECAL*: Cf $times$ (1-Ct.a) + Ct $times$ Ct.a \
        //   • *BLEND*: Cf $times$ (1-Ct.rgb) + Cc $times$ Ct.rgb \
        //   • *ADD*: Cf + Ct
        //   • *COLOR* Cf
        // ]
      ],
      ports: (
        west: (
          (id: "clk", name: "", clock: true, small: true),
          (id: "rst", name: "rst"),
          (id: "pixel_color", name: "pixel_color [31:0]"),
          (id: "texture_color", name: "texture_color [31:0]"),
          (id: "env_color", name: "env_color [31:0]"),
          (id: "valid_in", name: "valid_in"),
          (id: "op", name: "op [2:0]"),
        ),
        east: (
          (id: "ready", name: "ready"),
          (id: "fragment_color", name: "fragment_color [31:0]"),
          (id: "valid_out", name: "valid_out"),
        ),
      ),
      stroke: 1.5pt,
    )

    wire.stub("shader-port-clk", "west", name: "clk", length: stud_len)
    wire.stub("shader-port-rst", "west", length: stud_len)
    wire.stub("shader-port-pixel_color", "west", length: stud_len)
    wire.stub("shader-port-texture_color", "west", length: stud_len)
    wire.stub("shader-port-env_color", "west", length: stud_len)
    wire.stub("shader-port-valid_in", "west", length: stud_len)
    wire.stub("shader-port-op", "west", length: stud_len)

    wire.stub("shader-port-ready", "east", length: stud_len)
    wire.stub("shader-port-fragment_color", "east", length: stud_len)
    wire.stub("shader-port-valid_out", "east", length: stud_len)
  })
]
