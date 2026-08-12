#import "@preview/circuiteria:0.2.0"
#import "@preview/cetz:0.3.2": draw

#set page(width: auto, height: auto, margin: (left: 2.5cm, right: 1.5cm, top: 1.5cm, bottom: 1.5cm))

#align(center)[
  // #text(size: 24pt, weight: "bold")[Lviv GPU Block Diagram]
  // #v(1em)
  #circuiteria.circuit({
    import circuiteria: *

    // 0a. Control Unit (CU) Block (Top-Left)
    element.block(
      x: -9,
      y: 13,
      w: 5,
      h: 4,
      id: "CP",
      fill: red.lighten(40%),
      name: [ #text("Control Unit\n(CU)", size: 13pt, weight: "bold") ],
      ports: (
        west: (
          (id: "host_in", name: "", vertical: false),
        ),
        east: (
          (id: "to_ctrl", name: "", vertical: false),
        ),
      ),
    )

    // 0b. Triangle FIFO (Top)
    element.block(
      x: 3.5,
      y: 9,
      w: 8,
      h: 3,
      id: "TriFIFO",
      fill: rgb("#FDBA6F"),
      name: [ #text("Triangle FIFO", size: 16pt, weight: "bold") ],
      ports: (
        west: (
          (id: "from_dma", name: "", vertical: false),
        ),
        south: (
          (id: "to_frontend", name: "", vertical: true),
        ),
      ),
    )

    // 0c. Triangle DMA (Top-Left)
    element.block(
      x: -9,
      y: 9,
      w: 5,
      h: 3,
      id: "TriDMA",
      fill: silver.darken(10%),
      name: [ #text("Triangle DMA", size: 12pt, weight: "bold") ],
      ports: (
        west: (
          (id: "to_ddr", name: "", vertical: false),
        ),
        south: (
          (id: "from_selector", name: "", vertical: true),
        ),
        east: (
          (id: "to_fifo", name: "", vertical: false),
        ),
      ),
    )

    // 0d. Triangle Selector (Top-Left, below Triangle DMA)
    element.block(
      x: -9,
      y: 5,
      w: 5,
      h: 3,
      id: "TriSelector",
      fill: util.colors.yellow.lighten(40%),
      name: [ #text("Triangle\nSelector", size: 12pt, weight: "bold") ],
      ports: (
        south: (
          (id: "from_vis_dma", name: "", vertical: true),
        ),
        north: (
          (id: "to_tri_dma", name: "", vertical: true),
        ),
      ),
    )

    // 0e. Visibility DMA (Top-Left, below Triangle Selector)
    element.block(
      x: -9,
      y: 1,
      w: 5,
      h: 3,
      id: "VisDMA",
      fill: silver.darken(10%),
      name: [ #text("Visibility DMA", size: 12pt, weight: "bold") ],
      ports: (
        west: (
          (id: "to_ddr", name: "", vertical: false),
        ),
        north: (
          (id: "to_selector", name: "", vertical: true),
        ),
        east: (
          (id: "from_cu", name: "", vertical: false),
        ),
      ),
    )

    // 1. Raster Frontend Block (Top)
    element.block(
      x: 0,
      y: -0.5,
      w: 15,
      h: 6,
      id: "frontend",
      fill: util.colors.blue,
      name: [
        #text("Raster Frontend", size: 18pt, weight: "bold") \ \
        #text("Initial per Triangle Setup\nand Bounding Box calculation & aligment", size: 10pt, weight: "regular")
      ],
      ports: (
        north: (
          (id: "vertex_in", name: "", vertical: true),
        ),
        south: (
          (id: "data_out", name: "", vertical: true),
        ),
        west: (
          (id: "from_cp", name: "", vertical: false),
        ),
      ),
    )

    // 2. Thread Orchestrator Block (Middle)
    element.block(
      x: 0,
      y: -9,
      w: 15,
      h: 6,
      id: "orchestrator",
      fill: util.colors.pink,
      name: [
        #text("Thread Orchestrator", size: 18pt, weight: "bold") \ \
        #text(
          "Traverses the bounding box in a snake pattern\ninterpolating the per-pixel (per-thread) coeeficients\n and synchronizes the threads\n",
          size: 9pt,
          weight: "regular",
        )

        #text(
          [Pixel regection ($e_(0,1,2)>=0$ and Z) is done on threads],
          size: 9pt,
          weight: "regular",
        )
      ],
      ports: (
        north: (
          (id: "data_in", name: "", vertical: true),
        ),
        south: (
          (id: "thread_data", name: "", vertical: true),
        ),
      ),
    )

    // Control Unit (CU) has been moved to the top left column

    // 3. Parallel Threads (Bottom)
    for i in range(4) {
      element.block(
        x: i * 4,
        y: -20,
        w: 3,
        h: 8,
        id: "thread" + str(i),
        fill: util.colors.green,
        name: [ #text("Thread " + str(i) + "\n\n\n\n", size: 13pt, weight: "bold") ],
        ports: (
          north: (
            (id: "data_in", name: "", vertical: true),
            (id: "ctrl_in", name: "", vertical: true),
          ),
          south: (
            (id: "to_fb", name: "", vertical: true),
            (id: "to_zb", name: "", vertical: true),
          ),
        ),
      )

      element.block(
        x: i * 4 + 0.5,
        y: -19.25,
        w: 2,
        h: 2,
        id: "L1Cache" + str(i),
        fill: util.colors.orange,
        name: [ #text("L1\nCache", size: 12pt, weight: "bold") ],
        ports: (
          north: (
            (id: "to_l2", name: "", vertical: false),
          ),
        ),
      )
    }

    // Command Stream input is now defined at the top CU height

    // CP Control Bus and connections are defined at the end of the file after block definitions to ensure coordinate resolution

    // Top-Level inputs to Frontend (North)
    // wire.stub("frontend-port-vertex_in", "north", name: "Vertex In", length: 2em)

    // Connect Frontend (South) to Orchestrator (North) (Bold combined data bus)
    draw.line(
      "frontend-port-data_out",
      "orchestrator-port-data_in",
      stroke: (thickness: 2.5pt, paint: black),
      mark: (end: ">", fill: black, size: 0.6),
    )
    draw.content(
      (7.5, -1.75),
      text(box(fill: white, inset: 2pt)[Coefficients, BB Data, invArea, Vertex], size: 10pt, weight: "bold"),
    )

    // Connect Orchestrator (South) to Threads (North) with a split bus
    let split-y = -10.5
    draw.line(
      "orchestrator-port-thread_data",
      (7.5, split-y),
      stroke: (thickness: 2pt, paint: black),
    )
    draw.line(
      (0.95, split-y),
      (13.05, split-y),
      stroke: (thickness: 2pt, paint: black),
    )
    for i in range(4) {
      let thread-x = i * 4 + 1.0
      draw.line(
        (thread-x, split-y),
        "thread" + str(i) + "-port-data_in",
        stroke: (thickness: 2pt, paint: black),
        mark: (end: ">", fill: black, size: 0.6),
      )
    }
    draw.content(
      (8, -9.7),
      anchor: "west",
      text("per-thread data", size: 9.5pt, weight: "bold"),
    )

    // L2 Cache Block on the left side (centered vertically to Thread blocks)
    element.block(
      x: -7,
      y: -18,
      w: 3,
      h: 4,
      id: "L2Cache",
      fill: util.colors.yellow,
      name: [ #text("L2\nCache", size: 14pt, weight: "bold") ],
      ports: (
        east: (
          (id: "to_l1", name: "", vertical: false),
        ),
        west: (
          (id: "to_ddr", name: "", vertical: false),
        ),
      ),
    )

    // Connect L1 Caches to L2 Cache with a bus that runs horizontally through the threads
    let l2-bus-y = -16.0
    draw.line(
      "L2Cache-port-to_l1",
      (13.5, l2-bus-y),
      stroke: (thickness: 1pt, paint: black),
    )
    for i in range(4) {
      let branch-x = i * 4 + 1.5
      draw.line(
        (branch-x, l2-bus-y),
        "L1Cache" + str(i) + "-port-to_l2",
        stroke: (thickness: 1pt, paint: black),
        mark: (end: ">", fill: black, size: 0.5),
      )
    }

    // 2D DMA Engine Block (Left side)
    element.block(
      x: -7,
      y: -27.5,
      w: 3,
      h: 5,
      id: "DMA",
      fill: silver.darken(30%),
      name: [ #text("2D DMA", size: 13pt, weight: "bold") ],
      ports: (
        west: (
          (id: "to_ddr", name: "", vertical: false),
        ),
        east: (
          (id: "to_buf", name: "", vertical: false),
          (id: "from_cp", name: "", vertical: false),
        ),
      ),
    )

    // Tile Frame Buffer Block (Bottom, left aligned)
    element.block(
      x: 0.5,
      y: -27.5,
      w: 6,
      h: 5,
      id: "FrameBuffer",
      fill: eastern,
      name: [ #text("Tile Frame Buffer", size: 12pt, weight: "bold") ],
      ports: (
        north: (
          (id: "fb_in", name: "", vertical: true),
        ),
        west: (
          (id: "from_dma", name: "", vertical: false),
          (id: "from_cp", name: "", vertical: false),
        ),
      ),
    )

    // Tile Z-Buffer Block (Bottom, right aligned)
    element.block(
      x: 8.5,
      y: -27.5,
      w: 6,
      h: 5,
      id: "ZBuffer",
      fill: util.colors.purple,
      name: [ #text("Tile Z-Buffer", size: 12pt, weight: "bold") ],
      ports: (
        north: (
          (id: "zb_in", name: "", vertical: true),
        ),
      ),
    )

    // Connect L2 Cache to DDR (L2 goes in, thick arrow)
    draw.line(
      (-10.0, -16.0),
      "L2Cache-port-to_ddr",
      stroke: (thickness: 2.5pt, paint: black),
      mark: (end: ">", fill: black, size: 0.6),
    )
    draw.content(
      (-10.2, -16.0),
      anchor: "east",
      text("DDR", size: 16pt, weight: 500),
    )

    // Connect 2D DMA Engine to DDR (DMA goes out to DDR, thick arrow)
    draw.line(
      "DMA-port-to_ddr",
      (-10.0, -25.0),
      stroke: (thickness: 2.5pt, paint: black),
      mark: (end: ">", fill: black, size: 0.6),
    )
    draw.content(
      (-10.2, -25.0),
      anchor: "east",
      text("DDR", size: 16pt, weight: 500),
    )

    // Connect Threads (South) to Tile Frame Buffer (North) - FB Bus
    let fb-bus-y = -21.0
    draw.line(
      "FrameBuffer-port-fb_in",
      (3.5, fb-bus-y),
      stroke: (thickness: 1.5pt, paint: black),
      mark: (start: ">", fill: black, size: 0.5),
    )
    draw.line(
      (1.0, fb-bus-y),
      (13.0, fb-bus-y),
      stroke: (thickness: 1.5pt, paint: black),
    )
    for i in range(4) {
      let branch-x = i * 4 + 1.0
      draw.line(
        "thread" + str(i) + "-port-to_fb",
        (branch-x, fb-bus-y),
        stroke: (thickness: 1.5pt, paint: black),
        mark: (start: ">", fill: black, size: 0.5),
      )
    }

    // Connect Threads (South) to Tile Z-Buffer (North) - ZB Bus
    let zb-bus-y = -21.5
    draw.line(
      "ZBuffer-port-zb_in",
      (11.5, zb-bus-y),
      stroke: (thickness: 1.5pt, paint: black),
      mark: (start: ">", fill: black, size: 0.5),
    )
    draw.line(
      (2.0, zb-bus-y),
      (14.0, zb-bus-y),
      stroke: (thickness: 1.5pt, paint: black),
    )
    for i in range(4) {
      let branch-x = i * 4 + 2.0
      draw.line(
        "thread" + str(i) + "-port-to_zb",
        (branch-x, zb-bus-y),
        stroke: (thickness: 1.5pt, paint: black),
        mark: (start: ">", fill: black, size: 0.5),
      )
    }

    // Connect 2D DMA Engine (East) directly to Tile Frame Buffer (West)
    draw.line(
      "DMA-port-to_buf",
      "FrameBuffer-port-from_dma",
      stroke: (thickness: 1.5pt, paint: black),
      mark: (start: ">", fill: black, size: 0.6),
    )

    // Host Config/Cmd Input to CP (at new top height)
    draw.line(
      (-12.0, 15.0),
      "CP-port-host_in",
      stroke: (thickness: 1.5pt, paint: black),
      mark: (end: ">", fill: black, size: 0.5),
    )
    draw.content(
      (-12.2, 15.0),
      anchor: "east",
      text("Command Stream", size: 10pt, weight: "bold"),
    )

    // CP control connections using circuiteria wires (single fanning-out bus)
    let ctrl-bus-x = -1.5
    let ctrl-thread-y = -11.0

    // Vertical Control Bus Trunk
    wire.wire(
      "w_ctrl_trunk",
      (
        (horizontal: (ctrl-bus-x, 0), vertical: "CP-port-to_ctrl"),
        (horizontal: (ctrl-bus-x, 0), vertical: "DMA-port-from_cp"),
      ),
      style: "direct",
      dashed: true,
    )

    // Branch from CP to Trunk
    wire.wire(
      "w_cp_to_trunk",
      ("CP-port-to_ctrl", (horizontal: (ctrl-bus-x, 0), vertical: "CP-port-to_ctrl")),
      style: "direct",
      dashed: true,
    )

    // Branch to Frontend
    wire.wire(
      "w_trunk_to_fe",
      ((horizontal: (ctrl-bus-x, 0), vertical: "frontend-port-from_cp"), "frontend-port-from_cp"),
      style: "direct",
      directed: true,
      dashed: true,
    )

    // Horizontal control line above threads
    wire.wire(
      "w_thread_ctrl_bus",
      ((ctrl-bus-x, ctrl-thread-y), (14.0, ctrl-thread-y)),
      style: "direct",
      dashed: true,
    )

    // Thread branches
    for i in range(4) {
      let branch-x = i * 4 + 2.0
      wire.wire(
        "w_trunk_to_t" + str(i),
        ((branch-x, ctrl-thread-y), "thread" + str(i) + "-port-ctrl_in"),
        style: "direct",
        directed: true,
        dashed: true,
      )
    }

    // Branch to Tile Frame Buffer
    wire.wire(
      "w_trunk_to_fb",
      ((horizontal: (ctrl-bus-x, 0), vertical: "FrameBuffer-port-from_cp"), "FrameBuffer-port-from_cp"),
      style: "direct",
      directed: true,
      dashed: true,
    )

    // Branch to 2D DMA
    wire.wire(
      "w_trunk_to_dma",
      ((horizontal: (ctrl-bus-x, 0), vertical: "DMA-port-from_cp"), "DMA-port-from_cp"),
      style: "direct",
      directed: true,
      dashed: true,
    )

    // Visibility DMA DDR Stub (DDR input)
    draw.line(
      (-12.0, 2.5),
      "VisDMA-port-to_ddr",
      stroke: (thickness: 2.5pt, paint: black),
      mark: (end: ">", fill: black, size: 0.6),
    )
    draw.content(
      (-12.2, 2.5),
      anchor: "east",
      text("DDR", size: 16pt, weight: 500),
    )

    // Triangle DMA DDR Stub (DDR input)
    draw.line(
      (-12.0, 10.5),
      "TriDMA-port-to_ddr",
      stroke: (thickness: 2.5pt, paint: black),
      mark: (end: ">", fill: black, size: 0.6),
    )
    draw.content(
      (-12.2, 10.5),
      anchor: "east",
      text("DDR", size: 16pt, weight: 500),
    )

    // Connect Visibility DMA to Triangle Selector (Visibility Stream)
    wire.wire(
      "w_vis_dma_to_selector",
      ("VisDMA-port-to_selector", "TriSelector-port-from_vis_dma"),
      style: "direct",
      directed: true,
    )
    draw.content(
      (-8.5, 4.5),
      anchor: "west",
      text(box(fill: white, inset: 2pt)[*Visibility Stream*], size: 10pt),
    )

    // Connect Triangle Selector to Triangle DMA (no label)
    wire.wire(
      "w_selector_to_tri_dma",
      ("TriSelector-port-to_tri_dma", "TriDMA-port-from_selector"),
      style: "direct",
      directed: true,
    )

    // Branch to Visibility DMA
    wire.wire(
      "w_trunk_to_vis_dma",
      ((horizontal: (ctrl-bus-x, 0), vertical: "VisDMA-port-from_cu"), "VisDMA-port-from_cu"),
      style: "direct",
      directed: true,
      dashed: true,
    )

    // Connect Triangle DMA to Triangle FIFO (Bold data path)
    draw.line(
      "TriDMA-port-to_fifo",
      "TriFIFO-port-from_dma",
      stroke: (thickness: 2.5pt, paint: black),
      mark: (end: ">", fill: black, size: 0.6),
    )
    draw.content(
      (0.5, 10.8),
      anchor: "south",
      text("Triangles", size: 10pt, weight: "bold"),
    )

    // Connect Triangle FIFO to Frontend (Bold data path)
    draw.line(
      "TriFIFO-port-to_frontend",
      "frontend-port-vertex_in",
      stroke: (thickness: 2.5pt, paint: black),
      mark: (end: ">", fill: black, size: 0.6),
    )
    draw.content(
      (7.5, 7.25),
      text(box(fill: white, inset: 2pt)[Vertex In], size: 10pt, weight: "bold"),
    )


    // Control bus junction dots
    draw.circle((horizontal: (ctrl-bus-x, 0), vertical: "VisDMA-port-from_cu"), radius: 0.09, fill: black, stroke: none)
    draw.circle((ctrl-bus-x, -11.0), radius: 0.09, fill: black, stroke: none)
    draw.circle((horizontal: (ctrl-bus-x, 0), vertical: "DMA-port-from_cp"), radius: 0.09, fill: black, stroke: none)
  })
]
