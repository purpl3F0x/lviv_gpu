#import "@preview/fletcher:0.5.8" as fletcher: diagram, edge, node

#set page(width: auto, height: auto, margin: 10mm, fill: white)
#set text(font: "DejaVu Sans Mono", size: 9pt, fill: black)

// Color palette
#let colors = (
  orange: rgb(245, 180, 147),
  yellow: rgb(250, 225, 127),
  green: rgb(127, 200, 172),
  pink: rgb(236, 127, 178),
  purple: rgb(189, 151, 255),
  blue: rgb(127, 203, 235),
  gray: gray,
  cyan: rgb("#3EBCB3"),
  cream: rgb("#F4CC9C"),
  dark-blue: rgb("#69AAAF"),
  cinammon: rgb("#F04158").lighten(25%),
)


#let bent-edge(from, to, offset, ..args) = {
  let midpoint = (from, offset, to)
  let vertices = (
    from,
    (from, "|-", midpoint),
    (midpoint, "-|", to),
    to,
  )
  edge(..vertices, "<->", ..args)
}



#diagram(
  node-stroke: 0.8pt + black,
  node-corner-radius: 3pt,
  edge-corner-radius: 0pt,
  edge-stroke: 1.6pt + black,
  mark-scale: 60%,
  spacing: (20mm, 16mm),

  //

  //
  // Triagle Selector
  //
  node(
    (-1, 1.9),
    fill: colors.yellow,
    width: 110pt,
    height: 60pt,
    name: <tri_selector>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Triangle\ Selector]

      ]
    ],
  ),
  edge(<tri_selector>, <tri_dma>, "->"),

  //
  // Triagle Selector
  //
  node(
    (-1, 2.8),
    fill: colors.gray,
    width: 110pt,
    height: 60pt,
    name: <vis_dma>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Triangle\ Selector]

      ]
    ],
  ),
  edge(
    <vis_dma>,
    <tri_selector>,
    "->",
    label: [#text("Visibility Stream", weight: 700)],
    label-side: center,
    label-size: 8pt,
  ),
  node((-2, 2.8), [#text("DDR", weight: "bold", 14pt)], name: <DDR_VIS_DMA>, stroke: 0pt),
  edge(<DDR_VIS_DMA>, <vis_dma>, "->"),

  //
  // Triagle DMA
  //
  node(
    (-1, 1),
    fill: colors.cyan,
    width: 110pt,
    height: 60pt,
    name: <tri_dma>,
    [
      #align(center)[
        #text(size: 12pt, weight: "bold")[Triangle DMA]

      ]
    ],
  ),
  node((-2, 1), [#text("DDR", weight: "bold", 14pt)], name: <DDR_TRI_DMA>, stroke: 0pt),
  edge(<DDR_TRI_DMA>, <tri_dma>, "->"),

  //
  // Triagle Fifo
  //
  node(
    (1, 1),
    fill: colors.cinammon,
    inset: 30pt,
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
    fill: colors.pink,
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
          [#v(30pt)#text(weight: 700, size: 10pt)[Thread #i]],
          name: head-name,
          stroke: 0pt,
          inset: -10pt,
          fill: none,
        ),

        // 2. Internal L1 Cache Node (Now an explicit node)
        node(
          (x, 6),
          [#text(weight: "bold", size: 8.5pt)[L1\ Cache]],
          fill: colors.orange,
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

        // edge((x , 7.12), label("thread-" + str(i) + ".south") , "u", "@->", shift: (-10pt, 0), mark-scale: 50%),
        // edge((x , 6.93), label("thread-" + str(i) + ".south") , "u", "@->", shift: (10pt, 0),  mark-scale: 50%),
      )
    })
    .flatten(),

  //
  // L2 Cache
  //
  node(
    (-1, 5.5),
    fill: colors.cream,
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
  node((-2, 5.5), [#text("DDR", weight: "bold", 14pt)], name: <DDR_L2>, stroke: 0pt),
  edge(<DDR_L2>, <l2>, "->"),

  //
  // Tile Frame-buffer
  //
  node(
    (0.5, 8),
    fill: colors.dark-blue,
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

  // //
  // // Frame Data Bus
  // //
  // edge(<tile_buffer.north>, (0.5, 6.86), "-@", mark-scale: 50%),
  // edge((0.3, 6.9), (1.796, 6.9), "->"),

  // //
  // // Z Data Bus
  // //
  // edge(<z_buffer.north>, (1.5, 7.08), "-@", mark-scale: 50%),
  // edge((0.205, 7.1), (1.7, 7.1), "->"),

  bent-edge(<tile_buffer.north>, <thread-0.south>, 45%, shift: 10pt),
  bent-edge(<tile_buffer.north>, <thread-1.south>, 45%, shift: 10pt),
  bent-edge(<tile_buffer.north>, <thread-2.south>, 45%, shift: 10pt),
  bent-edge(<tile_buffer.north>, <thread-3.south>, 45%, shift: 10pt),

  bent-edge(<z_buffer.north>, <thread-0.south>, 55%, shift: -10pt),
  bent-edge(<z_buffer.north>, <thread-1.south>, 55%, shift: -10pt),
  bent-edge(<z_buffer.north>, <thread-2.south>, 55%, shift: -10pt),
  bent-edge(<z_buffer.north>, <thread-3.south>, 55%, shift: -10pt),

  //
  // Tile DMA
  //
  node(
    (-1, 8),
    fill: gray,
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
  node((-2, 8), [#text("DDR", weight: "bold", 14pt)], name: <DDR_2D_DMA>, stroke: 0pt),
  edge(<DDR_2D_DMA>, <tile_dma>, "<-"),
  // 2D DMA to Frame Buffer
  edge(<tile_dma>, <tile_buffer>, "<-|||->", text("300MHz  600MHz")),
)
