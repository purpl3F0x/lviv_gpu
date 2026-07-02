#import "@preview/cetz:0.4.1": canvas, draw
#import "@preview/circuiteria:0.2.0"

#set page(
  paper: "a4",
  margin: (x: 2cm, y: 2.5cm),
  header: align(right)[
    #text(size: 8.5pt, fill: rgb("888888"))[Bachi Thread Orchestrator Documentation]
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
  size: 10.5pt,
)

#set par(justify: true, leading: 0.65em)

// Document Title Block
#align(center)[
  #v(1cm)
  #text(size: 24pt, weight: "bold")[Thread Orchestrator (Bachi)] \
  #v(0.2cm)
  #text(size: 12pt, style: "italic")[Shio Ramen Snake-Traversal & Work Distribution Pipeline] \
  #v(0.5cm)
]

== 1. Module Overview
The `thread_orchestrator` module (codename *Bachi*, named after the sweeping plectrum used for traditional string instruments) is responsible for traversing the 2D bounding box of a triangle inside a specific tile. It performs a snake-like (boustrophedon) traversal, evaluating $2 times 2$ pixel quads in each step, and dynamically updates the edge functions for all 4 pixels of the quad in parallel.

Rather than re-evaluating the full edge function at each step, Bachi performs incremental floating-point additions/subtractions based on pre-calculated derivatives ($e_(i, "dx")$ and $e_(i, "dy")$), significantly reducing hardware overhead. The updated edge functions and metadata are then distributed to four parallel downstream thread execution units.

== 2. Block Diagram
The block diagram below details Bachi's input and output ports:

#align(center)[
  #circuiteria.circuit({
    import circuiteria: *

    element.block(
      x: 0,
      y: 0,
      w: 22,
      h: 14,
      id: "orchestrator",
      fill: circuiteria.util.colors.yellow,
      name: [
        #text("Thread Orchestrator\n(Bachi)", size: 16pt, weight: "bold")
      ],
      ports: (
        west: (
          (id: "clk", name: "", clock: true, small: true),
          (id: "rst_n", name: [#overline([rst])]),
          (id: "valid_in", name: "valid_in"),
          (id: "ready_out", name: "ready_out"),
          (id: "init_e0", name: "init_e0 [4]"),
          (id: "init_e1", name: "init_e1 [4]"),
          (id: "init_e2", name: "init_e2 [4]"),
          (id: "e0_dx_2x", name: "e0_dx_2x [31:0]"),
          (id: "e0_dy_2x", name: "e0_dy_2x [31:0]"),
          (id: "e1_dx_2x", name: "e1_dx_2x [31:0]"),
          (id: "e1_dy_2x", name: "e1_dy_2x [31:0]"),
          (id: "e2_dx_2x", name: "e2_dx_2x [31:0]"),
          (id: "e2_dy_2x", name: "e2_dy_2x [31:0]"),
          (id: "minX_local", name: "minX_local [7:0]"),
          (id: "minY_local", name: "minY_local [7:0]"),
          (id: "width", name: "width [7:0]"),
          (id: "height", name: "height [7:0]"),
          (id: "invArea", name: "invArea [31:0]"),
          (id: "v0", name: "v0 (vertex_t)"),
          (id: "v1", name: "v1 (vertex_t)"),
          (id: "v2", name: "v2 (vertex_t)"),
        ),
        east: (
          (id: "ready_in", name: "ready_in [4]"),
          (id: "valid_out", name: "valid_out [4]"),
          (id: "out_e0", name: "out_e0 [4][31:0]"),
          (id: "out_e1", name: "out_e1 [4][31:0]"),
          (id: "out_e2", name: "out_e2 [4][31:0]"),
          (id: "out_invArea", name: "out_invArea [31:0]"),
          (id: "out_v0", name: "out_v0 (vertex_t)"),
          (id: "out_v1", name: "out_v1 (vertex_t)"),
          (id: "out_v2", name: "out_v2 (vertex_t)"),
        ),
      ),
      stroke: 1.5pt,
    )

    wire.stub("orchestrator-port-clk", "west", name: "clk", length: 1.5em)
    wire.stub("orchestrator-port-rst_n", "west", length: 1.5em)
    wire.stub("orchestrator-port-valid_in", "west", length: 1.5em)
    wire.stub("orchestrator-port-ready_out", "west", length: 1.5em)
    wire.stub("orchestrator-port-init_e0", "west", length: 1.5em)
    wire.stub("orchestrator-port-init_e1", "west", length: 1.5em)
    wire.stub("orchestrator-port-init_e2", "west", length: 1.5em)
    wire.stub("orchestrator-port-e0_dx_2x", "west", length: 1.5em)
    wire.stub("orchestrator-port-e0_dy_2x", "west", length: 1.5em)
    wire.stub("orchestrator-port-e1_dx_2x", "west", length: 1.5em)
    wire.stub("orchestrator-port-e1_dy_2x", "west", length: 1.5em)
    wire.stub("orchestrator-port-e2_dx_2x", "west", length: 1.5em)
    wire.stub("orchestrator-port-e2_dy_2x", "west", length: 1.5em)
    wire.stub("orchestrator-port-minX_local", "west", length: 1.5em)
    wire.stub("orchestrator-port-minY_local", "west", length: 1.5em)
    wire.stub("orchestrator-port-width", "west", length: 1.5em)
    wire.stub("orchestrator-port-height", "west", length: 1.5em)
    wire.stub("orchestrator-port-invArea", "west", length: 1.5em)
    wire.stub("orchestrator-port-v0", "west", length: 1.5em)
    wire.stub("orchestrator-port-v1", "west", length: 1.5em)
    wire.stub("orchestrator-port-v2", "west", length: 1.5em)

    wire.stub("orchestrator-port-ready_in", "east", length: 1.5em)
    wire.stub("orchestrator-port-valid_out", "east", length: 1.5em)
    wire.stub("orchestrator-port-out_e0", "east", length: 1.5em)
    wire.stub("orchestrator-port-out_e1", "east", length: 1.5em)
    wire.stub("orchestrator-port-out_e2", "east", length: 1.5em)
    wire.stub("orchestrator-port-out_invArea", "east", length: 1.5em)
    wire.stub("orchestrator-port-out_v0", "east", length: 1.5em)
    wire.stub("orchestrator-port-out_v1", "east", length: 1.5em)
    wire.stub("orchestrator-port-out_v2", "east", length: 1.5em)

    draw.circle((rel: (-0.20, 0), to: "orchestrator-port-rst_n"), radius: 0.15, fill: white, stroke: 1.5pt)
  })
]

#pagebreak()

== 2. Module Interface
The table below specifies the functionality and description of each port on Bachi:

#align(center)[
  #table(
    columns: (1.8fr, 1fr, 1.2fr, 4fr),
    align: (left, center, center, left),
    stroke: 0.5pt,
    fill: (x, y) => if y == 0 { rgb("f0f0f0") } else { none },
    table.header([*Port Name*], [*Direction*], [*Type / Width*], [*Description*]),
    [clk], [Input], [logic], [System Clock (100 MHz)],
    [rst_n], [Input], [logic], [System Reset (Active Low)],
    [valid_in], [Input], [logic], [Handshake valid from Frontend],
    [ready_out], [Output], [logic], [Handshake ready to Frontend (High in ST_IDLE)],
    [ready_in [4]], [Input], [logic], [Handshake ready from 4 thread units],
    [valid_out [4]], [Output], [logic], [Handshake valid to 4 thread units],
    [init_e0 [4], init_e1 [4], init_e2 [4]],
    [Input],
    [logic [31:0]],
    [Initial edge functions evaluated at top-left pixel quad coordinates],

    [e0_dx_2x, e0_dy_2x], [Input], [logic [31:0]], [Edge function 0 derivatives scaled by 2 (float)],
    [e1_dx_2x, e1_dy_2x], [Input], [logic [31:0]], [Edge function 1 derivatives scaled by 2 (float)],
    [e2_dx_2x, e2_dy_2x], [Input], [logic [31:0]], [Edge function 2 derivatives scaled by 2 (float)],
    [minX_local, minY_local], [Input], [logic [7:0]], [Starting pixel coordinates of local bounding box],
    [width, height], [Input], [logic [7:0]], [Width and height of the bounding box (pixels)],
    [invArea], [Input], [logic [31:0]], [Inverse triangle area (floating-point recip)],
    [v0, v1, v2], [Input], [vertex_t], [Vertex coordinate descriptors],
    [out_e0 [4], out_e1 [4], out_e2 [4]], [Output], [logic [31:0]], [Traversally updated edge functions (1 per thread)],
    [out_invArea], [Output], [logic [31:0]], [Pipelined inverse area (float)],
    [out_v0, out_v1, out_v2], [Output], [vertex_t], [Pipelined vertex coordinates],
  )
]

== 4. Boustrophedon Traversal (Snake Path)
Bachi performs a boustrophedon (snake-like) traversal of $2 times 2$ pixel quads to sweep the bounding box of the triangle efficiently. The diagram below illustrates the traversal path across a grid of quads (each representing a $2 times 2$ pixel block):

#align(center)[
  #canvas(length: 1.0cm, {
    // Draw cells
    for r in range(0, 6) {
      for c in range(0, 6) {
        let x = c * 1.2
        let y = -r * 1.2
        let fill-color = if calc.even(calc.floor(c / 2)) == calc.even(calc.floor(r / 2)) {
          rgb("#eef1f6") // Light steel blue
        } else {
          rgb("#fff3e0") // Light peach
        }
        draw.rect(
          (x, y),
          (x + 1.2, y - 1.2),
          fill: fill-color,
          stroke: 0.5pt + rgb("#dee2e6"),
        )
      }
    }

    // Double borders around the 6x6 grid
    draw.rect((-0.15, 0.15), (7.35, -7.35), fill: none, stroke: 0.8pt + black)
    draw.rect((0, 0), (7.2, -7.2), fill: none, stroke: 1.5pt + black)

    // Draw Quad division lines (dotted)
    draw.line((2.4, 0), (2.4, -7.2), stroke: (paint: rgb("#495057"), dash: "dotted", thickness: 2pt))
    draw.line((4.8, 0), (4.8, -7.2), stroke: (paint: rgb("#495057"), dash: "dotted", thickness: 2pt))
    draw.line((0, -2.4), (7.2, -2.4), stroke: (paint: rgb("#495057"), dash: "dotted", thickness: 2pt))
    draw.line((0, -4.8), (7.2, -4.8), stroke: (paint: rgb("#495057"), dash: "dotted", thickness: 2pt))

    // Draw Traversal Path (S-curve)
    draw.line(
      (1.2, -1.2),
      (3.6, -1.2),
      (6.0, -1.2),
      (6.0, -3.6),
      (3.6, -3.6),
      (1.2, -3.6),
      (1.2, -6.0),
      (3.6, -6.0),
      (6.0, -6.0),
      stroke: 3.5pt + rgb("#ef233c"),
      mark: (end: ">", fill: rgb("#ef233c"), size: 0.15),
    )

    // Draw Quad labels (Q0 to Q8)
    let draw-label(x, y, text-label) = {
      draw.content(
        (x, y),
        box(fill: white, inset: 3.5pt, radius: 2pt, stroke: 0.5pt + rgb("#dee2e6"))[
          #text(size: 8pt, weight: "bold", fill: rgb("#2b2d42"))[#text-label]
        ],
      )
    }

    draw-label(1.2, -1.2, "Q0")
    draw-label(3.6, -1.2, "Q1")
    draw-label(6.0, -1.2, "Q2")
    draw-label(6.0, -3.6, "Q3")
    draw-label(3.6, -3.6, "Q4")
    draw-label(1.2, -3.6, "Q5")
    draw-label(1.2, -6.0, "Q6")
    draw-label(3.6, -6.0, "Q7")
    draw-label(6.0, -6.0, "Q8")

    // Add Start and End Annotations
    draw.content((1.2, 0.45), text(size: 9.5pt, weight: "bold", fill: rgb("#2b9348"), "START"), anchor: "south")
    draw.content((6.0, -7.65), text(size: 9.5pt, weight: "bold", fill: rgb("#d90429"), "END"), anchor: "north")
  })
]

The FSM tracks the current horizontal quad index `curr_qx` ($in [0, "num_quads_x"-1]$) and vertical quad index `curr_qy` ($in [0, "num_quads_y"-1]$), where:
$ "num_quads_x" = "width" >> 1 $
$ "num_quads_y" = "height" >> 1 $

The sweep direction is controlled by the register `dir_right`:
- *Rightward Sweep (`dir_right = 1`)*: Moves horizontally to the right ($Delta x = +2$ pixels). At the right boundary, it moves down ($Delta y = +2$ pixels) and flips `dir_right` to 0.
- *Leftward Sweep (`dir_right = 0`)*: Moves horizontally to the left ($Delta x = -2$ pixels). At the left boundary, it moves down ($Delta y = +2$ pixels) and flips `dir_right` to 1.
- *Termination*: Upon reaching the end of the final row boundary, traversal terminates, asserting `step_done` and returning to `ST_IDLE`.
