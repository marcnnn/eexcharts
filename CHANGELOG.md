# Changelog

Notable changes to EexCharts. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `EexCharts.PDF`: charts drawn as PDF operators, for
  [PrawnEx](https://hex.pm/packages/prawn_ex). `ops/4` returns the drawing
  operations as plain tuples and needs no dependency; `to_pdf/4` writes a
  one-page document and needs `prawn_ex` with its graphics-state operators
  (`concat_matrix`, `set_dash`, `set_line_cap`, `set_line_join`), which are not
  yet in a Hex release. Gradients degrade to their first stop, and fill and
  stroke share one opacity. See `EexCharts.PDF.Ops`.
- Chart types and features beyond ApexCharts v4.7.0, built from public
  release-note descriptions only (no v5+ code; provenance in
  `docs/PARITY.md`):
  - `:histogram` with automatic (Freedman-Diaconis, Sturges, Scott, sqrt) or
    fixed bins, `:count` / `:probability` / `:percent` / `:density`
    normalisation and cumulative output; `:violin` with Gaussian KDE and an
    optional raincloud layout; box plots computed from raw observations.
  - `:sunburst`, and treemaps nested to any depth with group headers.
  - `:funnel`, `:pyramid`, `:waterfall` (subtotals, totals, connectors) and
    `:dumbbell`; v4.7.0's `is_funnel`, `is_dumbbell` and
    `legend.custom_legend_items` ported.
  - Series `group:` for side-by-side stacks, and `chart.stack_type: "100%"`
    for bars (per group), area and line. Stacked area and line
    (`chart.stacked: true`) now stack; they used to overlap.
  - `:streamgraph` with wiggle (Byron & Wattenberg) and silhouette baselines.
  - `:gauge` with bands, ticks, needle and centre labels; radial-bar
    `targets`; `plot_options.pie.border_radius` and `spacing`.
  - `:unit` (grid, parliament, beeswarm layouts) and `:waffle`.
  - Trellis small multiples via `options.trellis`, with shared scales,
    one legend and labels only on edge panels.
  - Heatmaps on numeric and datetime x-axes, and a gradient colour-bar legend
    (`legend.gradient`).
  - Annotation dash patterns and `stroke_linecap`; balanced
    `data_labels.hide_overlapping`; per-point `data_labels.offset_x/y`
    functions; tooltips on point annotations; log axes below 1.
- SVG invariant lint (`test/svg_invariants_test.exs`) over every catalog
  example in light, dark and live output, a contact sheet for human review
  (`mix run dev/contact_sheet.exs`), and `docs/VALIDATION.md`.
- Chart styles. `EexCharts.Style` is a behaviour whose `defaults/1` returns
  option overrides per chart type, layered between ApexCharts' type defaults and
  the user's options; pick one with `style:` per chart or
  `config :eexcharts, style: ...`. The built-in `:chartjs` style gives the
  Chart.js v4 look (`Colors` palette, translucent fills, small ringed points,
  grid on both axes, 40x12 legend boxes on top). Styles compose with
  `theme.mode`.
- `legend.markers.width`, `height` and `fill_opacity`; a stroked legend marker
  without `stroke_color` is outlined in its series color.
- `markers.stroke_colors: nil` rings each marker in its series color, and line
  charts now index per-series `markers.colors`/`stroke_colors` lists.
- The `:chartjs` palette (`theme: %{palette: :chartjs}`).

- Styled segments inside one axis label. A label line from
  `xaxis.labels.formatter` or `yaxis.formatter` may now be a list of segments,
  where a segment is a string or a map with `:text` and any of `:fill`,
  `:font_weight`, `:font_size`, `:font_style` and `:font_family`; maps render as
  nested `tspan`s. The typical use is a short key in an accent colour in front
  of a long category name. Radar, cartesian x-axis and y-axis labels share one
  implementation (`EexCharts.LabelText`), so all three measure segments the same
  way when reserving space, and y-axis formatters may return several lines too.

### Fixed

- Dark theme: annotation labels and data labels on light series colours were
  near-invisible (the fore colour on a white or light box, contrast about
  1.1:1, as in ApexCharts v4). Text now switches to dark grey only when it
  would otherwise be practically invisible (below 1.5:1); every legible
  default keeps its ApexCharts colour.
- The last category label of a line or area chart no longer clips at the
  right edge when it is wider than the right gutter.
- Horizontal bars drew their category labels by `xaxis.labels.show` and value
  labels by `yaxis.labels.show`, the reverse of how the layout sized them.
- Horizontal crowded bar categories are thinned to every k-th label instead
  of overlapping.
- Extreme numeric data no longer raises. Every chart type raised
  `ArithmeticError` on values near the float limit (`±1.0e308`), and line
  charts on values too small or too close together for a scale. Series and
  categories are now clamped to `±1.0e100` and magnitudes below `1.0e-100`
  become `0.0` (`EexCharts.Numbers`); the scale clamps a forced `min`/`max` the
  same way and treats a range below float precision as degenerate. Values from
  `1e21` up are labelled in exponent form (`1.0e21`), as JavaScript does.
- A logarithmic y-axis over values `<= 0` renders instead of raising.
- Datetime values outside years -9000..9000 are clamped instead of raising in
  `DateTime.from_unix!/2`.
- Heatmaps accept ApexCharts' `%{x:, y:}` points; without
  `xaxis.categories`, the first series' `x` values name the columns. A cell
  without a numeric value is left empty instead of raising.
- Styled label segments line up with the text around them in resvg-based
  renderers (Typst, Inkscape exports). `dominant-baseline` is not inherited in
  SVG 1.1, and resvg/usvg follow 1.1: a `tspan` that does not set it falls back
  to the alphabetic baseline, so an orange key in front of a radar label sat
  above the title like a superscript. Every `tspan` a label draws now repeats
  its `<text>` element's `dominant-baseline`. Browsers inherit it anyway, so
  their rendering is unchanged; the SVG goldens gain the attribute.
- `yaxis.title.offset_x` / `offset_y` move the rotated y-axis title on screen.
  The title was rotated about its un-offset anchor, so `offset_x: 8` slid it 8px
  along its own (vertical) text instead of 8px to the right, and there was no
  way to pull a title clear of the left edge, where a font size above about 10
  clips its ascenders.
- A top legend under a title no longer overlaps the plot. It was pushed down by
  the title's height twice; it now follows ApexCharts' `2 * titleH + margin -
  20` and never crosses the grid. Legend text also clears a stroked marker's
  outline.
- `theme.palette` applies in light mode. It was only honoured under `:dark` and
  `:daisy`, while ApexCharts reads it in every mode.
- Bars and range bars with a `stroke.width` but no `stroke.colors` are outlined
  in their series color, as in ApexCharts, instead of drawing no outline.
- Point annotation labels stay inside the plot. The label was always centered
  above the marker, so a point at the top of the scale pushed it out of the
  chart and one at the left or right edge cut it in half. The default spot is
  kept when it fits; otherwise the label flips below the marker and slides in
  from the side edge.
- `EexCharts.Live` treats the size its hook reports as untrusted: each side is
  rounded and clamped to 1-10,000 px, and a `"measured"` event without two
  numbers is ignored. A client could send `1.0e308`, which raised in the
  layout, or a payload without `width`, which crashed the component.
- Marker shape names given as strings are looked up instead of converted with
  `String.to_atom/1`. Unknown names draw a circle, as unknown atoms already
  did, and no longer add a permanent atom each, so shapes taken from user data
  cannot exhaust the atom table.
- Radar charts size their label reserve from the formatted labels. A formatter
  that wraps long categories onto several lines used to free no space, because
  the reserve was still measured on the raw, unwrapped category; now it uses the
  longest line drawn, and wrapped labels on the top and bottom spokes get
  vertical room too. An arity-1 `xaxis.labels.formatter` may now return a list
  of lines, as the arity-2 form already could (the list used to be joined into
  one string).
- x-axis and point annotations render on value x-axes (scatter, bubble and
  numeric or datetime line charts). `x` and `x2` were always resolved as a
  category index, so `x: 47` on a 0-100 scatter was read as slot 47 and dropped
  as out of range; only y-axis annotations showed. On a value axis they are now
  data values, as in ApexCharts, and a datetime axis also takes `DateTime`,
  `NaiveDateTime`, `Date` and ISO 8601 strings.
- Vertical x-axis annotation labels no longer get cropped at the top of the
  chart. The label was centered one font size below the plot edge and then
  rotated, so any label longer than about two characters stuck out above the
  plot by half its length and lost the top of its frame. It now hangs from the
  plot edge (or sits on the bottom edge with `position: :bottom`), as in
  ApexCharts.
- Multi-line radar labels sit on their spoke the way a single line does. The
  first line used to land on the anchor with the rest hanging below, so side
  labels looked shifted down and the top label ran into the outer ring. Side
  labels are now centred on the spoke, the top label grows upward and the
  bottom label still grows downward.
- The library now compiles without warnings under Elixir 1.20's type checker.
  Two branches it flagged were already unreachable: the heatmap legend re-tested
  `ranges != []` in a clause the one above it had already narrowed to a non-empty
  list, and the catch-all `in_range?/2` in `EexCharts.Annotations` sat behind
  callers that all guard on `is_number/1` first. Both are gone; rendered output
  is unchanged, as the SVG goldens confirm. CI runs the suite on 1.20 as well,
  and the format and warning gates moved to it.

### Security

- CSS values can no longer add CSS of their own. A color or font family was
  HTML-escaped but otherwise written into `style` attributes as is, so a
  series color of `red;background:url(https://example.com/x)` made the
  browser fetch that URL. Every `style` is now built from declarations
  (`EexCharts.SVG.style/1`), and each declaration value, like every
  CSS-valued presentation attribute (`fill`, `stroke`, `font-family`, …),
  must pass `EexCharts.CSS.safe_value?/1` or is dropped. Ordinary colors,
  `var()`, `color-mix()` and font stacks are unaffected. Each `style`
  attribute now ends in `;`.
- A malformed hex color such as `#ggg` no longer raises in gradient and
  heatmap shading; it is shaded with `color-mix()` like any non-hex color.

### Performance

- Render time grows linearly with the number of points. Several loops read
  the data, categories, labels or palette by position with `Enum.at/2` inside
  a loop over positions, which made them quadratic: a 32,000-point smooth
  line took about 36 s and a stacked bar of the same size about 39 s. They
  now read from tuples (`EexCharts.Indexed`), and the squarified treemap keeps
  its row's running min, max and sum instead of rescanning the row, so a zero
  value no longer makes it quadratic. Those charts now render in 1-3 s.
  Output is unchanged: the SVG goldens are byte-identical.
- `EexCharts.SVG.esc/1` returns text with nothing to escape as is, instead of
  running five replace passes over it.

## v0.1.1 — 2026-09-03

### Fixed

- SVG golden snapshots now compare numerically rather than byte-for-byte, so
  `mix test` passes on a clean checkout regardless of platform. Coordinates are
  serialised at full precision on purpose, and the last bit of a `:math.cos/1`
  result differs between macOS and the Linux runner that seeds the goldens —
  which made the radar snapshot fail for anyone not on Linux. Markup still has
  to match exactly. See `EexCharts.SnapshotDiff`.
- Reformatted the handful of files that had drifted from `mix format`, and added
  `mix format --check-formatted` plus `mix compile --warnings-as-errors` to CI
  so they cannot drift again. `dev/` is now covered by the formatter;
  `lib/eex_charts/font_metrics.ex` is deliberately excluded, so its
  advance-width tables stay readable as tables.
- Corrected the `EexCharts.Charts.RadialBar` moduledoc, which pointed at a
  private function in `EexCharts.Renderer` and so shipped a broken link in the
  generated docs.
- `to_svg/4` no longer crashes on a `:datetime` axis whose categories are
  `Date` or `DateTime` values. The static-mode walk that resolves `var()`
  fallbacks treated structs as nested option maps and tried to rebuild them.

### Changed

- ApexCharts' MIT notice moved out of `LICENSE` into `NOTICE.md`, so GitHub and
  Hex detect the project's own license as MIT instead of "Other". The
  attribution is unchanged, and `NOTICE.md` ships in the Hex package.
- `CHANGELOG.md`, `CONTRIBUTING.md`, `NOTICE.md`, and `docs/KNOWN_ISSUES.md`
  are published as HexDocs pages. README links that pointed at files missing
  from the package (the preview image, `LICENSE`, the edge-case test) now
  resolve on HexDocs.
- CI now checks the `elixir: "~> 1.15"` requirement instead of only asserting
  it: the library is compiled against the floor (1.15.8/OTP 26.2.5) in a job of
  its own, and the suite runs on both 1.18.4 and 1.19.5. The floor cannot run
  the suite itself — `phoenix_test_playwright` pulls in `playwright_ex`, which
  needs Elixir 1.18+ — but that is a harness constraint, not one a consumer of
  the library inherits.
- Internally, charts are now built as an element tree that is serialised to
  markup at the boundary, and `transform` attributes are structured like path
  data. The output is byte-for-byte unchanged.

## v0.1.0 — 2026-08-21

Initial release: a port of [ApexCharts.js](https://apexcharts.com) v4.7.0's
rendering to Elixir, for Phoenix LiveView.

### Added

- Chart types: line, area, bar/column (grouped, stacked, horizontal,
  distributed), pie, donut, scatter, bubble, candlestick, box plot, range bar,
  heatmap, treemap, radar, radial bar, polar area.
- Curves (`:smooth`, `:straight`, `:stepline`, `:monotone_cubic`) with
  `nil`-value gaps; category, numeric, and datetime x-axes; logarithmic and
  multiple y-axes; axis/point annotations.
- Theming: light, dark, custom palettes, and daisyUI (`theme: %{mode: :daisy}`)
  — charts follow the active daisyUI theme, live theme switches included, with
  no JS.
- LiveView-native interactivity: `on_click`, `on_legend_click` with
  `hidden_series`, and optional `push_hover`, all as ordinary LiveView events.
  Hover tooltips are pre-rendered server-side and toggled by a ~100-line hook.
- `to_svg/4` for standalone SVG output aimed at rasterisers and PDF pipelines.
- Real font metrics and container-measured sizing for ApexCharts-faithful
  label placement; an opt-in HTML legend.
- Two visual regression layers: byte-comparable SVG goldens in `mix test`, and
  headless-Chromium screenshots via `phoenix_test_playwright`.
