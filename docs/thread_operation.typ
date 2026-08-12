#import "@preview/cetz:0.3.2": canvas, draw

#set page(width: auto, height: auto, margin: 1cm)
#set text(font: "DejaVu Sans Mono", size: 10pt)
#show math.equation: set text(weight: "bold")
#show math.equation: set text(font: "DejaVu Sans Mono")

#canvas(length: 0.58cm, {
  let block(x, y, w, h, fill, title, formula, name: none) = {
    draw.rect(
      (x - w / 2, y - h / 2),
      (x + w / 2, y + h / 2),
      fill: fill,
      stroke: (thickness: 1.5pt, paint: black),
      radius: 0.2,
      name: name,
    )
    draw.content(
      (x, y),
      align(center)[
        #text(size: 12pt, weight: "bold")[#title]
        #if formula != none and formula != [] and formula != "" [
          \ #v(0.2em) #text(size: 8pt)[#formula]
        ]
      ],
    )
  }

  // ─── Layout design: ZIG-ZAG snake ────────────────────────────────────────
  //
  //  Row 0 (Y= 6): Z track         →→ [Z Interp] → [Depth Test]
  //  Row 1 (Y=-2): W/t track  →→→→→→→→→→→→→→→→→→→→→→ [fx_conv]
  //                                                          ↓ t-bus (X=45)
  //  Loop-back  ←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←←
  //  ↓ (X=12.5)
  //  Row 2 (Y=-8):  [Tex Interp] →→ [Tex Gate] →→ [Tex Addr]
  //  Row 3 (Y=-14): [Col Interp] →→ [Col Gate]
  //                                                     ↓
  //  Row 4 (Y=-11):                              [Shading] → [Blending]
  // ─────────────────────────────────────────────────────────────────────────

  // 1. INPUT STUBS
  draw.content((0.0, 2.0), anchor: "east", text(size: 14pt, weight: "bold")[Edge $e_i$, $1/"area"$])
  draw.content((0.0, -2.0), anchor: "east", text(size: 14pt, weight: "bold")[Vertex $w_i = 1/W_i$])
  draw.content((0.0, 6.8), anchor: "east", text(size: 14pt, weight: "bold")[Vertex $z_i$])
  draw.content((0.0, 8.5), anchor: "east", text(size: 14pt, weight: "bold")[Z-Buffer Addr])
  draw.content((0.0, -12.0), anchor: "east", text(size: 14pt, weight: "bold")[Vertex $(u_i, v_i)$])
  draw.content((0.0, -18.0), anchor: "east", text(size: 14pt, weight: "bold")[Vertex Color $C_i$])

  // 2. PROCESSING BLOCKS
  // Z track (Y=6)
  block(15.0, 6.0, 6.0, 3.5, blue.lighten(40%), [Z \ Interpolation], [$Z = sum z_i dot i w_i$], name: "z_interp")
  block(25.0, 6.0, 6.0, 3.5, red.lighten(40%), [Depth Test], [$Z <= Z_("current")$], name: "depth_test")

  // iw + W/t track (Y=2 and Y=-2)
  block(4.0, 2.0, 6.0, 3.5, yellow.lighten(40%), [iw \ Calculation], [$i w_i = e_i dot 1/"area"$], name: "iw_calc")
  block(
    15.0,
    -2.0,
    7.0,
    3.5,
    blue.lighten(40%),
    [1/W \ Interpolation],
    [$1/W = sum w_i dot i w_i$],
    name: "inv_w_interp",
  )
  block(23.0, -2.0, 6.0, 3.5, purple.lighten(40%), [Reciprocal \ Unit], [$W = 1 / (1/W)$], name: "recip_w")
  block(32.0, -2.0, 7.0, 3.5, yellow.lighten(40%), [t Weights \ Calc], [$t_i = W dot w_i dot i w_i$], name: "t_calc")
  block(
    41.0,
    -2.0,
    7.0,
    3.5,
    yellow.lighten(40%),
    [Fixed-Point \ Conv],
    [$t_(i,"fx") = "fx2.23"(t_i)$],
    name: "fx_conv",
  )

  // Tex row (Y=-11): starts at LEFT, goes RIGHT — zig-zag snake turn
  block(
    7.0,
    -11.0,
    7.0,
    3.5,
    teal.lighten(40%),
    [Texture\ Interpolator],
    [$U, V = sum (u_i, v_i) dot t_i$],
    name: "tex_interp",
  )
  block(16.0, -11.0, 5.0, 3.5, gray.lighten(50%), [Reject Gate], [if $Z > Z_("current")$], name: "tex_gate")
  block(24.0, -11.0, 7.0, 3.5, teal.lighten(40%), [Texture LUT &\ Addr. Swizzling], none, name: "tex_addr_gen")

  // Color row (Y=-17): also starts LEFT, goes RIGHT
  block(7.0, -17.0, 7.0, 3.5, orange.lighten(40%), [Color \ Interpolator], [$C = sum C_i dot t_i$], name: "col_interp")
  block(16.0, -17.0, 5.0, 3.5, gray.lighten(50%), [Reject Gate], [if $Z > Z_("current")$], name: "col_gate")

  // Shading + Blending (Y=-14, right of tex addr gen)
  block(32.0, -14.0, 6.0, 3.5, purple.lighten(40%), [Shading\ Unit], none, name: "shading_unit")
  block(40.0, -14.0, 6.0, 3.5, orange.lighten(40%), [Color\ Blending], none, name: "color_blender")

  // 3. WIRES

  // Edge → iw_calc
  draw.line(
    (0.0, 2.0),
    "iw_calc.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Vertex w_i → inv_w_interp
  draw.line(
    (0.0, -2.0),
    "inv_w_interp.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // iw bus: X=9.5, drop from Y=5.2 to Y=1.0
  let iw-bus-x = 9.5
  draw.line("iw_calc.east", (iw-bus-x, 2.0), stroke: (thickness: 2pt, paint: black))
  draw.line((iw-bus-x, 5.2), (iw-bus-x, 1.0), stroke: (thickness: 2pt, paint: black))

  // iw bus → Z Interpolator
  draw.line(
    (iw-bus-x, 5.2),
    (horizontal: "z_interp.west", vertical: (0, 5.2)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // iw bus → 1/W Interpolator (second input: down then right into west side)
  draw.line(
    (iw-bus-x, 1.0),
    (iw-bus-x, -1.2),
    (horizontal: "inv_w_interp.west", vertical: (0, -1.2)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // inv_w_interp → recip_w → t_calc → fx_conv (main L→R chain, row 1)
  draw.line(
    "inv_w_interp.east",
    "recip_w.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )
  draw.line(
    "recip_w.east",
    "t_calc.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )
  draw.line(
    "t_calc.east",
    "fx_conv.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // iw bus → t_calc (bypass above main row, separate top entry)
  draw.line(
    (iw-bus-x, 1.0),
    (32.0, 1.0),
    (horizontal: (32.0, 1.0), vertical: "t_calc.north"),
    "t_calc.north",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Vertex z_i → Z Interpolator
  draw.line(
    (0.0, 6.8),
    (horizontal: "z_interp.west", vertical: (0, 6.8)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Z-Buffer Addr → Depth Test (elbow from top-left)
  draw.line(
    (0.0, 8.5),
    (19.0, 8.5),
    (19.0, 7.2),
    (22.0, 7.2),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Z Interpolator → Depth Test
  draw.line(
    "z_interp.east",
    "depth_test.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Z-Buffer bidirectional arrow from top
  draw.line(
    (25.0, 10.5),
    "depth_test.north",
    stroke: (thickness: 2pt, paint: black),
    mark: (start: ">", end: ">", fill: black, size: 0.5),
  )
  draw.content((25.0, 10.7), anchor: "south", text(size: 10pt, weight: "bold")[Z-Buffer])

  // ── ZIG-ZAG: t-bus → snakes LEFT back to interpolators ──────────────────
  // fx_conv.east (X=44.5) → t-bus-x=46 → drops to Y=-8.5
  let t-bus-x = 46.0
  draw.line("fx_conv.east", (t-bus-x, -2.0), (t-bus-x, -8.5), stroke: (thickness: 2pt, paint: black))

  // Loop-back arrow: goes LEFT from t-bus to X=2.5 (left of tex_interp.west at 3.5)
  draw.line((t-bus-x, -8.5), (2.5, -8.5), stroke: (thickness: 2pt, paint: black))

  // Loop-back → Texture Interpolator upper-west port (Y=-10.0)
  draw.line(
    (2.5, -8.5),
    (2.5, -10.0),
    (horizontal: "tex_interp.west", vertical: (0, -10.0)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Loop-back continues down → Color Interpolator upper-west port (Y=-16.0)
  draw.line(
    (2.5, -8.5),
    (2.5, -16.0),
    (horizontal: "col_interp.west", vertical: (0, -16.0)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Vertex (u,v) → Texture Interpolator lower-west port (Y=-12.0, straight horizontal)
  draw.line(
    (0.0, -12.0),
    (horizontal: "tex_interp.west", vertical: (0, -12.0)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Vertex Color → Color Interpolator lower-west port (Y=-18.0, straight horizontal)
  draw.line(
    (0.0, -18.0),
    (horizontal: "col_interp.west", vertical: (0, -18.0)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // tex_interp → tex_gate → tex_addr_gen (R→ row 2)
  draw.line(
    "tex_interp.east",
    "tex_gate.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )
  draw.line(
    "tex_gate.east",
    "tex_addr_gen.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // col_interp → col_gate (L→R, row 3)
  draw.line(
    "col_interp.east",
    "col_gate.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Z-result ctrl bus: exits depth_test right and drops to the right of fx_conv
  let ctrl-bus-x = 47.0
  draw.line("depth_test.east", (ctrl-bus-x, 6.0), stroke: (thickness: 2pt, paint: black))
  draw.line((ctrl-bus-x, 6.0), (ctrl-bus-x, -9), stroke: (thickness: 2pt, paint: black))
  draw.line((ctrl-bus-x, -9), (12, -9), stroke: (thickness: 2pt, paint: black))
  draw.line((12, -9), (12, -16), stroke: (thickness: 2pt, paint: black))
  draw.line(
    (12, -16),
    (horizontal: "col_gate.west", vertical: (0, -16)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )
  draw.line(
    (12, -10),
    (horizontal: "tex_gate.west", vertical: (0, -10)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // L1 Cache ↕ tex_addr_gen (from below)
  draw.line(
    (24.0, -12.75),
    (horizontal: "tex_addr_gen.south", vertical: (30.0, -15)),
    stroke: (thickness: 2pt, paint: black),
    mark: (start: ">", end: ">", fill: black, size: 0.5),
  )
  draw.content((24.0, -15.2), anchor: "north", text(size: 11pt, weight: "bold")[L1 Cache])

  // tex_addr_gen → shading_unit (right then down into north)
  draw.line("tex_addr_gen.east", (28.05, -11.0), (28.05, -13.55), stroke: (thickness: 2pt, paint: black))
  draw.line(
    (28.0, -13.5),
    (29.0, -13.5),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // col_gate → shading_unit (right then up into south)
  draw.line("col_gate.east", (28.05, -17.0), (28.05, -14.45), stroke: (thickness: 2pt, paint: black))
  draw.line(
    (28.0, -14.5),
    (29.0, -14.5),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // shading → blending
  draw.line(
    "shading_unit.east",
    "color_blender.west",
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )

  // Tile Buffer Read/Write
  draw.line(
    (40.0, -11.0),
    (horizontal: "color_blender.south", vertical: (0, -12.3)),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )
  draw.content((36.8, -10.4), anchor: "west", text(size: 11pt, weight: "bold")[Tile Buffer Read])

  draw.line(
    (horizontal: "color_blender.east", vertical: (0, -14)),
    (45.0, -14),
    stroke: (thickness: 2pt, paint: black),
    mark: (end: ">", fill: black, size: 0.5),
  )
  draw.content((45.2, -14), anchor: "west", text(size: 11pt, weight: "bold")[Tile Buffer Write])
})
