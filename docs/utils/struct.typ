#import "@preview/cetz:0.5.2" as cetz
#import "@preview/oxifmt:1.0.0": strfmt
#import "model.typ": model
#import "layout.typ": layout


// Field constructors, the same vocabulary as packet. Widths are in bits; the
// first positional argument, if any, is the label.
#let _field(kind, width, rest, anchor: none, fill: none, used: none) = (
  kind: kind,
  width: width,
  label: rest.pos().at(0, default: none),
  anchor: anchor,
  fill: fill,
  used: used,
)

// `used: (bits, word)`: only the low `bits` of each `word`-bit word are used
#let bytes(n, ..rest, at: none, fill: none, used: none) = _field(
  "field",
  n * 8,
  rest,
  anchor: if at != none { at * 8 },
  fill: fill,
  used: used,
)
#let bits(n, ..rest, at: none, fill: none) = _field(
  "field",
  n,
  rest,
  anchor: at,
  fill: fill,
)
#let gap(n, ..rest) = _field("gap", n, rest)
#let reserved(n, ..rest) = _field("field", n, rest)


// Fixed look, not exposed. Edit here if you want something different.
// Distances are canvas units (cm).
#let _look = (
  meta-ink: black, // addresses, sizes, bit offsets
  gap-stroke: (paint: luma(150), thickness: 0.6pt, dash: "dashed"),
  gap-fill: rgb("eee"),
  gap-ink: rgb("bbb"),
  leader-stroke: 0.5pt + luma(110),
  side-gap: 0.15, // box edge to the address/size columns
  addr-inset: 0.15, // addresses sit this far inside a box's top/bottom edge
  col-gap: 0.08, // space between cells of a bit strip
  label-pad: 0.1, // padding inside a box before a label wraps
  callout-drop: 0.4, // leader length below a box
  callout-line-h: 0.45, // spacing between stacked bit-strip callouts
  callout-bottom: 0.2, // space under a callout before the next box
  cut-at: 0.55, // where the "~" cut sits, as a fraction down the box
  cut-amp: 0.12, // height of the "~" wave
  cut-gap: 0.2, // thickness of the band in the "~"
  brace-amp: 0.2, // how far a group's brace sticks out
  brace-label-gap: 0.15, // brace tip to its label
)

#let _cm(l) = l / 1cm
// a byte address, zero-padded hex, with a `:bit` suffix for sub-byte starts
#let _addr(bitpos, digits) = {
  let bit = calc.rem(bitpos, 8)
  let suffix = if bit != 0 { ":" + str(bit) } else { "" }
  // `w` counts the "0x" prefix too
  strfmt("{:#0w$X}{}", calc.quo(bitpos, 8), suffix, w: digits + 2)
}

#let _size-str(bits) = if calc.rem(bits, 8) == 0 {
  str(calc.quo(bits, 8)) + "B"
} else {
  str(bits) + "b"
}

// A field's outline from `top` down to `bot`. With `cut` (a y position) the box
// is split there by a wavy "~" band: a clamped field is drawn shorter than its
// true size. A gap is dashed and sits on a lower layer, so wherever it meets a
// solid box the solid edge stays on top of the dashes.
#let _shape(x0, x1, top, bot, style, gap: false, cut: none) = {
  import cetz.draw: bezier, line, merge-path, on-layer, rect
  let style = if gap { (stroke: _look.gap-stroke, fill: _look.gap-fill) } else { style }
  let body = if cut == none {
    rect((x0, bot), (x1, top), ..style)
  } else {
    // one S-shaped period across the box; `k` makes the peak exactly `cut-amp`
    let k = 2 * calc.sqrt(3) * _look.cut-amp
    let w = x1 - x0
    let wave(y) = bezier((x0, y), (x1, y), (x0 + w / 3, y + k), (x1 - w / 3, y - k))
    let low = cut - _look.cut-gap
    merge-path(close: true, ..style, {
      wave(cut)
      line((x1, cut), (x1, top), (x0, top), (x0, cut))
    })
    merge-path(close: true, ..style, {
      wave(low)
      line((x1, low), (x1, bot), (x0, bot), (x0, low))
    })
  }
  if gap { on-layer(-1, body) } else { body }
}

// Fit `label`, set in text `style`, in a `w`×`h` box: on one line if it fits,
// else wrapped to the box width if that stays within two lines and `h`. Returns
// the body, its height, and whether it fits inside; if not, the caller hangs it
// below the box.
#let _fit(label, w, h, style) = {
  let one-line = text(..style, label)
  if _cm(measure(one-line).width) <= w {
    return (body: one-line, height: _cm(measure(one-line).height), inside: true)
  }
  // justification off, so a wrapped label doesn't inherit `par(justify: true)`
  let wrapped = box(width: w * 1cm, {
    set par(justify: false)
    align(center, one-line)
  })
  let height = _cm(measure(wrapped).height)
  let two-lines = _cm(measure(box(width: w * 1cm, text(..style)[A\ A])).height)
  (body: wrapped, height: height, inside: height <= two-lines + 0.01 and height <= h)
}


// struct: vertical "memory map" view of a byte-region cluster. Fields stack
// top-down with box height proportional to byte size, clamped between
// `min-height` and `max-height` (clamped boxes get a "~" cut). Byte addresses
// run down the left edge, sizes down the right. Same element vocabulary as
// packet (`bytes`/`bits`/`gap`/`reserved`); no row-wrapping. Returns content.
//
//   width        box width
//   byte-height  height per byte before clamping
//   min-height   smallest box height (tiny fields are floored to this)
//   max-height   tallest box height (bigger fields are cut with a "~")
//   spacing      vertical space between boxes
//   size         base text size
//   label-size   field label size (default: `size`)
//   meta-size    address/size/bit-offset size (default: 80% of `label-size`)
//   font         font for all text: labels, addresses, sizes, bit offsets
//                (default: DejaVu Sans Mono, Typst's built-in monospace)
//   stroke       box outline
//   fill         a color, or an array of colors cycled over the boxes in order.
//                A field's own `fill` wins and does not use up a slot.
//   end-labels   also show each box's last-byte address at its bottom edge
//   groups       braces right of the sizes, each over its bytes (in proportion
//                inside a box): an array of (at: byte, size: bytes, label: content)
#let struct(
  ..args,
  width: 4cm,
  byte-height: 0.25pt,
  min-height: 20pt,
  max-height: 65pt,
  spacing: 0pt,
  size: 10pt,
  label-size: auto,
  meta-size: auto,
  font: "DejaVu Sans Mono",
  stroke: 0.8pt + black,
  fill: (luma(200), white),
  end-labels: true,
  groups: (),
) = context {
  let label-size = if label-size == auto { size } else { label-size }
  let meta-size = if meta-size == auto { label-size * 0.8 } else { meta-size }
  let fills = if type(fill) == array { fill } else { (fill,) }
  let ink = text.fill
  let entries = layout(
    model(args.pos()),
    scale: _cm(byte-height),
    min-height: _cm(min-height),
    max-height: _cm(max-height),
    gap: _cm(spacing),
  )

  // pad addresses to the width of the struct's end so they line up: 0x00 … 0x10
  let digits = if entries.len() == 0 { 1 } else {
    let last = entries.last()
    strfmt("{:X}", calc.quo(last.start + last.size, 8)).len()
  }
  let label-style = (font: font, size: label-size)
  let meta(s) = text(font: font, size: meta-size, fill: _look.meta-ink, s)
  let x0 = 0.0
  let x1 = _cm(width)
  let pad = _look.label-pad

  cetz.canvas({
    import cetz.draw: content, line
    let shift = 0.0 // how far callouts hung below earlier boxes push the rest down
    let slot-i = 0 // how many boxes have taken an automatic fill so far
    let spans = () // each box's bits and edges, for the group braces
    let bot = 0.0
    for e in entries {
      let top = -(e.top + shift)
      bot = top - e.height
      let slot = fills.at(calc.rem(slot-i, fills.len()))

      if e.type == "box" {
        let is-gap = e.kind == "gap"
        let cut = if e.clamped { top - _look.cut-at * e.height }
        let box-fill = if e.fill != none { e.fill } else { slot }
        if e.used == none {
          _shape(x0, x1, top, bot, (stroke: stroke, fill: box-fill), gap: is-gap, cut: cut)
        } else {
          // the used low bits lit (on the right, as in a register), the rest as a gap
          let (bits, word) = e.used
          let ux = x1 - bits / word * (x1 - x0)
          _shape(x0, ux, top, bot, none, gap: true, cut: cut)
          _shape(ux, x1, top, bot, (stroke: stroke, fill: box-fill), cut: cut)
          _shape(x0, x1, top, bot, (stroke: stroke, fill: none), cut: cut)
          let uy = if cut == none { (top + bot) / 2 } else { (top + cut + _look.cut-amp) / 2 }
          content(((ux + x1) / 2, uy), meta(str(bits - 1) + ":0"))
        }

        // Label: centred in the box (above the "~" when cut) on one or two
        // lines, else hung below the box on a leader.
        if e.label != none {
          let room = if cut == none { e.height } else { top - cut - _look.cut-amp }
          let label-ink = if is-gap { _look.gap-ink } else { ink }
          let fit = _fit(e.label, x1 - x0 - 2 * pad, room - 2 * pad, label-style + (fill: label-ink))
          let cx = (x0 + x1) / 2
          if fit.inside {
            content((cx, top - room / 2), fit.body)
          } else {
            let y = bot - _look.callout-drop
            line((cx, bot), (cx, y), stroke: _look.leader-stroke)
            content((cx, y), fit.body, anchor: "north")
            shift += _look.callout-drop + fit.height + _look.callout-bottom
          }
        }

        // a gap, or a field with its own fill, doesn't advance the alternation
        if not is-gap and e.fill == none { slot-i += 1 }
      } else {
        // A bit-carved byte-run: one strip subdivided horizontally into cells.
        // A cell shows its name inline if it fits, else its bit offset and a
        // leader callout (a 1-bit cell can't hold a name). The strip takes one
        // automatic fill; a cell's own `fill` overrides it.
        let bit-x(b) = x0 + (b - e.start) / e.size * (x1 - x0)
        let last-j = e.cells.len() - 1
        let callouts = ()
        for (j, c) in e.cells.enumerate() {
          // float the cells apart by `col-gap`, but keep the strip's outer
          // edges flush with the boxes above and below
          let cx0 = bit-x(c.start) + if j == 0 { 0.0 } else { _look.col-gap / 2 }
          let cx1 = bit-x(c.start + c.size) - if j == last-j { 0.0 } else { _look.col-gap / 2 }
          let is-gap = c.kind == "gap"
          let cell-fill = if c.fill != none { c.fill } else { slot }
          _shape(cx0, cx1, top, bot, (stroke: stroke, fill: cell-fill), gap: is-gap)

          let mid = ((cx0 + cx1) / 2, (top + bot) / 2)
          let name = text(..label-style, fill: if is-gap { _look.gap-ink } else { ink }, c.label)
          if c.label != none and _cm(measure(name).width) <= cx1 - cx0 - 2 * pad {
            content(mid, name)
          } else {
            content(mid, meta(str(c.start - e.start)))
            if c.label != none { callouts.push((x: mid.at(0), label: c.label)) }
          }
        }

        // Names that did not fit, stacked in a band below the strip and ordered
        // left-to-right so the drop-then-turn leaders never cross. They sit
        // outside the frame (left of x0), so a leader can't cut through text.
        let gutter = x0 - _look.side-gap
        for (k, c) in callouts.sorted(key: c => c.x).enumerate() {
          let y = bot - _look.callout-drop - k * _look.callout-line-h
          line((c.x, bot), (c.x, y), (gutter, y), stroke: _look.leader-stroke)
          content((gutter, y), text(..label-style, c.label), anchor: "east")
        }
        if callouts.len() > 0 {
          shift += _look.callout-drop + (callouts.len() - 1) * _look.callout-line-h + _look.callout-bottom
        }
        slot-i += 1
      }

      // Address column (left): the start address hangs just inside the box's
      // top edge and the end address (inclusive last byte) just inside its
      // bottom, so at each boundary the previous end stacks right above the
      // next start, like a datasheet memory map.
      let ax = x0 - _look.side-gap
      content((ax, top - _look.addr-inset), meta(_addr(e.start, digits)), anchor: "north-east")
      if end-labels {
        content((ax, bot + _look.addr-inset), meta(_addr(e.start + e.size - 8, digits)), anchor: "south-east")
      }

      // size column (right), centred on the box
      content((x1 + _look.side-gap, (top + bot) / 2), meta(_size-str(e.size)), anchor: "west")
      spans.push((start: e.start, end: e.start + e.size, top: top, bot: bot))
    }

    // Group braces, clear of the widest size label
    if groups.len() > 0 and entries.len() > 0 {
      import cetz.decorations: brace
      let size-w = calc.max(..entries.map(e => _cm(measure(meta(_size-str(e.size))).width)))
      let bx = x1 + 2 * _look.side-gap + size-w
      // y of a bit position: its box's edge, or in proportion inside the box
      let y-at(bit) = {
        for s in spans {
          if bit >= s.start and bit <= s.end {
            return s.top - (bit - s.start) / (s.end - s.start) * (s.top - s.bot)
          }
        }
        none
      }
      for (i, g) in groups.enumerate() {
        let y0 = y-at(g.at * 8)
        let y1 = y-at((g.at + g.size) * 8)
        if y0 != none and y1 != none {
          let name = "group-" + str(i)
          brace(
            (bx, y0),
            (bx, y1),
            amplitude: _look.brace-amp,
            content-offset: _look.brace-label-gap,
            stroke: stroke,
            name: name,
          )
          content(name + ".content", text(..label-style, g.label), anchor: "west")
        }
      }
    }

    // With end labels off, still mark where the struct ends: the last byte's
    // address, level with the bottom edge.
    if not end-labels and entries.len() > 0 {
      let last = entries.last()
      content((x0 - _look.side-gap, bot), meta(_addr(last.start + last.size - 8, digits)), anchor: "east")
    }
  })
}
