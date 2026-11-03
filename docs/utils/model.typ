
#let model(descriptors) = {
  let fields = ()
  let cursor = 0
  for d in descriptors {
    assert(
      d.width > 0,
      message: "field " + repr(d.label) + ": width must be > 0",
    )

    let anchor = d.at("anchor", default: none)
    let start = if anchor != none { anchor } else { cursor }
    if start > cursor {
      fields.push((
        kind: "gap",
        start: cursor,
        end: start - 1,
        label: none,
        fill: none,
      ))
    }

    let end = start + d.width - 1
    fields.push((
      kind: d.kind,
      start: start,
      end: end,
      label: d.label,
      fill: d.at("fill", default: none),
      used: d.at("used", default: none),
    ))

    cursor = calc.max(cursor, end + 1)
  }
  fields
}
