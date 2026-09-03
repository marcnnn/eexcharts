defmodule EexCharts do
  @moduledoc """
  Server-side rendered SVG charts for Phoenix LiveView, modeled on
  [ApexCharts.js](https://apexcharts.com) v4.7.0 (MIT).

  The entire chart — geometry, axes, series, legend, and even the tooltip
  contents — is rendered in Elixir. A ~100-line JS hook only shows/hides the
  pre-rendered tooltips and positions them next to the cursor. Click
  interactions use plain `phx-click` bindings, so selections arrive as
  regular LiveView events with no custom JS.

  ## Usage

      <EexCharts.chart
        id="revenue"
        type={:area}
        series={[
          %{name: "Revenue", data: [31, 40, 28, 51, 42, 109, 100]},
          %{name: "Cost", data: [11, 32, 45, 32, 34, 52, 41]}
        ]}
        categories={~w(Mon Tue Wed Thu Fri Sat Sun)}
        options={%{stroke: %{curve: :smooth}}}
      />

  Options mirror ApexCharts' configuration, as nested maps with snake_case
  atom keys (e.g. `%{plot_options: %{bar: %{border_radius: 4}}}`). See
  `EexCharts.Config.defaults/0` for the supported set and default values.

  ## JS hook (hover tooltips)

  In `assets/js/app.js`:

      import EexCharts from "../../deps/eexcharts/priv/static/eexcharts"

      let liveSocket = new LiveSocket("/live", Socket, {
        hooks: { EexCharts, ...otherHooks },
      })

  And import the stylesheet (or copy it into your CSS):

      @import "../../deps/eexcharts/priv/static/eexcharts.css";

  Charts render fully without the hook — only hover tooltips need it.

  ## daisyUI theming

  Apps set up with [daisyUI](https://daisyui.com) (the Phoenix 1.8 default) can
  opt every chart into the active daisyUI theme:

      config :eexcharts, theme_mode: :daisy

  or per chart, `options={%{theme: %{mode: :daisy}}}`. Colors are emitted as
  `var(--color-primary)` and friends, so the browser resolves them against
  whichever theme is active — switching `data-theme` restyles a rendered chart
  with no re-render. Each value keeps its light-theme literal as a `var()`
  fallback, so charts degrade cleanly on pages without daisyUI. See
  `EexCharts.Theme.apply/2` for the full mapping.

  ## Static output (PDFs, images)

  `to_svg/4` renders a chart as a standalone `<svg>` string with all
  interactive furniture omitted, ready for SVG rasterizers (resvg, Typst's
  `image()`, librsvg) and PDF pipelines. See its docs for the print-specific
  caveats (dark-mode background, fonts).

  ## LiveView interactions

    * `on_click="point-selected"` — bars, slices and category zones get
      `phx-click` with `phx-value-index`, delivered as a normal LiveView
      event.
    * `push_hover="chart-hover"` — the hook pushes the hovered data point
      index to the server (`%{"id" => ..., "index" => ...}`), if you want to
      react to hover server-side.
  """

  use Phoenix.Component

  alias EexCharts.{Renderer, SVG}

  @doc """
  Renders a chart as a stateless function component.

  Charts are pure functions of their assigns: pass new `series` and the SVG
  re-renders over the LiveView diff.
  """
  attr(:id, :string, required: true, doc: "DOM id (required for hook + tooltips)")

  attr(:type, :atom,
    default: :line,
    values: [
      :line,
      :area,
      :bar,
      :pie,
      :donut,
      :scatter,
      :bubble,
      :radial_bar,
      :polar_area,
      :radar,
      :heatmap,
      :treemap,
      :candlestick,
      :box_plot,
      :range_bar
    ],
    doc: "chart type"
  )

  attr(:series, :list,
    default: [],
    doc: "cartesian: [%{name: \"A\", data: [1, 2, 3]}]; pie/donut: a list of numbers"
  )

  attr(:categories, :list, default: nil, doc: "x-axis category labels")
  attr(:labels, :list, default: nil, doc: "slice labels for pie/donut")
  attr(:width, :integer, default: nil, doc: "SVG coordinate width (default 600)")
  attr(:height, :integer, default: nil, doc: "SVG coordinate height (default 350)")
  attr(:options, :map, default: %{}, doc: "ApexCharts-style options (snake_case atoms)")
  attr(:on_click, :string, default: nil, doc: "phx-click event pushed with phx-value-index")
  attr(:push_hover, :string, default: nil, doc: "event name pushed by the hook on hover")

  attr(:on_legend_click, :string,
    default: nil,
    doc: "phx-click event on legend items, pushed with phx-value-series"
  )

  attr(:hidden_series, :list,
    default: [],
    doc: "series indexes toggled off (legend items render dimmed, chart rescales)"
  )

  attr(:class, :string, default: nil)

  def chart(assigns) do
    ~H"""
    {Phoenix.HTML.raw(
      SVG.to_iodata(
        Renderer.render(%{
          id: @id,
          type: @type,
          series: @series,
          categories: @categories,
          labels: @labels,
          width: @width,
          height: @height,
          options: @options,
          on_click: @on_click,
          push_hover: @push_hover,
          on_legend_click: @on_legend_click,
          hidden_series: @hidden_series,
          class: @class
        })
      )
    )}
    """
  end

  @doc """
  Renders a chart to a safe HTML string outside of LiveView (controllers,
  static pages, emails).

      EexCharts.render("cpu", :line, [%{name: "CPU", data: [10, 20, 15]}],
        categories: ["a", "b", "c"],
        options: %{stroke: %{curve: :straight}}
      )
  """
  def render(id, type, series, opts \\ []) do
    opts = Map.new(opts)

    {:safe,
     SVG.to_iodata(
       Renderer.render(%{
         id: id,
         type: type,
         series: series,
         categories: opts[:categories],
         labels: opts[:labels],
         width: opts[:width],
         height: opts[:height],
         options: opts[:options] || %{},
         on_click: opts[:on_click],
         push_hover: opts[:push_hover],
         on_legend_click: opts[:on_legend_click],
         hidden_series: opts[:hidden_series] || [],
         hook: opts[:hook],
         class: opts[:class]
       })
     )}
  end

  @doc """
  Renders a chart to a standalone `<svg>` string for static output — PDF
  pipelines (Typst, resvg, ChromicPDF), image conversion, downloads.

  Unlike `render/4` there is no wrapping `<div>`, no tooltip HTML, and none
  of the hover furniture that only the JS hook uses (crosshair, hover
  markers, hover zones, `data-j` indexes) — a rasterizer would draw all of
  it. Interactive options (`:on_click`, `:push_hover`, `:on_legend_click`)
  are not accepted, so the output carries no `phx-*` bindings.

  Static rasterizers have no CSS custom properties and render `var(…)` as
  black, ignoring even the fallback — so every `var(--x, fallback)` in the
  effective config is resolved to its fallback literal, and shading uses
  plain hex instead of `color-mix()`. Under `theme: %{mode: :daisy}` the
  output therefore matches the ApexCharts light theme.

  Two things to set explicitly for print output:

    * `theme: %{mode: :dark}` changes text colors but not the background —
      also pass `chart: %{background: "#343434"}` (or render `:light`),
      otherwise light text lands on white paper.
    * `chart.font_family` defaults to `Helvetica, Arial, sans-serif`; a
      rasterizer without those fonts substitutes its own (correctly
      positioned, since layout is measured server-side). Set a font the
      rendering host has installed if exact typography matters.

  ## Example

      EexCharts.to_svg("cpu", :line, [%{name: "CPU", data: [10, 20, 15]}],
        categories: ["a", "b", "c"]
      )
      #=> "<svg id=\\"cpu-svg\\" ...>...</svg>"

  Accepts `:categories`, `:labels`, `:width`, `:height`, `:options`, and
  `:hidden_series`, with the same meaning as `render/4`.
  """
  def to_svg(id, type, series, opts \\ []) do
    opts = Map.new(opts)

    %{
      id: id,
      type: type,
      series: series,
      categories: opts[:categories],
      labels: opts[:labels],
      width: opts[:width],
      height: opts[:height],
      options: opts[:options] || %{},
      hidden_series: opts[:hidden_series] || [],
      static: true
    }
    |> Renderer.render()
    |> SVG.to_iodata()
    |> IO.iodata_to_binary()
  end
end
