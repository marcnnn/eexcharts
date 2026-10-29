defmodule EexCharts.Charts.Waterfall do
  @moduledoc """
  Waterfall charts: each value is a change, and its bar floats from the
  running total before it to the running total after it.

  ## Usage

      EexCharts.chart(id: "w", type: :waterfall,
        series: [%{name: "Cash", data: [
          %{x: "Opening", y: 120},
          %{x: "Sales", y: 80},
          %{x: "Costs", y: -55},
          %{x: "Q1", subtotal: true},
          %{x: "Tax", y: -20},
          %{x: "Closing", total: true}
        ]}])

  ## Data

  A data point is one of:

    * a number, or `%{y: number}` (optionally with `x:`) — a change;
    * `%{total: true}` or `%{subtotal: true}` (optionally with `x:`) — a bar
      from zero to the running total so far. Totals do not reset the running
      total; `subtotal` is drawn and behaves exactly like `total` and exists
      for readability;
    * `nil` — no bar; the running total carries over.

  When every point of the first series has an `x:` label and no categories are
  given, the labels become the categories. Several series render side by side
  per category, each with its own running total.

  ## Horizontal

  With `plot_options.bar.horizontal: true` the categories run down the left
  edge, first point at the top (as for horizontal `:bar`), and the bars float
  along a horizontal value axis. Connectors become vertical segments between
  consecutive bars. Bar thickness comes from `plot_options.bar.bar_height`.

  ## Options (`plot_options.waterfall`)

    * `colors` - `%{increase: "#00E396", decrease: "#FF4560", total: "#008FFB"}`.
      Each kind takes a colour, `:outline` (outline only, in that kind's
      default colour) or a map `%{color: "#...", fill: %{type: :none |
      :pattern, ...}}` (`color` optional; `fill` as in `EexCharts.PointStyle`).
      A kind's fill sits between the point's own paint and the series `fill`.
    * `connector` — `%{show: true, color: "#a8a8a8", width: 1, dash_array: 3}`:
      a line from the end of each bar to the start of the next, at the running
      total they share.
    * `total_label` (`"Total"`) — tooltip label of the running-total row.
    * `label_colors` (`nil`) - `%{increase:, decrease:, total:}` data label
      colours on the bars of each kind; a missing kind uses
      `data_labels.style.colors`.

  Under `theme: %{mode: :daisy}` the kinds take `--color-success`,
  `--color-error` and `--color-primary` and the connector `--color-base-300`,
  unless set, and labels on those bars their `*-content` colour; the light
  colours also read on the dark theme.

  Bar width, border radius and fill opacity come from `plot_options.bar` and
  `fill` as for `:bar`. Data labels show the change (or the total for total
  bars) at the bar centre; a `data_labels.formatter` receives that number.
  Tooltips show the change, signed, and the running total after it.
  """

  import EexCharts.SVG

  alias EexCharts.{Charts, Config, Layout, PointStyle, Renderer}

  @kind_colors %{increase: "#00E396", decrease: "#FF4560", total: "#008FFB"}

  @doc "Per-type config defaults."
  def type_defaults do
    %{
      chart: %{stacked: false},
      plot_options: %{
        bar: %{data_labels: %{position: :center}},
        waterfall: %{
          colors: @kind_colors,
          connector: %{show: true, color: "#a8a8a8", width: 1, dash_array: 3},
          total_label: "Total",
          label_colors: nil
        }
      },
      data_labels: %{style: %{colors: ["#fff"]}, background: %{enabled: false}},
      stroke: %{width: 0, line_cap: :square},
      fill: %{opacity: 0.85},
      legend: %{markers: %{shape: :square}},
      tooltip: %{shared: false, intersect: true},
      xaxis: %{tick_placement: :between}
    }
  end

  @doc """
  Turns each series' changes into floating ranges:
  `%{y: [from, to], delta, total, kind}` per point, `kind` being `:increase`,
  `:decrease` or `:total`, and `total` the running total after the point.
  """
  def prepare(params) do
    case params[:series] do
      series when is_list(series) ->
        %{params | series: Enum.map(series, &prepare_series/1)}

      _ ->
        params
    end
  end

  defp prepare_series(%{data: data} = s) when is_list(data) do
    {points, _} = Enum.map_reduce(data, 0, &step/2)
    %{s | data: points}
  end

  defp prepare_series(other), do: other

  defp step(nil, acc), do: {nil, acc}
  defp step(%{prepared: true} = p, _acc), do: {p, p.total}

  defp step(%{} = p, acc) do
    {point, acc} =
      if p[:total] == true or p[:subtotal] == true do
        {point(p[:x], [0, acc], nil, acc, :total), acc}
      else
        step_value(p[:x], p[:y], acc)
      end

    # Per-point paint (`EexCharts.PointStyle`) rides along.
    paint = Map.take(p, [:fill_color, :stroke_color, :fill])
    {point && Map.merge(paint, point), acc}
  end

  defp step(v, acc), do: step_value(nil, v, acc)

  defp step_value(_x, v, acc) when not is_number(v), do: {nil, acc}

  defp step_value(x, v, acc) do
    kind = if v < 0, do: :decrease, else: :increase
    {point(x, [acc, acc + v], v, acc + v, kind), acc + v}
  end

  defp point(x, range, delta, total, kind) do
    %{x: x, y: range, delta: delta, total: total, kind: kind, prepared: true}
  end

  @doc "`{min, max}` over every bar end, always including zero."
  def data_range(series) do
    values =
      for s <- series, %{y: [a, b]} <- s.data, v <- [a, b], is_number(v), do: v

    case values do
      [] -> {nil, nil}
      _ -> values |> Enum.concat([0]) |> Enum.min_max()
    end
  end

  @doc """
  Every bar rectangle: `%{series, index, x, y, w, h, point, color, positive,
  style}`, `style` being the bar's `EexCharts.PointStyle` paint.
  """
  def positions(cfg, series, %Layout{} = l) do
    n_series = max(length(series), 1)
    bar_cfg = cfg.plot_options.bar

    {origin, slot, thickness} =
      if l.horizontal,
        do: {l.grid_y, l.grid_h / l.n, bar_cfg.bar_height},
        else: {l.grid_x, l.grid_w / l.n, bar_cfg.column_width}

    bar_w = slot / n_series * Charts.Bar.pct(thickness) / 100

    series
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, pos_i} ->
      s.data
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {%{y: [from, to]} = p, j} ->
          {color, kind_fill} = kind_paint(cfg, p.kind)
          start = origin + slot * j + (slot - bar_w * n_series) / 2 + bar_w * pos_i

          [
            bar_box(l, from, to, start, bar_w)
            |> Map.merge(%{
              series: s.index,
              index: j,
              point: p,
              color: color,
              positive: p.kind != :decrease,
              last_in_stack: true,
              style: PointStyle.resolve(cfg, with_kind_fill(s, kind_fill), p, color)
            })
          ]

        _ ->
          []
      end)
    end)
  end

  # `start` is the bar's position on the category axis.
  defp bar_box(%Layout{horizontal: true} = l, from, to, start, thickness) do
    x_from = Layout.x_for(l, clamp(l, from))
    x_to = Layout.x_for(l, clamp(l, to))
    %{x: min(x_from, x_to), y: start, w: abs(x_to - x_from), h: thickness}
  end

  defp bar_box(l, from, to, start, thickness) do
    y_from = Layout.y_for(l, clamp(l, from))
    y_to = Layout.y_for(l, clamp(l, to))
    %{x: start, y: min(y_from, y_to), w: thickness, h: abs(y_from - y_to)}
  end

  # A kind's own fill sits under the point's paint and over the series fill.
  defp with_kind_fill(s, nil), do: s

  defp with_kind_fill(s, kind_fill),
    do: Map.put(s, :fill, Config.deep_merge(Map.get(s, :fill) || %{}, kind_fill))

  @doc "Renders bars and connectors; returns iodata."
  def render(cfg, series, %Layout{} = l, opts \\ []) do
    on_click = opts[:on_click]
    {rects, defs} = cfg |> positions(series, l) |> PointStyle.link(opts[:id] || "eexcharts")

    rects
    |> Enum.group_by(& &1.series)
    |> Enum.sort_by(fn {i, _} -> i end)
    |> Enum.map(fn {i, rs} ->
      bars =
        Enum.map(rs, fn r ->
          attrs = %{
            class:
              Enum.join(
                ["eexcharts-bar eexcharts-waterfall-#{r.point.kind}" | List.wrap(r.style.class)],
                " "
              ),
            data_j: r.index,
            d: Charts.Bar.bar_path(cfg, r, l.horizontal),
            fill: r.style.fill,
            fill_opacity: r.style.fill_opacity,
            stroke: r.style.stroke || Config.color_for(cfg.stroke.colors, i),
            stroke_width: r.style.stroke_width
          }

          attrs =
            if on_click,
              do:
                Map.merge(attrs, %{
                  "phx-click" => on_click,
                  "phx-value-index" => r.index,
                  "phx-value-series" => r.series,
                  cursor: "pointer"
                }),
              else: attrs

          el("path", attrs)
        end)

      el("g", %{class: "eexcharts-series"}, [connectors(cfg, rs, l), bars])
    end)
    |> then(&[defs, &1])
  end

  @doc """
  Connector segments `{x1, y1, x2, y2}` between consecutive bars of one
  series, at the running total the first ends on and the second starts from:
  horizontal lines on a vertical chart, vertical ones on a horizontal chart.
  """
  def connector_segments(rects, %Layout{} = l) do
    rects
    |> Enum.sort_by(& &1.index)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      if l.horizontal do
        x = Layout.x_for(l, clamp(l, a.point.total))
        {x, a.y + a.h, x, b.y}
      else
        y = Layout.y_for(l, clamp(l, a.point.total))
        {a.x + a.w, y, b.x, y}
      end
    end)
  end

  defp connectors(cfg, rects, l) do
    c = cfg.plot_options.waterfall.connector

    if c.show do
      Enum.map(connector_segments(rects, l), fn {x1, y1, x2, y2} ->
        el("line", %{
          class: "eexcharts-waterfall-connector",
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          stroke: c.color,
          stroke_width: c.width,
          stroke_dasharray: if(c.dash_array && c.dash_array != 0, do: c.dash_array)
        })
      end)
    else
      []
    end
  end

  @doc "Data labels at the bar centres."
  def data_labels(cfg, series, l) do
    dl = cfg.data_labels

    labels =
      cfg
      |> positions(series, l)
      |> Enum.map(fn r ->
        v = label_value(r.point)

        el(
          "text",
          %{
            x: r.x + r.w / 2 + dl.offset_x,
            y: r.y + r.h / 2 + dl.offset_y,
            text_anchor: "middle",
            dominant_baseline: "central",
            fill:
              PointStyle.label_color(
                cfg,
                r.style,
                label_on_bar(cfg, r)
              ),
            font_size: dl.style.font_size,
            font_weight: dl.style.font_weight,
            class: "eexcharts-datalabel"
          },
          esc(format_label(cfg, v, r.series, r.index))
        )
      end)

    el("g", %{class: "eexcharts-datalabels"}, labels)
  end

  defp label_on_bar(cfg, r) do
    (cfg.plot_options.waterfall.label_colors || %{})[r.point.kind] ||
      Config.color_for(cfg.data_labels.style.colors, r.series) || r.color
  end

  defp label_value(%{kind: :total, total: t}), do: t
  defp label_value(%{delta: d}), do: d

  defp format_label(cfg, v, i, j) do
    case cfg.data_labels.formatter do
      f when is_function(f, 2) -> to_string(f.(v, %{series_index: i, data_point_index: j}))
      f when is_function(f, 1) -> to_string(f.(v))
      _ -> fmt_value(v)
    end
  end

  @doc "Tooltip rows for one point: the signed change and the running total."
  def tooltip_rows(cfg, s, %{kind: :total} = p) do
    Renderer.tooltip_row(color(cfg, :total), s.name, Renderer.format_tooltip_y(cfg, p.total))
  end

  def tooltip_rows(cfg, s, %{delta: d} = p) when is_number(d) do
    delta =
      case cfg.tooltip.y_formatter do
        f when is_function(f, 1) -> to_string(f.(d))
        _ -> if d > 0, do: "+" <> fmt_value(d), else: fmt_value(d)
      end

    [
      Renderer.tooltip_row(color(cfg, p.kind), s.name, delta),
      Renderer.tooltip_row(
        color(cfg, :total),
        cfg.plot_options.waterfall.total_label,
        Renderer.format_tooltip_y(cfg, p.total)
      )
    ]
  end

  def tooltip_rows(_cfg, _s, _p), do: []

  defp color(cfg, kind), do: cfg |> kind_paint(kind) |> elem(0)

  # `{colour, fill map or nil}` for a bar kind; `:outline` and a map without
  # `:color` keep the kind's default colour.
  defp kind_paint(cfg, kind) do
    case Map.fetch!(cfg.plot_options.waterfall.colors, kind) do
      :outline -> {@kind_colors[kind], %{type: :none}}
      %{} = spec -> {spec[:color] || @kind_colors[kind], spec[:fill]}
      color -> {color, nil}
    end
  end

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)
end
