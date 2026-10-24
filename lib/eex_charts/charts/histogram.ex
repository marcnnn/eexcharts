defmodule EexCharts.Charts.Histogram do
  @moduledoc """
  Histogram chart (`type: :histogram`): bins raw observations and draws one
  bar per bin on a numeric x-axis.

  Each series' `data` is a list of raw numbers (non-numbers are skipped):

      series: [%{name: "Latency", data: [12.1, 15.3, 9.8, ...]}]

  ## Options (`plot_options: %{histogram: %{...}}`)

    * `bins` — `:auto` (default; Freedman-Diaconis, Sturges when the IQR is
      0), `:fd`, `:sturges`, `:scott`, `:sqrt`, or an integer bin count
    * `bin_width` — a fixed bin width, edges aligned to its multiples; wins
      over `bins`
    * `normalize` — `:count` (default), `:probability`, `:percent`,
      `:density` (bar areas sum to 1)
    * `cumulative` — `false` (default) or `true` for running totals
    * `overlay_opacity` — fill opacity used when more than one series is
      visible (default `0.5`, never more than `fill.opacity`), so overlaid
      histograms show through each other

  The binning rules are documented in `EexCharts.Stats`. All series share one
  set of bin edges, computed from every series' values pooled together, so
  overlaid histograms line up bin for bin and hiding a series via the legend
  does not move the bins. Bars touch (no gap); set
  `stroke: %{width: 1, colors: ["#fff"]}` to outline them.

  The x-axis spans the bin edges rounded out to nice tick values unless
  `xaxis.min` / `xaxis.max` are set, and the y-axis starts at zero. Hovering a bar shows a tooltip titled with
  the bin range (`10 - 20`) listing every series' value for that bin.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, Scale, Stats}

  @doc """
  Bins every series and returns `{cfg, series}`: each series' `data` becomes a
  list of `%{x: mid, y: value, x0: lo, x1: hi, count: c}` points, one per bin,
  and the x-axis range is set to the outer edges.
  """
  def prepare(cfg, series) do
    opts = cfg.plot_options.histogram
    pooled = Enum.flat_map(series, &numbers(&1.data))
    edges = Stats.bin_edges(pooled, bins: opts.bins, bin_width: opts.bin_width)

    series =
      Enum.map(series, fn s ->
        counts = Stats.histogram(numbers(s.data), edges)
        values = Stats.normalize(counts, edges, opts.normalize, opts.cumulative == true)
        counts = if opts.cumulative == true, do: Enum.scan(counts, &(&1 + &2)), else: counts

        bins =
          edges
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.zip(counts)
          |> Enum.zip_with(values, fn {[lo, hi], c}, v ->
            %{x: (lo + hi) / 2, y: v, x0: lo, x1: hi, count: c}
          end)

        %{s | data: bins}
      end)

    {x_axis(cfg, edges), series}
  end

  # A numeric x-axis divides `min..max` linearly, which on raw bin edges gives
  # ticks like 72.6, 96.85. Round the span out to a nice scale instead (the
  # same rounding the y-axis uses) unless the caller fixed the axis.
  defp x_axis(cfg, []), do: cfg

  defp x_axis(%{xaxis: x} = cfg, edges) do
    width = if is_number(cfg.chart.width), do: cfg.chart.width, else: 600
    scale = Scale.nice_scale(hd(edges), List.last(edges), svg_height: width / 2)

    step =
      if is_nil(x.tick_amount) and is_nil(x.step_size) and is_nil(x.min) and is_nil(x.max),
        do: scale.step,
        else: x.step_size

    %{
      cfg
      | xaxis: %{x | min: x.min || scale.nice_min, max: x.max || scale.nice_max, step_size: step}
    }
  end

  defp numbers(data) when is_list(data), do: Enum.filter(data, &is_number/1)
  defp numbers(_), do: []

  @doc "Renders the prepared histogram series into the cartesian grid."
  def render(cfg, series, %Layout{} = l, opts \\ []) do
    on_click = opts[:on_click]

    opacity =
      if length(series) > 1,
        do: min(cfg.fill.opacity, cfg.plot_options.histogram.overlay_opacity),
        else: cfg.fill.opacity

    y0 = Layout.zero_y(l)

    Enum.map(series, fn s ->
      color = Config.color_at(cfg, s.index)

      bars =
        s.data
        |> Enum.with_index()
        |> Enum.flat_map(fn {b, j} ->
          xa = Layout.x_value_pos(l, b.x0)
          xb = Layout.x_value_pos(l, b.x1)
          y = Layout.y_for(l, clamp(l, b.y))

          if b.y > 0 do
            attrs = %{
              class: "eexcharts-bar eexcharts-histogram-bar",
              data_j: j,
              data_cx: (xa + xb) / 2,
              x: xa,
              y: min(y, y0),
              width: max(xb - xa, 0),
              height: abs(y0 - y),
              fill: color,
              fill_opacity: opacity,
              stroke: Config.color_for(cfg.stroke.colors, s.index),
              stroke_width: if(cfg.stroke.width > 0, do: cfg.stroke.width)
            }

            [el("rect", click(attrs, on_click, j, s.index))]
          else
            []
          end
        end)

      el("g", %{class: "eexcharts-series"}, bars)
    end)
  end

  @doc "Returns `{0, max}` over the prepared bins."
  def data_range(series) do
    case for(s <- series, b <- s.data, is_number(b.y), do: b.y) do
      [] -> {nil, nil}
      ys -> {0, Enum.max(ys)}
    end
  end

  @doc "Tooltip titles: one `lo - hi` label per bin."
  def bin_labels(series) do
    case Enum.find(series, &(&1.data != [])) do
      nil -> []
      s -> Enum.map(s.data, fn b -> "#{fmt_value(b.x0)} - #{fmt_value(b.x1)}" end)
    end
  end

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)

  defp click(attrs, nil, _j, _series), do: attrs

  defp click(attrs, on_click, j, series) do
    Map.merge(attrs, %{
      "phx-click" => on_click,
      "phx-value-index" => j,
      "phx-value-series" => series,
      cursor: "pointer"
    })
  end
end
