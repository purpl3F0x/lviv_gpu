
#let _byte-aligned(f) = calc.rem(f.start, 8) == 0 and calc.rem(f.end + 1, 8) == 0

#let layout(
  fields,
  scale: 0.3,
  min-height: 0.55,
  max-height: 2.2,
  gap: 0.0,
) = {
  let entries = ()
  let top = 0.0
  let i = 0
  while i < fields.len() {
    let f = fields.at(i)
    let entry = if _byte-aligned(f) {
      i += 1
      let size = f.end - f.start + 1
      let raw = size / 8 * scale
      (
        type: "box",
        kind: f.kind,
        label: f.label,
        fill: f.fill,
        used: f.at("used", default: none),
        start: f.start,
        size: size,
        height: calc.max(min-height, calc.min(max-height, raw)),
        clamped: raw > max-height,
      )
    } else {
      // gather fields until the run returns to a byte boundary
      let start = calc.quo(f.start, 8) * 8
      let cells = ()
      while i < fields.len() {
        let g = fields.at(i)
        i += 1
        cells.push((
          kind: g.kind,
          label: g.label,
          fill: g.fill,
          start: g.start,
          size: g.end - g.start + 1,
        ))
        if calc.rem(g.end + 1, 8) == 0 { break }
      }
      let size = cells.last().start + cells.last().size - start
      (
        type: "bits",
        start: start,
        size: size,
        height: calc.max(min-height, size / 8 * scale),
        clamped: false,
        cells: cells,
      )
    }
    entries.push(entry + (top: top))
    top += entry.height + gap
  }
  entries
}
