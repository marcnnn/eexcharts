# Changelog

Notable changes to EexCharts. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Fixed

- The library now compiles without warnings under Elixir 1.20's type checker.
  Two branches it flagged were already unreachable: the heatmap legend re-tested
  `ranges != []` in a clause the one above it had already narrowed to a non-empty
  list, and the catch-all `in_range?/2` in `EexCharts.Annotations` sat behind
  callers that all guard on `is_number/1` first. Both are gone; rendered output
  is unchanged, as the SVG goldens confirm. CI runs the suite on 1.20 as well,
  and the format and warning gates moved to it.

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
