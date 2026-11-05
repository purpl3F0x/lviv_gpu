#import "@preview/cetz:0.5.2" as cetz
#import "@preview/splash:0.5.0": google

// The visibility DMA's figures. Distances are canvas units (cm).

#let _active = google.dark-yellow-1.lighten(40%)
#let _other = google.dark-blue-1.lighten(40%)
#let _edge = google.dark-red-1

#let _t(body, size: 8pt, fill: black) = text(font: "Cascadia Mono", size: size, fill: fill, body)

// The bitmap's 4 KiB pages, a row per chunk, a column per tile, one tile's lit
#let vis_layout() = cetz.canvas({
  import cetz.draw: content, line, rect
  let w = 2.2
  let h = 0.75
  let active = 1
  let tiles = ("tile 0", "tile 1", "tile 2", "…", "tile T-1")
  let pages = (
    ("0", "1", "2", "…", "T-1"),
    ("T", "T+1", "T+2", "…", "2T-1"),
    ("2T", "2T+1", "2T+2", "…", "3T-1"),
  )

  for (x, name) in tiles.enumerate() {
    content(((x + 0.5) * w, 0.3), _t(name))
  }
  for (y, row) in pages.enumerate() {
    let top = -y * h
    content((-0.2, top - h / 2), _t("chunk " + str(y)), anchor: "east")
    for (x, page) in row.enumerate() {
      rect((x * w, top), ((x + 1) * w, top - h), stroke: 0.8pt, fill: if x == active { _active })
      content(((x + 0.5) * w, top - h / 2), _t(page))
    }
  }
  // Read down the lit column, a burst a page
  for y in (1, 2) {
    let x = (active + 0.85) * w
    line((x, -y * h + 0.2), (x, -y * h - 0.2), stroke: 1pt, mark: (end: ">", fill: black))
  }
  content(((active + 0.5) * w, -3 * h - 0.25), _t("…"))
})

// Beats of a tile, bit 0 on the left: its runs, their edges and what becomes of each beat
#let vis_runs() = cetz.canvas({
  import cetz.draw: content, line, rect
  let bit = 0.07
  let bar = 0.42
  let pitch = 1.0
  let runs = ((180, 404, _active), (440, 460, _other))
  let beats = ("no edge: dropped", "1 edge: queued", "no edge: dropped", "3 edges: queued")
  let width = 128 * bit

  content((0, 0.25), _t("bit 0", size: 7pt), anchor: "west")
  content((width, 0.25), _t("bit 127", size: 7pt), anchor: "east")

  for (k, status) in beats.enumerate() {
    let first = 128 * k
    let top = -k * pitch
    let x(t) = (t - first) * bit

    content((-0.25, top - 0.1), _t("beat " + str(k)), anchor: "east")
    content(
      (-0.25, top - 0.38),
      _t(str(first) + ".." + str(first + 127), size: 7pt),
      anchor: "east",
    )

    for (a, b, fill) in runs {
      let lo = calc.max(a, first)
      let hi = calc.min(b, first + 128)
      if lo < hi {
        rect((x(lo), top), (x(hi), top - bar), stroke: none, fill: fill)
      }
    }
    rect((0, top), (width, top - bar), stroke: 0.8pt)

    for (a, b, fill) in runs {
      for edge in (a, b) {
        if edge >= first and edge < first + 128 {
          line((x(edge), top + 0.1), (x(edge), top - bar), stroke: 1.2pt + _edge)
          content((x(edge), top + 0.1), _t(str(edge), size: 7pt, fill: _edge), anchor: "south")
        }
      }
    }

    content((width + 0.25, top - bar / 2), _t(status), anchor: "west")
  }

  let y = -beats.len() * pitch + 0.05
  for (i, (fill, line-text)) in (
    (_active, "command: 224 triangles at TRI_BASE + 180 × 96 B"),
    (_other, "command:  20 triangles at TRI_BASE + 440 × 96 B"),
  ).enumerate() {
    let top = y - i * 0.5
    rect((0, top), (0.35, top - 0.3), stroke: 0.6pt, fill: fill)
    content((0.5, top - 0.15), _t(line-text), anchor: "west")
  }
})
