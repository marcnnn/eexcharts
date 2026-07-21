defmodule EexCharts.Charts.RangeBar do
  @moduledoc """
  Range bar / column series rendering, ported from ApexCharts `Bar.js` with
  range (`[from, to]`) values.

  Data shape: `[[from, to], ...]` or `[%{x: label, y: [from, to]}, ...]`
  (categories come from the x-axis). Each bar spans `from`..`to` rather than
  a zero baseline. Vertical columns are grouped side-by-side in the category
  slot (`slot / series_count * column_width%`); when the layout is horizontal
  (`plot_options.bar.horizontal`), bars run from `x_for(from)` to `x_for(to)`
  using `bar_height%`. `plot_options.bar.border_radius` rounds both ends,
  reusing `Charts.Bar.bar_path/3`.
  """

  import EexCharts.SVG

  alias EexCharts.{Charts, Config, Layout}

  @doc "Renders range bar series into the cartesian grid."
  def render(cfg, series, %Layout{} = l, opts \\ []) do
    on_click = opts[:on_click]

    cfg
    |> positions(series, l)
    |> Enum.group_by(& &1.series)
    |> Enum.sort_by(fn {i, _} -> i end)
    |> Enum.map(fn {_i, rects} ->
      el(
        "g",
        %{class: "eexcharts-series"},
        Enum.map(rects, fn r ->
          attrs = %{
            class: "eexcharts-bar",
            data_j: r.index,
            d: Charts.Bar.bar_path(cfg, r, l.horizontal),
            fill: r.color,
            fill_opacity: cfg.fill.opacity,
            stroke: stroke_color(cfg, r.series),
            stroke_width: cfg.stroke.width
          }

          attrs =
            if on_click do
              Map.merge(attrs, %{
                "phx-click" => on_click,
                "phx-value-index" => r.index,
                "phx-value-series" => r.series,
                cursor: "pointer"
              })
            else
              attrs
            end

          el("path", attrs)
        end)
      )
    end)
  end

  defp positions(cfg, series, %Layout{horizontal: true} = l) do
    n_series = length(series)
    slot = l.grid_h / l.n
    bar_h = slot / max(n_series, 1) * pct(cfg.plot_options.bar.bar_height) / 100

    series
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, pos_i} ->
      color = Config.color_at(cfg, s.index)
      group_y = fn j -> l.grid_y + slot * j + (slot - bar_h * n_series) / 2 end

      s.data
      |> Enum.with_index()
      |> Enum.flat_map(fn {p, j} ->
        case range(p) do
          [from, to] ->
            x_from = Layout.x_for(l, clamp(l, from))
            x_to = Layout.x_for(l, clamp(l, to))

            [
              %{
                series: s.index,
                index: j,
                x: min(x_from, x_to),
                y: group_y.(j) + bar_h * pos_i,
                w: abs(x_to - x_from),
                h: bar_h,
                color: color,
                positive: to >= from,
                last_in_stack: true
              }
            ]

          nil ->
            []
        end
      end)
    end)
  end

  defp positions(cfg, series, l) do
    n_series = length(series)
    slot = l.grid_w / l.n
    bar_w = slot / max(n_series, 1) * pct(cfg.plot_options.bar.column_width) / 100

    series
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, pos_i} ->
      color = Config.color_at(cfg, s.index)
      group_x = fn j -> l.grid_x + slot * j + (slot - bar_w * n_series) / 2 end

      s.data
      |> Enum.with_index()
      |> Enum.flat_map(fn {p, j} ->
        case range(p) do
          [from, to] ->
            y_from = Layout.y_for(l, clamp(l, from))
            y_to = Layout.y_for(l, clamp(l, to))

            [
              %{
                series: s.index,
                index: j,
                x: group_x.(j) + bar_w * pos_i,
                y: min(y_from, y_to),
                w: bar_w,
                h: abs(y_from - y_to),
                color: color,
                positive: to >= from,
                last_in_stack: true
              }
            ]

          nil ->
            []
        end
      end)
    end)
  end

  @doc "Returns `{y_min, y_max}` across all ranges."
  def data_range(series) do
    values =
      series
      |> Enum.flat_map(& &1.data)
      |> Enum.flat_map(fn p -> range(p) || [] end)
      |> Enum.filter(&is_number/1)

    case values do
      [] -> {nil, nil}
      _ -> Enum.min_max(values)
    end
  end

  @doc "Formats one range data point for the tooltip."
  def tooltip_value(cfg, v) do
    case range(v) do
      [from, to] -> "#{fmt_num(cfg, from)} – #{fmt_num(cfg, to)}"
      nil -> ""
    end
  end

  defp range(%{y: [from, to | _]}), do: [from, to]
  defp range([from, to | _]), do: [from, to]
  defp range(_), do: nil

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)

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

  defp pct(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 70
    end
  end

  defp pct(value) when is_number(value), do: value
end
