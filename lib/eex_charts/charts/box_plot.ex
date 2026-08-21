defmodule EexCharts.Charts.BoxPlot do
  @moduledoc """
  Box plot series rendering, ported from ApexCharts
  `src/charts/BoxCandlestick.js`.

  Data shape: `[[min, q1, median, q3, max], ...]` or
  `[%{x: label, y: [min, q1, median, q3, max]}, ...]` (categories come from
  the x-axis). Multiple series sit side-by-side in each category slot like
  grouped columns.

  The box spans `q1`..`q3` and is split in two fills at the median: the lower
  half (`q1`..`median`) uses `plot_options.box_plot.colors.lower`, the upper
  half (`median`..`q3`) uses `colors.upper`. A median line runs across the box;
  whiskers extend `min`..`q1` and `q3`..`max` as vertical lines with
  horizontal end caps. All outlines use `stroke` (`#24292e` default).
  """

  import EexCharts.SVG

  alias EexCharts.Layout

  @doc "Renders box plot series into the cartesian grid."
  def render(cfg, series, %Layout{} = l, opts \\ []) do
    on_click = opts[:on_click]
    colors = cfg.plot_options.box_plot.colors
    stroke_w = cfg.stroke.width

    n_series = length(series)
    slot = l.grid_w / l.n
    bar_w = slot / max(n_series, 1) * pct(cfg.plot_options.bar.column_width) / 100

    series
    |> Enum.with_index()
    |> Enum.map(fn {s, pos_i} ->
      stroke = stroke_color(cfg, s.index) || "#24292e"

      elements =
        s.data
        |> Enum.with_index()
        |> Enum.flat_map(fn {p, j} ->
          case five(p) do
            [mn, q1, med, q3, mx] ->
              group_x = l.grid_x + slot * j + (slot - bar_w * n_series) / 2
              x = group_x + bar_w * pos_i
              cx = x + bar_w / 2

              y_mn = Layout.y_for(l, clamp(l, mn))
              y_q1 = Layout.y_for(l, clamp(l, q1))
              y_med = Layout.y_for(l, clamp(l, med))
              y_q3 = Layout.y_for(l, clamp(l, q3))
              y_mx = Layout.y_for(l, clamp(l, mx))

              cap_l = x + bar_w / 4
              cap_r = x + bar_w - bar_w / 4

              base = %{data_j: j, stroke: stroke, stroke_width: max(stroke_w, 1)}
              base = click(base, on_click, j, s.index)

              lower_box =
                el(
                  "rect",
                  Map.merge(base, %{
                    class: "eexcharts-boxplot-lower",
                    x: x,
                    y: min(y_med, y_q1),
                    width: bar_w,
                    height: abs(y_q1 - y_med),
                    fill: colors.lower,
                    fill_opacity: cfg.fill.opacity
                  })
                )

              upper_box =
                el(
                  "rect",
                  Map.merge(base, %{
                    class: "eexcharts-boxplot-upper",
                    x: x,
                    y: min(y_q3, y_med),
                    width: bar_w,
                    height: abs(y_med - y_q3),
                    fill: colors.upper,
                    fill_opacity: cfg.fill.opacity
                  })
                )

              median_line =
                el("line", Map.merge(base, %{x1: x, x2: x + bar_w, y1: y_med, y2: y_med}))

              lower_whisker =
                el("line", Map.merge(base, %{x1: cx, x2: cx, y1: y_q1, y2: y_mn}))

              lower_cap =
                el("line", Map.merge(base, %{x1: cap_l, x2: cap_r, y1: y_mn, y2: y_mn}))

              upper_whisker =
                el("line", Map.merge(base, %{x1: cx, x2: cx, y1: y_q3, y2: y_mx}))

              upper_cap =
                el("line", Map.merge(base, %{x1: cap_l, x2: cap_r, y1: y_mx, y2: y_mx}))

              [
                lower_whisker,
                lower_cap,
                upper_whisker,
                upper_cap,
                lower_box,
                upper_box,
                median_line
              ]

            nil ->
              []
          end
        end)

      el("g", %{class: "eexcharts-series"}, elements)
    end)
  end

  @doc "Returns `{y_min, y_max}` across all five-number summaries."
  def data_range(series) do
    values =
      series
      |> Enum.flat_map(& &1.data)
      |> Enum.flat_map(fn p -> five(p) || [] end)
      |> Enum.filter(&is_number/1)

    case values do
      [] -> {nil, nil}
      _ -> Enum.min_max(values)
    end
  end

  @doc "Formats one box data point for the tooltip."
  def tooltip_value(cfg, v) do
    case five(v) do
      [mn, q1, med, q3, mx] ->
        "Min: #{fmt_num(cfg, mn)} Q1: #{fmt_num(cfg, q1)} Median: #{fmt_num(cfg, med)} " <>
          "Q3: #{fmt_num(cfg, q3)} Max: #{fmt_num(cfg, mx)}"

      nil ->
        ""
    end
  end

  defp five(%{y: [mn, q1, med, q3, mx | _]}), do: [mn, q1, med, q3, mx]
  defp five([mn, q1, med, q3, mx | _]), do: [mn, q1, med, q3, mx]
  defp five(_), do: nil

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)

  # ApexCharts indexes `stroke.colors` by series, so each box can be outlined
  # in its own series color.
  defp stroke_color(cfg, i) do
    case cfg.stroke.colors do
      nil -> nil
      [] -> nil
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
