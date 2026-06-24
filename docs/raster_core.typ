#import "@preview/circuiteria:0.2.0"

#set page(
  paper: "a4",
  margin: (x: 2cm, y: 2.5cm),
  header: align(right)[
    #text(size: 8.5pt, fill: rgb("888888"))[Shio Ramen Rasterizer Documentation]
  ],
  footer: context {
    let page_number = counter(page).get().first()
    let total_pages = counter(page).final().first()
    align(center)[
      #text(size: 8.5pt, fill: rgb("888888"))[Page #page_number of #total_pages]
    ]
  },
)

#set text(
  // font: "Liberation Sans",
  size: 10.5pt,
)

#set par(justify: true, leading: 0.65em)

// Document Title Block
#align(center)[
  #v(1cm)
  #text(size: 24pt, weight: "bold")[Raster Core Architecture] \
  #v(0.2cm)
  #text(size: 12pt, style: "italic")[Shio Ramen Edge Function & Inverse Area Pipeline] \
  #v(0.5cm)
]

== 1. Module Overview
The `raster_core` module is responsible for computing the edge functions and the inverse triangle area for a given triangle and tile. It utilizes a highly optimized sequential pipeline that shares floating-point subtraction, multiplication, and reciprocal arithmetic units to calculate the values over a period of 62 cycles. To optimize initial coordinate calculations, the design employs an internal Lookup Table (LUT) to convert the integer tile IDs (`tile_x_id`, `tile_y_id`) into floating-point coordinates quickly, avoiding the hardware overhead and latency of a dynamic floating-point conversion unit.

The block diagram below details the module's input and output ports:

#align(center)[
  #circuiteria.circuit({
    import circuiteria: *

    element.block(
      x: 0,
      y: 0,
      w: 24,
      h: 36,
      id: "raster",
      fill: util.colors.blue,
      name: [
        #text("Raster Frontend\n(Shio Ramen)", size: 16pt, weight: "bold") \ \
        #text("55-cycle Pipeline", size: 9pt, weight: "regular")
      ],
      ports: (
        west: (
          (id: "clk", name: "", clock: true, small: true),
          (id: "rst_n", name: [#overline([rst])]),
          (id: "vertex_in", name: "vertex_in"),
          (id: "tile_x_id", name: "tile_x_id [4:0]"),
          (id: "tile_y_id", name: "tile_y_id [4:0]"),
          (id: "valid_in", name: "valid_in"),
          (id: "ready_out", name: "ready_out"),
        ),
        east: (
          (id: "ready_in", name: "ready_in"),
          (id: "valid_out", name: "valid_out"),
          (id: "out_e0_00", name: "out_e0_00 [31:0]"),
          (id: "out_e1_00", name: "out_e1_00 [31:0]"),
          (id: "out_e2_00", name: "out_e2_00 [31:0]"),
          (id: "out_e0_10", name: "out_e0_10 [31:0]"),
          (id: "out_e1_10", name: "out_e1_10 [31:0]"),
          (id: "out_e2_10", name: "out_e2_10 [31:0]"),
          (id: "out_e0_01", name: "out_e0_01 [31:0]"),
          (id: "out_e1_01", name: "out_e1_01 [31:0]"),
          (id: "out_e2_01", name: "out_e2_01 [31:0]"),
          (id: "out_e0_11", name: "out_e0_11 [31:0]"),
          (id: "out_e1_11", name: "out_e1_11 [31:0]"),
          (id: "out_e2_11", name: "out_e2_11 [31:0]"),
          (id: "out_e0_dx_2x", name: "out_e0_dx_2x [31:0]"),
          (id: "out_e0_dy_2x", name: "out_e0_dy_2x [31:0]"),
          (id: "out_e1_dx_2x", name: "out_e1_dx_2x [31:0]"),
          (id: "out_e1_dy_2x", name: "out_e1_dy_2x [31:0]"),
          (id: "out_e2_dx_2x", name: "out_e2_dx_2x [31:0]"),
          (id: "out_e2_dy_2x", name: "out_e2_dy_2x [31:0]"),
          (id: "out_invArea", name: "out_invArea [31:0]"),
          (id: "out_v0", name: "out_v0"),
          (id: "out_v1", name: "out_v1"),
          (id: "out_v2", name: "out_v2"),
          (id: "out_minX_local", name: "out_minX_local [7:0]"),
          (id: "out_minY_local", name: "out_minY_local [7:0]"),
          (id: "out_width", name: "out_width [7:0]"),
          (id: "out_height", name: "out_height [7:0]"),
        ),
      ),
      stroke: 1.5pt,
    )

    wire.stub("raster-port-clk", "west", name: "clk", length: 1.5em)
    wire.stub("raster-port-rst_n", "west", length: 1.5em)
    wire.stub("raster-port-vertex_in", "west", length: 1.5em)
    wire.stub("raster-port-tile_x_id", "west", length: 1.5em)
    wire.stub("raster-port-tile_y_id", "west", length: 1.5em)
    wire.stub("raster-port-valid_in", "west", length: 1.5em)
    wire.stub("raster-port-ready_out", "west", length: 1.5em)

    wire.stub("raster-port-ready_in", "east", length: 1.5em)
    wire.stub("raster-port-valid_out", "east", length: 1.5em)
    wire.stub("raster-port-out_e0_00", "east", length: 1.5em)
    wire.stub("raster-port-out_e1_00", "east", length: 1.5em)
    wire.stub("raster-port-out_e2_00", "east", length: 1.5em)
    wire.stub("raster-port-out_e0_10", "east", length: 1.5em)
    wire.stub("raster-port-out_e1_10", "east", length: 1.5em)
    wire.stub("raster-port-out_e2_10", "east", length: 1.5em)
    wire.stub("raster-port-out_e0_01", "east", length: 1.5em)
    wire.stub("raster-port-out_e1_01", "east", length: 1.5em)
    wire.stub("raster-port-out_e2_01", "east", length: 1.5em)
    wire.stub("raster-port-out_e0_11", "east", length: 1.5em)
    wire.stub("raster-port-out_e1_11", "east", length: 1.5em)
    wire.stub("raster-port-out_e2_11", "east", length: 1.5em)
    wire.stub("raster-port-out_e0_dx_2x", "east", length: 1.5em)
    wire.stub("raster-port-out_e0_dy_2x", "east", length: 1.5em)
    wire.stub("raster-port-out_e1_dx_2x", "east", length: 1.5em)
    wire.stub("raster-port-out_e1_dy_2x", "east", length: 1.5em)
    wire.stub("raster-port-out_e2_dx_2x", "east", length: 1.5em)
    wire.stub("raster-port-out_e2_dy_2x", "east", length: 1.5em)
    wire.stub("raster-port-out_invArea", "east", length: 1.5em)
    wire.stub("raster-port-out_v0", "east", length: 1.5em)
    wire.stub("raster-port-out_v1", "east", length: 1.5em)
    wire.stub("raster-port-out_v2", "east", length: 1.5em)
    wire.stub("raster-port-out_minX_local", "east", length: 1.5em)
    wire.stub("raster-port-out_minY_local", "east", length: 1.5em)
    wire.stub("raster-port-out_width", "east", length: 1.5em)
    wire.stub("raster-port-out_height", "east", length: 1.5em)

    // draw.circle((rel: (-0.20, 0), to: "raster-port-rst_n"), radius: 0.15, fill: white, stroke: 1.5pt)
  })
]

#pagebreak()

== 2. Module Interface
The table below specifies the functionality and description of each port on `raster_core`:

#align(center)[
  #table(
    columns: (1.5fr, 1fr, 1fr, 3.5fr),
    align: (left, center, center, left),
    stroke: 0.5pt,
    fill: (x, y) => if y == 0 { rgb("f0f0f0") } else { none },
    table.header([*Port Name*], [*Direction*], [*Type / Width*], [*Description*]),
    [clk], [Input], [logic], [System Clock (100 MHz)],
    [rst_n], [Input], [logic], [System Reset (Active Low)],
    [vertex_in], [Input], [vertex_t], [Sequential Vertex coordinate input (X/Y)],
    [tile_x_id], [Input], [logic [8:0]], [X coordinate ID of the tile],
    [tile_y_id], [Input], [logic [8:0]], [Y coordinate ID of the tile],
    [valid_in], [Input], [logic], [Input Handshake Valid signal],
    [ready_in], [Input], [logic], [Downstream Handshake Ready signal],
    [ready_out], [Output], [logic], [Input Handshake Ready signal (asserted in `ST_READ_*`)],
    [valid_out], [Output], [logic], [Output Handshake Valid signal (asserted in ST_STALL)],
    [out_e0_row], [Output], [logic [31:0]], [Evaluated edge function 0 at tile corner],
    [out_e1_row], [Output], [logic [31:0]], [Evaluated edge function 1 at tile corner],
    [out_e2_row], [Output], [logic [31:0]], [Evaluated edge function 2 at tile corner],
    [out_e0_dx, out_e0_dy], [Output], [logic [31:0]], [Edge function 0 X and Y derivatives],
    [out_e1_dx, out_e1_dy], [Output], [logic [31:0]], [Edge function 1 X and Y derivatives],
    [out_e2_dx, out_e2_dy], [Output], [logic [31:0]], [Edge function 2 X and Y derivatives],
    [out_invArea], [Output], [logic [31:0]], [Inverse triangle area (floating-point recip)],
    [out_v0, out_v1, out_v2], [Output], [vertex_t], [Registered output copy of vertex coordinates],
  )
]

== 3. Mathematical Model
For a triangle defined by vertices $v_0$, $v_1$, $v_2$, and a tile corner coordinate $p_"min"$, the rasterizer evaluates the edge functions and inverse area using a unified edge function helper.

1. *Edge Function Definition:*
  The core mathematical primitive is the 2D edge function $E(a, b, c)$, which determines the signed area of the triangle formed by $a$, $b$, and $c$, or the position of point $c$ relative to the directed edge $a -> b$:
  $ E(a, b, c) = (c.x - a.x) times (b.y - a.y) - (c.y - a.y) times (b.x - a.x) $

2. *Tile Corner Coordinate ($p_"min"$):*
  The tile start coordinate $p_"min" = (p_"min".x, p_"min".y)$ represents the center of the top-left pixel in the tile. It is computed from the integer tile IDs using a $+0.5$ half-pixel offset to align with the pixel center grid:
  $ p_"min".x = ("tile_x_id" times "TILE_SIZE") + 0.5 $
  $ p_"min".y = ("tile_y_id" times "TILE_SIZE") + 0.5 $

3. *Triangle Area:*
  $ "area" = E(v_0, v_1, v_2) $

4. *Inverse Area:*
  $ "invArea" = 1.0 / "area" $

5. *Edge Evaluation at Tile Corner ($p_"min"$):*
  $ e_0 = E(v_1, v_2, p_"min") $
  $ e_1 = E(v_2, v_0, p_"min") $
  $ e_2 = E(v_0, v_1, p_"min") $

6. *Edge Derivatives & Step-Based Increments:*
  The derivatives $e_(i, "dx")$ and $e_(i, "dy")$ represent the partial derivatives of the edge function $E(v_i, v_(i+1), p)$ with respect to $p.x$ and $p.y$:
  $ e_(i, "dx") = (partial E(v_i, v_(i+1), p)) / (partial p.x) = v_(i+1).y - v_i.y $
  $ e_(i, "dy") = (partial E(v_i, v_(i+1), p)) / (partial p.y) = -(v_(i+1).x - v_i.x) = v_i.x - v_(i+1).x $
  
  These derivatives describe the rate of change of the edge function when moving by a single pixel in the $x$ and $y$ directions. This enables the downstream pixel shader/shader block to evaluate the edge equations at any grid coordinate $(x + 1, y)$ or $(x, y + 1)$ incrementally using low-cost additions instead of re-evaluating the full edge equation:
  $ e_i (x + 1, y) = e_i (x, y) + e_(i, "dx") $
  $ e_i (x, y + 1) = e_i (x, y) + e_(i, "dy") $

#pagebreak()


#pagebreak()

== 6. Control Flow & Stalling Behavior
The raster core FSM operates as follows:
- *ST_READ_V0 / ST_READ_V1 / ST_READ_V2*: The FSM waits for `valid_in = 1` to read the three sequential vertices of the triangle (`v0`, `v1`, `v2`). `ready_out` is high.
- *ST_CALC*: Once all three vertices are received, the FSM transitions to `ST_CALC` and `cycle_cnt` increments up to 62. `ready_out` is low.
- *ST_STALL*: At `cycle_cnt == 62`, the pipeline results are latched, `valid_out` goes high to indicate the outputs are valid, and the FSM unconditionally transitions to `ST_STALL`.
  - While in `ST_STALL`, `ready_out` remains `0` (so the core blocks and refuses new vertices).
  - The core remains in `ST_STALL` holding the valid output data until `ready_in` goes high, indicating that the downstream consumer has read the outputs.
  - When `ready_in` is asserted, `valid_out` goes back to `0`, and the FSM transitions to `ST_READ_V0` to prepare for the next triangle.
