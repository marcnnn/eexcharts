# EexCharts

**Server-side rendered SVG charts for Phoenix LiveView, modeled on
[ApexCharts.js](https://apexcharts.com).**

EexCharts re-implements the rendering logic and default styling of
ApexCharts.js v4.7.0 (the last MIT-licensed release) in pure Elixir. The
entire chart — axes, nice-scale ticks, series geometry, legend, data labels,
and even every tooltip's HTML — is rendered on the server. A single ~100-line
JS hook handles hover: it only toggles pre-rendered tooltips, positions them
next to the cursor, and moves the crosshair. Clicks are plain `phx-click`
bindings, so selections arrive as ordinary LiveView events.

![preview](https://raw.githubusercontent.com/marcnnn/eexcharts/main/dev/preview.png)

## Features

- **Chart types:** line, area, bar/column (grouped, stacked, horizontal,
  distributed), pie, donut, scatter, bubble, candlestick, box plot, range
  bar, heatmap, treemap (squarified), radar, radial bar, polar area
- **Curves:** `:smooth` (ApexCharts' 35% bezier), `:straight`, `:stepline`,
  `:monotone_cubic` (Fritsch–Carlson), with `nil`-value gaps
- **Axes:** category, numeric, and datetime x-axes (ported TimeScale tick
  logic), logarithmic y-axes, multiple y-axes with `opposite: true`
- **Annotations:** y/x axis lines and bands, labeled point markers
- **Theming:** light and dark (`theme: %{mode: :dark}`), custom palettes, and
  [daisyUI](https://daisyui.com) (`theme: %{mode: :daisy}`) — charts follow the
  active daisyUI theme, including live theme switches, with no JS
- **ApexCharts fidelity:** same default palette, per-type defaults, nice-scale
  axis algorithm, `column_width`/`bar_height` percentages, border radius
  (`:end` / `:around`), gradient area fills, donut center/total labels,
  percentage slice labels
- **Server-side everything:** charts render without any JS at all; the hook
  is only needed for hover tooltips
- **Static SVG export:** `to_svg/4` emits a bare `<svg>` for PDF pipelines
  (Typst, resvg, ChromicPDF) and image conversion — no hover furniture, no
  `phx-*` wiring, CSS variables resolved to literals
- **Native PDF output:** `EexCharts.PDF` draws a chart with PDF operators —
  real vectors, real text, no rasterizer to shell out to — either as a
  one-page document or as operations to drop into a report you are already
  building with [PrawnEx](https://hex.pm/packages/prawn_ex)
- **LiveView-native interactivity:** `on_click` → `phx-click` with
  `phx-value-index` / `phx-value-series`; `on_legend_click` + `hidden_series`
  for legend toggling; optional `push_hover` pushes hover events to the server
- **No dependencies** beyond `phoenix_live_view`

## Installation

```elixir
def deps do
  [
    {:eexcharts, "~> 0.1.0"}
  ]
end
```

Register the hover hook in `assets/js/app.js`:

```js
import EexCharts from "../../deps/eexcharts/priv/static/eexcharts";

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { EexCharts /*, ...your hooks */ },
});
```

And include the stylesheet in `assets/css/app.css`:

```css
@import "../../deps/eexcharts/priv/static/eexcharts.css";
```

## Usage

```heex
<EexCharts.chart
  id="revenue"
  type={:area}
  series={[
    %{name: "Revenue", data: [31, 40, 28, 51, 42, 109, 100]},
    %{name: "Cost", data: [11, 32, 45, 32, 34, 52, 41]}
  ]}
  categories={~w(Mon Tue Wed Thu Fri Sat Sun)}
/>
```

Pie / donut charts take a plain list of values plus `labels`:

```heex
<EexCharts.chart
  id="share"
  type={:donut}
  series={[44, 55, 41, 17]}
  labels={~w(Apples Oranges Bananas Cherries)}
  options={%{plot_options: %{pie: %{donut: %{labels: %{show: true, total: %{show: true}}}}}}}
/>
```

Options mirror ApexCharts' configuration as nested maps with snake_case atom
keys — `%{stroke: %{curve: :smooth}}` instead of `{stroke: {curve: 'smooth'}}`.
See `EexCharts.Config.defaults/0` for the supported options and their
defaults.

```heex
<EexCharts.chart
  id="quarterly"
  type={:bar}
  series={[
    %{name: "Cash", data: [44, 55, 41, 67]},
    %{name: "Credit", data: [13, 23, 20, 8]}
  ]}
  categories={~w(Q1 Q2 Q3 Q4)}
  options={%{
    chart: %{stacked: true},
    plot_options: %{bar: %{border_radius: 5, border_radius_application: :end}},
    colors: ["#008FFB", "#00E396"]
  }}
/>
```

### daisyUI theming

A Phoenix app generated with daisyUI (the default since Phoenix 1.8) can hand
its theme to every chart with one line:

```elixir
# config/config.exs
config :eexcharts, theme_mode: :daisy
```

Or per chart: `options={%{theme: %{mode: :daisy}}}`.

Series then use daisyUI's semantic colors (`primary`, `secondary`, `accent`,
`info`, `success`, `warning`, `error`, `neutral`), axis text follows
`base-content`, grid lines follow `base-300`, slice separators follow
`base-100`, and labels drawn on a mark use that color's paired `-content`
color — so contrast stays correct in every theme, which is more than
ApexCharts' hardcoded white manages.

Nothing is resolved on the server: charts emit `var(--color-primary)` and let
the browser resolve it. Switching `data-theme` restyles an already-rendered
chart instantly, with no re-render and no round-trip — dark mode included.
Every value carries its light-theme literal as a `var()` fallback, so charts
still look right on a page without daisyUI.

Set `theme: %{mode: :daisy, palette: :palette6}` to keep daisyUI chrome while
pinning the series to an ApexCharts palette.

### Interactions from LiveView

```heex
<EexCharts.chart id="sales" type={:bar} series={@series} on_click="bar-selected" />
```

```elixir
def handle_event("bar-selected", %{"index" => i, "series" => s}, socket) do
  {:noreply, assign(socket, selected: {String.to_integer(s), String.to_integer(i)})}
end
```

`push_hover="chart-hover"` makes the hook push
`%{"id" => id, "index" => index}` to the server on hover, if you want
server-side reactions (e.g. syncing a table row highlight).

### Legend toggling

Legend items are clickable too — ApexCharts' series toggle, done the
LiveView way (the hidden set lives in your assigns):

```heex
<EexCharts.chart
  id="sales"
  type={:line}
  series={@series}
  on_legend_click="toggle-series"
  hidden_series={@hidden}
/>
```

```elixir
def handle_event("toggle-series", %{"series" => s}, socket) do
  i = String.to_integer(s)

  hidden =
    if i in socket.assigns.hidden,
      do: List.delete(socket.assigns.hidden, i),
      else: [i | socket.assigns.hidden]

  {:noreply, assign(socket, hidden: hidden)}
end
```

Hidden series disappear from the chart and tooltips, the axes rescale to
the remaining data, the other series keep their colors, and the legend item
stays visible but dimmed — same behavior as ApexCharts' legend toggle.

Because the chart is a pure function of its assigns, updating `@series`
re-renders the SVG through the normal LiveView diff — that's all there is to
"animations".

### Outside LiveView

```elixir
EexCharts.render("cpu", :line, [%{name: "CPU", data: [10, 20, 15]}],
  categories: ~w(a b c),
  hook: false
)
```

returns safe HTML for controllers, static pages, or emails — no JS involved.

### Static SVG export (PDFs, images)

```elixir
EexCharts.to_svg("cpu", :line, [%{name: "CPU", data: [10, 20, 15]}],
  categories: ~w(a b c)
)
```

returns a standalone `<svg>` string for SVG rasterizers — Typst's `image()`,
resvg, librsvg — and PDF pipelines. Compared to `render/4`:

- no wrapping `<div>`, tooltip HTML, or hover furniture (crosshair, hover
  markers, hover zones, `data-*` indexes) — a rasterizer would draw all of it
- no `phx-*` bindings (the interactive options aren't accepted)
- every `var(--x, fallback)` is resolved to its fallback literal and shading
  uses hex instead of `color-mix()`, because rasterizers have no CSS custom
  properties and would render `var(…)` as **black** — under
  `theme: %{mode: :daisy}` the export matches the ApexCharts light theme

Two print-specific caveats:

- `theme: %{mode: :dark}` changes text colors but **not** the background; also
  set `chart: %{background: "#343434"}` (or export in `:light`), otherwise
  light text lands on white paper.
- `chart.font_family` defaults to Helvetica/Arial. A rendering host without
  those fonts substitutes its own (layout is measured server-side, so labels
  stay correctly positioned); set a font the host has if typography matters.

### Native PDF output

```elixir
File.write!("cpu.pdf",
  EexCharts.PDF.to_pdf("cpu", :line, [%{name: "CPU", data: [10, 20, 15]}],
    categories: ~w(a b c),
    x: 40,
    y: 450,
    scale: 0.85
  ))
```

draws the chart with PDF operators instead of handing an SVG to a rasterizer:
vector paths, base-14 Helvetica text, and no external binary. `:x`/`:y` place
the chart's bottom-left corner on the page (PDF measures in points from the
bottom-left) and `:scale` sizes it.

To place a chart inside a document you are already building, use
`EexCharts.PDF.ops/4`, which returns the drawing operations as plain tuples —
it needs no dependency at all:

```elixir
Enum.reduce(EexCharts.PDF.ops("cpu", :line, series, x: 40, y: 480),
  doc, &PrawnEx.Document.append_op(&2, &1))
```

`to_pdf/4` needs the optional [`prawn_ex`](https://hex.pm/packages/prawn_ex)
dependency. Two things do not carry over: a gradient fill degrades to its first
stop, and fill and stroke share one opacity (PDF's alpha lives in the graphics
state, not on the paint). See `EexCharts.PDF.Ops` for the full list.

## Development

```sh
mix test                  # unit tests + SVG golden snapshots (fast, no browser)
mix run dev/preview.exs    # writes dev/preview.html, a static visual gallery
mix dev                    # storybook catalog at http://localhost:4444/storybook
```

All chart examples live in one place — `all/0` in `dev/chart_examples.ex` —
shared by the preview gallery, the storybook stories, and both snapshot test
layers, so there's no drift.

### Storybook catalog

`mix dev` boots a dev-only standalone Phoenix server (nothing under `dev/` ships
in the Hex package) hosting a [phoenix_storybook](https://hex.pm/packages/phoenix_storybook)
catalog. The catalog registers the real `EexCharts` hook, so hover tooltips and
legend toggles work there too.

The sidebar is the index of chart types — one story per chart family, each
listing that family's examples by name:

| Sidebar entry      | Story file                             | Chart types            |
| ------------------ | -------------------------------------- | ---------------------- |
| Line               | `dev/storybook/line.story.exs`          | `:line`                |
| Area               | `dev/storybook/area.story.exs`          | `:area`                |
| Bar & column       | `dev/storybook/bar.story.exs`           | `:bar`                 |
| Range bar          | `dev/storybook/range_bar.story.exs`     | `:range_bar`           |
| Scatter & bubble   | `dev/storybook/scatter.story.exs`       | `:scatter`, `:bubble`  |
| Pie & donut        | `dev/storybook/pie.story.exs`           | `:pie`, `:donut`       |
| Polar area         | `dev/storybook/polar_area.story.exs`    | `:polar_area`          |
| Radial bar         | `dev/storybook/radial_bar.story.exs`    | `:radial_bar`          |
| Radar              | `dev/storybook/radar.story.exs`         | `:radar`               |
| Heatmap            | `dev/storybook/heatmap.story.exs`       | `:heatmap`             |
| Treemap            | `dev/storybook/treemap.story.exs`       | `:treemap`             |
| Candlestick        | `dev/storybook/candlestick.story.exs`   | `:candlestick`         |
| Box plot           | `dev/storybook/box_plot.story.exs`      | `:box_plot`            |

Which story an example lands in comes from its `:group` key in
`Dev.ChartExamples.all/0`; the variation's label is its `:title`. Each story
file is a three-liner over the shared `Dev.ChartStory` macro
(`dev/chart_story.ex`), so adding an example is a one-line change in
`dev/chart_examples.ex` — no story edit needed unless you are introducing a new
chart family. Sidebar labels and ordering live in
`dev/storybook/_root.index.exs`.

`:group` also drives the storybook URLs (`/storybook/<group>`, iframe
`/storybook/iframe/<group>?variation_id=<id>`), which is how
`test/visual_test.exs` finds each chart. `:id` values (`c1`…`n13`) are
independent of grouping and stay frozen — they name the committed SVG goldens
in `test/snapshots/`.

### Visual regression testing

Two layers guard against visual regressions:

**1. SVG golden snapshots** (`test/svg_snapshot_test.exs`) — fast and
browserless, part of the normal `mix test`. Each example is rendered to SVG and
compared against a committed golden in `test/snapshots/`. Markup has to match
exactly; numbers have to match numerically, because coordinates are serialised
at full precision and the last bit of a trig result is not the same on macOS as
on the Linux runner that seeds the goldens (see `EexCharts.SnapshotDiff`). When
a change to the output is intentional, regenerate the goldens:

```sh
EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test test/svg_snapshot_test.exs
```

**2. Pixel screenshots** (`test/visual_test.exs`, tagged `:visual`, excluded by
default) — real headless-Chromium screenshots via
[phoenix_test_playwright](https://hex.pm/packages/phoenix_test_playwright),
catching font/CSS regressions the SVG diff can't see. They need the Playwright
driver + a browser:

```sh
npm --prefix assets install playwright
npx --prefix assets playwright install chromium
mix test --only visual        # asserts against test/visual/baseline/
```

`assert_screenshot/3` saves a baseline on first run and compares thereafter
(diffs land in `test/visual/baseline/__diff__/`). Because pixel output depends
on font rendering, **baselines must be generated in the same environment they're
checked against** — the CI `visual` job runs inside the official
`mcr.microsoft.com/playwright` image (see `.github/workflows/ci.yml`), which is
where the committed baselines are seeded (`mix test --only visual` with the
baseline deleted).

## License

MIT — see
[LICENSE](https://github.com/marcnnn/eexcharts/blob/main/LICENSE).

EexCharts is a re-implementation of rendering logic and default styling from
[ApexCharts.js](https://github.com/apexcharts/apexcharts.js) v4.7.0, © 2018
ApexCharts, used under the terms of its MIT license — reproduced in
[NOTICE.md](NOTICE.md).
