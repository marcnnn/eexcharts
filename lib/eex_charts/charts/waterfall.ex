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

  The chart is vertical only; `plot_options.bar.horizontal` is ignored.

  ## Options (`plot_options.waterfall`)

    * `colors` — `%{increase: "#00E396", decrease: "#FF4560", total: "#008FFB"}`
    * `connector` — `%{show: true, color: "#a8a8a8", width: 1, dash_array: 3}`:
      a line from the end of each bar to the start of the next, at the running
      total they share.
    * `total_label` (`"Total"`) — tooltip label of the running-total row.

  Bar width, border radius and fill opacity come from `plot_options.bar` and
  `fill` as for `:bar`. Data labels show the change (or the total for total
  bars) at the bar centre; a `data_labels.formatter` receives that number.
  Tooltips show the change, signed, and the running total after it.
  """

  import EexCharts.SVG

  alias EexCharts.{Charts, Config, Layout, Renderer}

  @doc "Per-type config defaults."
  def type_defaults do
    %{
      chart: %{stacked: false},
      plot_options: %{
        bar: %{data_labels: %{position: :center}},
        waterfall: %{
          colors: %{increase: "#00E396", decrease: "#FF4560", total: "#008FFB"},
          connector: %{show: true, color: "#a8a8a8", width: 1, dash_array: 3},
          total_label: "Total"
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
    if p[:total] == true or p[:subtotal] == true do
      {point(p[:x], [0, acc], nil, acc, :total), acc}
    else
      step_value(p[:x], p[:y], acc)
    end
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

  @doc "Every bar rectangle: `%{series, index, x, y, w, h, point, color, positive}`."
  def positions(cfg, series, %Layout{} = l) do
    n_series = max(length(series), 1)
    slot = l.grid_w / l.n
    bar_w = slot / n_series * Charts.Bar.pct(cfg.plot_options.bar.column_width) / 100

    series
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, pos_i} ->
      s.data
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {%{y: [from, to]} = p, j} ->
          y_from = Layout.y_for(l, clamp(l, from))
          y_to = Layout.y_for(l, clamp(l, to))

          [
            %{
              series: s.index,
              index: j,
              x: l.grid_x + slot * j + (slot - bar_w * n_series) / 2 + bar_w * pos_i,
              y: min(y_from, y_to),
              w: bar_w,
              h: abs(y_from - y_to),
              point: p,
              color: color(cfg, p.kind),
              positive: p.kind != :decrease,
              last_in_stack: true
            }
          ]

        _ ->
          []
      end)
    end)
  end

  @doc "Renders bars and connectors; returns iodata."
  def render(cfg, series, %Layout{} = l, opts \\ []) do
    on_click = opts[:on_click]
    rects = positions(cfg, series, l)

    rects
    |> Enum.group_by(& &1.series)
    |> Enum.sort_by(fn {i, _} -> i end)
    |> Enum.map(fn {i, rs} ->
      bars =
        Enum.map(rs, fn r ->
          attrs = %{
            class: "eexcharts-bar eexcharts-waterfall-#{r.point.kind}",
            data_j: r.index,
            d: Charts.Bar.bar_path(cfg, r, false),
            fill: r.color,
            fill_opacity: cfg.fill.opacity,
            stroke: Config.color_for(cfg.stroke.colors, i),
            stroke_width: cfg.stroke.width
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
  end

  @doc """
  Connector segments `{x1, x2, y}` between consecutive bars of one series, at
  the running total the first ends on and the second starts from.
  """
  def connector_segments(rects, %Layout{} = l) do
    rects
    |> Enum.sort_by(& &1.index)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] ->
      {a.x + a.w, b.x, Layout.y_for(l, clamp(l, a.point.total))}
    end)
  end

  defp connectors(cfg, rects, l) do
    c = cfg.plot_options.waterfall.connector

    if c.show do
      Enum.map(connector_segments(rects, l), fn {x1, x2, y} ->
        el("line", %{
          class: "eexcharts-waterfall-connector",
          x1: x1,
          y1: y,
          x2: x2,
          y2: y,
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
            fill: Config.color_for(dl.style.colors, r.series) || r.color,
            font_size: dl.style.font_size,
            font_weight: dl.style.font_weight,
            class: "eexcharts-datalabel"
          },
          esc(format_label(cfg, v, r.series, r.index))
        )
      end)

    el("g", %{class: "eexcharts-datalabels"}, labels)
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

  defp color(cfg, kind), do: Map.fetch!(cfg.plot_options.waterfall.colors, kind)

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)
end
