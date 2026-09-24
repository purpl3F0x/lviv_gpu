#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node
#import "@preview/splash:0.5.0": gruvbox

#set page(width: auto, height: auto, margin: 10mm, fill: white)
#set text(font: "DejaVu Sans Mono", size: 9pt, fill: black)

// Color palette
#let colors = (
  orange: rgb("44aa99"),
  yellow: gruvbox.bright-yellow,
  green: gruvbox.bright-aqua,
  purple: gruvbox.bright-purple,
  blue: gruvbox.bright-blue,
  red: gruvbox.bright-red.lighten(20%),
)


#align(center)[
  #text([Lviv GPU Block Diagram], size: 4em, weight: "bold", spacing: 0.5em)
  #v(-2em)

  #line(length: 600pt, stroke: 3pt + black)
]

#v(5em)

#diagram(
  node-stroke: 1pt + black,
  node-corner-radius: 1pt,
  edge-corner-radius: 0.5pt,
  edge-stroke: 1.6pt + black,
  mark-scale: 60%,
  spacing: (40pt, 30pt),

  //

  //
  // Triagle DMA
  //
  node(
    (-1, 2),
    fill: colors.orange,
    width: 110pt,
    height: 60pt,
    name: <vis_dma>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Visibility DMA]

      ]
    ],
  ),
  edge(
    <vis_dma>,
    <tri_dma>,
    "->",
    label: [#text("Datamover Command Stream", weight: 700)],
    label-side: center,
    label-size: 8pt,
  ),
  node((-2.5, 2), [#text("PS DDR", weight: "bold", 14pt)], name: <DDR_VIS_DMA>, stroke: 0pt),
  edge(<DDR_VIS_DMA>, <vis_dma>, "->", label: "/128b", label-side: center),

  //
  // Triagle DMA
  //
  node(
    (-1, 1),
    fill: colors.orange,
    width: 110pt,
    height: 60pt,
    name: <tri_dma>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Triangle DMA]

      ]
    ],
  ),
  node((-2.5, 1), [#text("PL DDR", weight: "bold", 14pt)], name: <DDR_TRI_DMA>, stroke: 0pt),
  edge(<DDR_TRI_DMA>, <tri_dma>, "->", label: "/512b", label-side: center),

  //
  // Control Unit
  //
  node(
    (-1, 3),
    fill: colors.red,
    width: 110pt,
    height: 100pt,
    name: <cu>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Control Unit]

      ]
    ],
  ),
  let cu_stroke = stroke(paint: black.lighten(50%), dash: (2pt, 8pt)),

  edge((0, 2), <vis_dma>, "-|>", stroke: cu_stroke),
  edge((0, 3), (0, 1.10), (rel: (0, 0.1), to: <tri_fifo.west>), "-|>", shift: 0%, stroke: cu_stroke, corner: right),
  edge((0, 2), <front.west>, "-|>", stroke: cu_stroke),
  edge((0, 3.9), "d,d,d,l", <tile_dma>, "-|>", stroke: cu_stroke),

  edge(<cu>, (0, 3), (0, 3.9), (0.2, 3.9), (rel: (-0.05, 0), to: <thread-0.north>), "<|-|>", stroke: cu_stroke),
  edge((0.2, 3.9), (0.7, 3.9), (rel: (-0.05, 0), to: <thread-1.north>), "-|>", stroke: cu_stroke),
  edge((0.7, 3.9), (1.2, 3.9), (rel: (-0.05, 0), to: <thread-2.north>), "-|>", stroke: cu_stroke),
  edge((1.2, 3.9), (1.7, 3.9), (rel: (-0.05, 0), to: <thread-3.north>), "-|>", stroke: cu_stroke),

  //
  // Triagle Fifo
  //
  node(
    (1, 1),
    fill: colors.blue,
    inset: 20pt,
    // width: 250pt,
    name: <tri_fifo>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Triangle FIFO]

      ]
    ],
  ),

  edge(<tri_dma>, <tri_fifo>, "-|||->", label: "300MHz  500MHz"),

  //
  // Thread Orchestrator
  //
  node(
    (1, 2),
    fill: colors.blue,
    inset: 30pt,
    width: 250pt,
    name: <front>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Thread Frontend]

        // #v(6pt)
        // #text(size: 8.5pt)[
        //   Initial per Triangle Setup\
        //   and bounding box calculation
        // ]
      ]
    ],
  ),
  edge(<tri_fifo>, <front>, "->", label: "Triangle in", label-side: center, label-size: 8pt),

  //
  // Thread Orchestrator
  //
  node(
    (1, 3),
    fill: colors.blue,
    inset: 30pt,
    width: 250pt,
    name: <orch>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Thread Orchestrator]

        // #v(6pt)
        // #text(size: 8.5pt)[
        //   Traverses the bounding box in a snake pattern\
        //   interpolating the per-pixel (per-thread) coefficients\
        //   and synchronizes the threads

        //   #v(4pt)
        //   Pixel rejection ($e_(0,1,2) >= 0$ and $Z$) is done on threads
        // ]
      ]
    ],
  ),

  edge(<front>, <orch>, "->"),

  //
  // Upper per-thread Data Bus
  //
  edge(<orch.south>, (1, 4), "-", label: [per-thread data], label-side: center),
  edge((0.25, 4), (1.75, 4), "-"),

  //
  // THREADS WITH ENCLOSED L1 CACHE NODES
  //
  ..range(4)
    .map(i => {
      let x = 0.25 + i * 0.5
      let head-name = label("head-" + str(i))
      let l1-name = label("l1-" + str(i))
      let thread-name = label("thread-" + str(i))

      (
        // 1. Internal Thread Title Node
        node(
          (x, 4.7),
          [#v(60pt)#text(weight: 700, size: 10pt)[Thread #i]],
          name: head-name,
          stroke: 0pt,
          inset: -20pt,
          fill: none,
        ),

        // 2. Internal L1 Cache Node (Now an explicit node)
        node(
          (x, 6),
          [#text(weight: "bold", size: 8.5pt)[L1\ Cache]],
          fill: colors.yellow,
          width: 40pt,
          height: 35pt,
          name: l1-name,
        ),

        // 3. Green Outer Container Enclosing Title + L1 Cache
        node(
          enclose: (head-name, l1-name),
          fill: colors.green,
          inset: 8pt,
          name: thread-name,
        ),

        // Top bus dropping into the Thread Container
        edge((x, 4), label("thread-" + str(i) + ".north"), "->"),

        // Direct connection from BOTTOM of L1 Cache out to the L2 Bus
        edge(l1-name, (x, 5.5), "<|-", stroke: 0.75pt, mark-scale: 120%),
      )
    })
    .flatten(),

  //
  // L2 Cache
  //
  node(
    (-1, 5.5),
    fill: colors.yellow,
    height: 80pt,
    width: 60pt,
    name: <l2>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[L2\ Cache]
      ]
    ],
  ),

  // Shared L2 Bus Line connecting L2 Cache directly to each L1 Cache
  edge(<l2.east>, (1.75, 5.5), "-", stroke: 0.75pt),
  edge((1.62, 5.5), (1.75, 5.5), "-", stroke: 0.75pt),

  // DDR to L2
  node((-2.5, 5.5), [#text("PL DDR", weight: "bold", 14pt)], name: <DDR_L2>, stroke: 0pt),
  edge(<DDR_L2>, <l2>, "->", label: "/512b", label-side: center),

  //
  // Tile Frame-buffer
  //
  node(
    (0.5, 8),
    fill: colors.purple,
    height: 120pt,
    width: 120pt,
    name: <tile_buffer>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Tile Frame Buffer]
      ]
    ],
  ),

  //
  // Tile Z-buffer
  //
  node(
    (1.5, 8),
    fill: colors.purple,
    height: 120pt,
    width: 120pt,
    name: <z_buffer>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Tile Z-Buffer]
      ]
    ],
  ),

  // ORDER MATTERS - don't fix it if ain't broken
  edge(<tile_buffer.north>, (0.5, 7.1), "<-"),
  edge((0.5, 7.1), (0.2, 7.1), "-"),
  edge((0.2, 7.121), (rel: (-0.05, 0), to: <thread-0.south>), "*->"),
  edge((0.489, 7.1), (0.7, 7.1), (rel: (-0.05, 0), to: <thread-1.south>), "*->"),
  edge((0.689, 7.1), (1.2, 7.1), (rel: (-0.05, 0), to: <thread-2.south>), "*->"),
  edge((1.7, 7.12), (rel: (-0.05, 0), to: <thread-3.south>), "*->"),

  edge((0.3, 6.9), (1.8, 6.9), "-", crossing: true),
  edge((1.5, 6.865), <z_buffer.north>, "*->"),
  edge((1.5, 6.865), (1.5, 7.2), "*-"),
  edge((0.3, 6.935), (rel: (0.05, 0), to: <thread-0.south>), "*->"),
  edge((0.8, 6.935), (rel: (0.05, 0), to: <thread-1.south>), "*->"),
  edge((1.3, 6.935), (rel: (0.05, 0), to: <thread-2.south>), "*->"),
  edge((1.8, 6.935), (rel: (0.05, 0), to: <thread-3.south>), "*->"),

  edge((1.4, 7.1), (1.6, 7.1), "-", crossing: true),
  edge((1.189, 7.1), (1.7, 7.1), "*-"),

  //
  // Tile DMA
  //
  node(
    (-1, 8),
    fill: colors.orange,
    height: 80pt,
    width: 60pt,
    name: <tile_dma>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[2D\ DMA]
      ]
    ],
  ),

  // DDR to 2D DMA
  node((-2.5, 8), [#text("PS DDR", weight: "bold", 14pt)], name: <DDR_2D_DMA>, stroke: 0pt),
  edge(<DDR_2D_DMA>, <tile_dma>, "<-", label: "/128b", label-side: center),
  // 2D DMA to Frame Buffer
  edge(<tile_dma>, <tile_buffer>, "<-|||->", text("300MHz  500MHz")),
)
