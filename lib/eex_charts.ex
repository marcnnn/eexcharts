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

  ## LiveView interactions

    * `on_click="point-selected"` — bars, slices and category zones get
      `phx-click` with `phx-value-index`, delivered as a normal LiveView
      event.
    * `push_hover="chart-hover"` — the hook pushes the hovered data point
      index to the server (`%{"id" => ..., "index" => ...}`), if you want to
      react to hover server-side.
  """

  use Phoenix.Component

  alias EexCharts.Renderer

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
     })}
  end
end
