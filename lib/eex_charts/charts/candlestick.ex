defmodule EexCharts.Charts.Candlestick do
  @moduledoc """
  Candlestick series rendering, ported from ApexCharts
  `src/charts/BoxCandlestick.js`.

  Data shape: `[[open, high, low, close], ...]` or
  `[%{x: label, y: [o, h, l, c]}, ...]` (categories come from the x-axis, so
  only the OHLC values are used). Multiple series are drawn side-by-side in
  each category slot like grouped columns (`slot / series_count *
  column_width%`).

  Each candle is a body rect spanning `open`..`close` — filled with
  `plot_options.candlestick.colors.upward` (`#00B746`) when `close >= open`,
  otherwise `colors.downward` (`#EF403C`) — plus a wick: a vertical line
  through the center from `high` to `low`. The wick is drawn in the body fill
  color when `wick.use_fill_color` is true, else in the stroke color. Body
  outlines use `stroke`.
  """

  import EexCharts.SVG

  alias EexCharts.Layout

  @doc "Renders candlestick series into the cartesian grid."
  def render(cfg, series, %Layout{} = l, opts \\ []) do
    on_click = opts[:on_click]
    candle = cfg.plot_options.candlestick
    up = candle.colors.upward
    down = candle.colors.downward
    use_fill = candle.wick.use_fill_color
    stroke_w = cfg.stroke.width

    n_series = length(series)
    slot = l.grid_w / l.n
    bar_w = slot / max(n_series, 1) * pct(cfg.plot_options.bar.column_width) / 100

    series
    |> Enum.with_index()
    |> Enum.map(fn {s, pos_i} ->
      stroke = stroke_color(cfg, s.index)

      elements =
        s.data
        |> Enum.with_index()
        |> Enum.flat_map(fn {p, j} ->
          case ohlc(p) do
            [o, h, low, c] ->
              color =
                if c >= o,
                  do: resolve_color(up, s.index),
                  else: resolve_color(down, s.index)

              group_x = l.grid_x + slot * j + (slot - bar_w * n_series) / 2
              x = group_x + bar_w * pos_i
              cx = x + bar_w / 2

              y_top = Layout.y_for(l, clamp(l, max(o, c)))
              y_bot = Layout.y_for(l, clamp(l, min(o, c)))
              y_high = Layout.y_for(l, clamp(l, h))
              y_low = Layout.y_for(l, clamp(l, low))

              wick_color = if use_fill, do: color, else: stroke

              wick =
                el(
                  "line",
                  click(
                    %{
                      class: "eexcharts-candlestick-wick",
                      data_j: j,
                      x1: cx,
                      x2: cx,
                      y1: y_high,
                      y2: y_low,
                      stroke: wick_color,
                      stroke_width: max(stroke_w, 1)
                    },
                    on_click,
                    j,
                    s.index
                  )
                )

              body =
                el(
                  "rect",
                  click(
                    %{
                      class: "eexcharts-candlestick",
                      data_j: j,
                      x: x,
                      y: y_top,
                      width: bar_w,
                      height: abs(y_bot - y_top),
                      fill: color,
                      fill_opacity: cfg.fill.opacity,
                      stroke: stroke,
                      stroke_width: stroke_w
                    },
                    on_click,
                    j,
                    s.index
                  )
                )

              [wick, body]

            nil ->
              []
          end
        end)

      el("g", %{class: "eexcharts-series"}, elements)
    end)
  end

  @doc "Returns `{y_min, y_max}` across all OHLC values."
  def data_range(series) do
    values =
      series
      |> Enum.flat_map(& &1.data)
      |> Enum.flat_map(fn p -> ohlc(p) || [] end)
      |> Enum.filter(&is_number/1)

    case values do
      [] -> {nil, nil}
      _ -> Enum.min_max(values)
    end
  end

  @doc "Formats one OHLC data point for the tooltip."
  def tooltip_value(cfg, v) do
    case ohlc(v) do
      [o, h, low, c] ->
        "O: #{fmt_num(cfg, o)} H: #{fmt_num(cfg, h)} L: #{fmt_num(cfg, low)} C: #{fmt_num(cfg, c)}"

      nil ->
        ""
    end
  end

  defp ohlc(%{y: [o, h, l, c | _]}), do: [o, h, l, c]
  defp ohlc([o, h, l, c | _]), do: [o, h, l, c]
  defp ohlc(_), do: nil

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)

  defp resolve_color(colors, i) when is_list(colors),
    do: Enum.at(colors, rem(i, length(colors)))

  defp resolve_color(color, _i), do: color

  defp stroke_color(cfg, i) do
    case cfg.stroke.colors do
      nil -> nil
      colors when is_list(colors) -> Enum.at(colors, rem(i, length(colors)))
      color -> color
    end
  end

  defp fmt_num(cfg, n) do
    case cfg.tooltip.y_formatter do
      f when is_function(f, 1) -> to_string(f.(n))
      _ -> fmt_value(n)
    end
  end

  defp click(attrs, nil, _j, _series), do: attrs

  defp click(attrs, on_click, j, series) do
    Map.merge(attrs, %{
      "phx-click" => on_click,
      "phx-value-index" => j,
      "phx-value-series" => series,
      cursor: "pointer"
    })
  end

  defp pct(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 70
    end
  end

  defp pct(value) when is_number(value), do: value
end
