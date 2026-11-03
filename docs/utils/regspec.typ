#import "@preview/rivet:0.3.1": config, schema
#import "@preview/oxifmt:1.0.0": strfmt

#let entry_row_maker(is_reserved, ..cells) = {
  cells
    .pos()
    .map(c => table.cell(
      fill: if is_reserved { rgb("eee") } else { none },
      text(c, fill: if is_reserved { rgb("bbb") } else { black }),
    ))
}

#let frame(stroke) = (x, y) => (
  left: if x > 0 { 0pt } else { stroke },
  right: stroke,
  top: if y < 2 { stroke } else { 0pt },
  bottom: stroke,
)

// data: the parsed regmap JSON; a path would resolve relative to this file
#let reg_spec(data) = {
  for slice in data.slices [
    #block(breakable: false)[
      === #slice.name (#strfmt("0x{:02X}", slice.addr))
      #if "doc" in slice and slice.doc != "" [
        #text(fill: luma(60))[#slice.doc]
      ]

      // Construct rivet 'ranges' dictionary dynamically
      #let ranges-dict = (:)
      #let colors-dict = (:)

      #for fld in slice.fields {
        // Determine key: "start" for 1-bit, "end-start" for multi-bit
        let key = str(fld.pos.end) + "-" + str(fld.pos.start)

        let is-reserved = (fld.name == "--")
        if is-reserved { continue }

        let entry = (
          name: if (fld.width > 2) { fld.name } else { "" },
          description: if (fld.width <= 2) { fld.name } else { "" },
        )

        ranges-dict.insert(key, entry)
        colors-dict.insert(key, eastern.lighten(40%))
      }

      #let reg_schema = schema.load((
        structures: (
          main: (
            bits: 32,
            ranges: ranges-dict,
          ),
        ),
        colors: (
          main: colors-dict,
        ),
      ))


      #schema.render(
        reg_schema,
        config: config.config(
          default-font-family: "Cascadia Mono",
          italic-font-family: "Cascadia Mono",
          default-font-size: 12pt,
          italic-font-size: 12pt,
          full-page: false,
          bit-width: 20,
          bit-height: 25,
          // force-descs-on-side: true,
          // arrow-label-distance: 200,
          arrow-margin: 20,
          // arrow-size: 0,
          left-labels: true,
          description-margin: 0,
          // dash-space: -100,
          // values-gap: 10000,
          margins: (0, 0, 0, 0),
          all-bit-i: false,
        ),
      )

      // #v(0.5em)

      #show table.cell: set text(size: 9pt)

      // Render register field description table
      #table(
        columns: (1fr, 2fr, 0.8fr, auto, 4fr),
        align: (center + horizon, left + horizon, center + horizon, center + horizon, left + horizon),
        stroke: (x, y) => (
          left: if (x > 0) and (y > 0) {
            (dash: "dashed", thickness: 0.5pt, paint: black)
          } else { 1pt },
          right: 1pt,
          top: if y < 2 { 1pt } else { (dash: "dashed", thickness: 0.5pt, paint: black) },
          bottom: 1pt,
        ),
        inset: (x: 0.5em, y: 0.5em),
        fill: (x, y) => if y == 0 { rgb("BBB") } else { none },
        table.header([*Section*], [*Field Name*], [*R/W*], [*Reset*], [*Description*]),

        ..slice
          .fields
          .rev()
          .map(f => (
            entry_row_maker(
              f.name == "--",
              strfmt("[{}]", if f.pos.start == f.pos.end { f.pos.start } else {
                str(f.pos.end) + ":" + str(f.pos.start)
              }),
              [ #f.name],
              [ #f.access ],
              [ #strfmt("{:#X}", f.reset)],
              [ #f.doc ],
            )
          ))
          .flatten(),
      )

      #v(3em)
    ]
  ]
}
