#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node
#import "@preview/splash:0.5.0": gruvbox

#set page(width: auto, height: auto, margin: 1.5cm)
#set text(font: "DejaVu Sans Mono", size: 10pt)
#show math.equation: set text(weight: "bold")
// #show math.equation: set text(font: "DejaVu Sans Mono")

#let colors = (
  orange: rgb("44aa99"),
  yellow: gruvbox.at("bright-yellow"),
  green: gruvbox.at("bright-aqua"),
  purple: gruvbox.at("bright-purple"),
  blue: gruvbox.at("bright-blue"),
  red: gruvbox.at("bright-red").lighten(20%),
)

#let node_dim = (w: 110pt, h: 60pt)

#align(center)[
  #text([Lviv GPU Raster Thread Top-Level Pipeline Diagram], size: 2em, weight: "bold", spacing: 0.5em)
  #v(1em)

  #line(length: 600pt, stroke: 2pt + black)
]

#v(5em)

#diagram(
  node-stroke: 1.5pt + black,
  node-corner-radius: 1pt,
  edge-corner-radius: 2pt,
  edge-stroke: 1.6pt + black,
  mark-scale: 50%,
  spacing: (32pt, 22pt),

  // -------------------------------------------------------------
  // COLUMN 0: INPUT STUBS
  // -------------------------------------------------------------
  node((0, 0.5), align(right)[*Vertex $(u_i, v_i)$*], stroke: none, name: <vert_u_v>),
  node((0, 1.2), align(right)[*Z-Buffer Addr*], stroke: none, name: <z_addr>),
  node((0, 1.9), align(right)[*Vertex $z_i$*], stroke: none, name: <vert_zi>),
  node((0, 3.0), align(right)[*Edge $e_i$, $1/"area"$*], stroke: none, name: <edge_ei>),
  node((0, 4.1), align(right)[*Vertex $w_i = 1/W_i$*], stroke: none, name: <vert_wi>),
  node((0, 4.8), align(right)[*Vertex Color $C_i$*], stroke: none, name: <vert_ci>),

  // -------------------------------------------------------------
  // COLUMN 1: iw CALCULATION (Weight Generation -> Yellow)
  // -------------------------------------------------------------
  node(
    (1, 3.0),
    align(center + horizon)[*iw Calculation*\ #v(0.2em)#text[$i w_i = e_i dot 1/"area"$]],
    fill: colors.yellow,
    width: node_dim.w,
    height: node_dim.h,
    name: <iw_calc>,
  ),

  // -------------------------------------------------------------
  // COLUMN 2: 1/W & Z INTERPOLATION (Interpolators -> Blue)
  // -------------------------------------------------------------
  node(
    (2, 2.0),
    align(center + horizon)[*Z Interpolation*\ #v(0.2em)#text[$Z = sum z_i dot i w_i$]],
    fill: colors.blue,
    width: node_dim.w,
    height: node_dim.h,
    name: <z_interp>,
  ),
  node(
    (2, 4.0),
    align(center + horizon)[*1/W Interpolation*\ #v(0.2em)#text[$1/W = sum w_i dot i w_i$]],
    fill: colors.blue,
    width: node_dim.w,
    height: node_dim.h,
    name: <inv_w_interp>,
  ),

  // -------------------------------------------------------------
  // COLUMN 3: DEPTH TEST (Red) & RECIPROCAL W (Weight Gen -> Yellow)
  // -------------------------------------------------------------
  node(
    (3, 2.0),
    align(center + horizon)[*Depth Test*\ #v(0.2em)#text[$Z <= Z_("current")$]],
    fill: colors.red,
    width: node_dim.w,
    height: node_dim.h,
    name: <depth_test>,
  ),
  node(
    (3, 4.0),
    align(center + horizon)[*Reciprocal Unit*\ #v(0.2em)#text[$W = 1 / (1/W)$]],
    fill: colors.purple,
    width: node_dim.w,
    height: node_dim.h,
    name: <recip_w>,
  ),

  // Z-Buffer external interface
  node((3, 0.7), align(center)[*Z-Buffer*], stroke: none, name: <z_buf>),

  // -------------------------------------------------------------
  // COLUMN 4: t WEIGHTS CALCULATION (Weight Gen -> Yellow)
  // -------------------------------------------------------------
  node(
    (4, 3.0),
    align(center + horizon)[*t Weights Calc*\ #v(0.2em)#text[$t_i = W dot w_i dot i w_i$]],
    fill: colors.yellow,
    width: node_dim.w,
    height: node_dim.h,
    name: <t_calc>,
  ),

  // -------------------------------------------------------------
  // COLUMN 5: FIXED-POINT CONVERSION (Weight Gen -> Yellow)
  // -------------------------------------------------------------
  node(
    (5, 3.0),
    align(center + horizon)[*Fixed-Point Conv*\ #v(0.2em)#text[$t_(i,"fx") = "fx2.23"(t_i)$]],
    fill: colors.yellow,
    width: node_dim.w,
    height: node_dim.h,
    name: <fx_conv>,
  ),

  // -------------------------------------------------------------
  // COLUMN 6: TEXTURE & COLOR INTERPOLATION (Interpolators -> Blue)
  // -------------------------------------------------------------
  node(
    (6, 2),
    align(center + horizon)[*Texture\ Interpolator*\ #v(0.2em)#text[$U, V = sum (u_i, v_i) dot t_i$]],
    fill: colors.blue,
    width: node_dim.w,
    height: node_dim.h,
    name: <tex_interp>,
  ),
  node(
    (6, 4),
    align(center + horizon)[*Color\ Interpolator*\ #v(0.2em) #[$C = sum C_i dot t_i$]],
    fill: colors.blue,
    width: node_dim.w,
    height: node_dim.h,
    name: <col_interp>,
  ),

  // -------------------------------------------------------------
  // COLUMN 7: TEXTURE ADDRESS GENERATOR & L1 CACHE (Texture -> Green)
  // -------------------------------------------------------------
  node(
    (7, 2),
    align(center + horizon)[*Texture LUT &*\ *Addr. Swizzling*],
    fill: colors.green,
    width: node_dim.w,
    height: node_dim.h,
    name: <tex_addr_gen>,
  ),
  node((7, 0.7), align(center)[*L1 Cache*], stroke: none, name: <l1_cache>),
  edge(<tex_addr_gen>, <l1_cache>, "<=>", mark-scale: 160%),

  // -------------------------------------------------------------
  // COLUMN 8: SHADING UNIT (Shading -> Purple)
  // -------------------------------------------------------------
  node(
    (8, 3),
    align(center + horizon)[*Shading Unit*],
    fill: colors.purple,
    width: node_dim.w,
    height: node_dim.h,
    name: <shading_unit>,
  ),

  // -------------------------------------------------------------
  // COLUMN 9: COLOR BLENDING & TILE BUFFER (Output/ROP -> Orange)
  // -------------------------------------------------------------
  node(
    (9, 3),
    align(center + horizon)[*Color Blending*],
    fill: colors.orange,
    width: node_dim.w,
    height: node_dim.h,
    name: <color_blender>,
  ),
  node((9, 4.0), align(center)[*Tile Buffer Read*], stroke: none, name: <tile_buf_read>),
  node((10, 3), align(center)[*Tile Buffer Write*], stroke: none, name: <tile_buf_write>, width: 100pt),
  node((10, 2), align(center)[*Depth Test\ (Controls WE)*], stroke: none, name: <comp_out>, width: 100pt),

  // =============================================================
  // EDGES / WIRES
  // =============================================================

  edge(<edge_ei>, <iw_calc>, "->"),
  edge((rel: (0, -0.1), to: <iw_calc.east>), (1.5, 2.9), (1.5, 2.1), (rel: (0, 0.1), to: <z_interp.west>), "->"),
  edge((rel: (0, 0.1), to: <iw_calc.east>), (1.5, 3.1), (1.5, 3.9), (rel: (0, -0.1), to: <inv_w_interp.west>), "->"),
  edge(<iw_calc.east>, (2.5, 3.0), (2.5, 2.9), (rel: (0, -0.1), to: <t_calc.west>), "->"),

  edge(<vert_zi>, (rel: (0.1, -0.1), to: <z_interp.west>), "->"),
  edge(<vert_wi>, (rel: (0.1, 0.1), to: <inv_w_interp.west>), "->"),
  edge(<inv_w_interp.east>, <recip_w>, "->"),

  edge((rel: (-0.1, 0.1), to: <z_interp.east>), (rel: (0.1, 0.1), to: <depth_test.west>), "->"),
  edge(<z_addr>, (2.5, 1.2), (2.5, 1.9), (rel: (0.1, -0.1), to: <depth_test.west>), "->"),
  edge(<z_buf>, <depth_test>, "<=>", mark-scale: 160%),

  edge(<recip_w.east>, (3.5, 4.0), (3.5, 3.1), (rel: (0.1, 0.1), to: <t_calc.west>), "->"),
  edge(<t_calc.east>, <fx_conv>, "->"),

  edge((rel: (0, -0.1), to: <fx_conv.east>), (5.5, 2.9), (5.5, 2.1), (rel: (0.1, 0.1), to: <tex_interp.west>), "->"),
  edge((rel: (0, 0.1), to: <fx_conv.east>), (5.5, 3.1), (5.5, 3.9), (rel: (0.1, -0.1), to: <col_interp.west>), "->"),

  edge(<vert_u_v>, (5.5, 0.5), (5.5, 1.9), (rel: (0.1, -0.1), to: <tex_interp.west>), "->"),
  edge(<vert_ci>, (5.5, 4.8), (5.5, 4.1), (rel: (0.1, 0.1), to: <col_interp.west>), "->"),

  edge((rel: (0, 0.1), to: <tex_interp>), (rel: (0, 0.1), to: <tex_addr_gen>), "->"),

  edge(<tex_addr_gen>, (7.5, 2), (7.5, 2.9), (rel: (0, -0.1), to: <shading_unit>), "->"),
  edge(<col_interp>, (7.5, 4), (7.5, 3.1), (rel: (0, 0.1), to: <shading_unit>), "->"),

  edge(<depth_test>, (4.5, 2), (4.5, 0.2), crossing: true),
  edge((4.5, 0.2), (4.5, 0), (7, 0)),
  edge(
    (6.5, 0),
    (6.5, 1.9),
    (rel: (0, -0.1), to: <tex_addr_gen.west>),
    "->",
    label: align(center)[Enables\ Cache fetch],
    label-side: center,
    label-pos: 0.2,
    label-fill: white,
  ),
  edge((7, 0), (8, 0), (8, 2), (10, 2), "->"),

  edge(<shading_unit>, <color_blender>, "->"),
  edge(<tile_buf_read>, <color_blender>, "->"),
  edge(<color_blender>, <tile_buf_write>, "->"),
)
