defmodule EexCharts.Charts.Bar do
  @moduledoc """
  Column / bar series rendering, ported from ApexCharts `src/charts/Bar.js`
  and `BarStacked.js`.

  Columns share a category slot (`grid_w / n`); each visible series gets
  `slot / series_count * column_width%` pixels, centered as a group in the
  slot. Values are drawn from the zero baseline, so negatives extend the
  other way. Stacked bars accumulate positive and negative totals separately.
  `border_radius` rounds the value-end corners (`:end`) or all corners
  (`:around`).
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout}

  @doc "Renders all bar series as an SVG group; returns `{iodata, bar_rects}`."
  def render(cfg, series, %Layout{} = l, opts \\ []) do
    bars = positions(cfg, series, l)
    on_click = opts[:on_click]

    io =
      bars
      |> Enum.group_by(& &1.series)
      |> Enum.sort_by(fn {i, _} -> i end)
      |> Enum.map(fn {i, rects} ->
        el(
          "g",
          %{class: "eexcharts-series"},
          Enum.map(rects, fn r ->
            attrs = %{
              class: "eexcharts-bar",
              data_j: r.index,
              d: bar_path(cfg, r, l.horizontal),
              fill: r.color,
              fill_opacity: cfg.fill.opacity,
              stroke: stroke_color(cfg, i),
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

    {io, bars}
  end

  @doc """
  Computes every bar rectangle: `%{series, index, x, y, w, h, value, color,
  positive}` with `{x, y}` the top-left corner.
  """
  def positions(cfg, series, %Layout{} = l) do
    if l.horizontal do
      horizontal_positions(cfg, series, l)
    else
      column_positions(cfg, series, l)
    end
  end

  defp column_positions(cfg, series, l) do
    bar_cfg = cfg.plot_options.bar
    n_series = length(series)
    slot = l.grid_w / l.n
    zero = Layout.zero_y(l)

    if cfg.chart.stacked do
      bar_w = slot * pct(bar_cfg.column_width) / 100

      series
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, pos_i} ->
        color = Config.color_at(cfg, s.index)

        Enum.with_index(s.data, fn v, j ->
          v = v || 0
          {pos, neg} = stack_base(series, pos_i, j)
          base = if v >= 0, do: pos, else: neg
          y_from = Layout.y_for(l, clamp(l, base))
          y_to = Layout.y_for(l, clamp(l, base + v))
          x = l.grid_x + slot * j + (slot - bar_w) / 2

          %{
            series: s.index,
            index: j,
            x: x,
            y: min(y_from, y_to),
            w: bar_w,
            h: abs(y_from - y_to),
            value: v,
            color: bar_color(cfg, s.index, j, color),
            positive: v >= 0,
            last_in_stack: last_nonzero?(series, pos_i, j, v)
          }
        end)
      end)
    else
      bar_w = slot / n_series * pct(bar_cfg.column_width) / 100

      series
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, pos_i} ->
        color = Config.color_at(cfg, s.index)
        group_x = fn j -> l.grid_x + slot * j + (slot - bar_w * n_series) / 2 end

        s.data
        |> Enum.with_index()
        |> Enum.reject(fn {v, _j} -> v == nil end)
        |> Enum.map(fn {v, j} ->
          y_v = Layout.y_for(l, clamp(l, v))

          %{
            series: s.index,
            index: j,
            x: group_x.(j) + bar_w * pos_i,
            y: min(y_v, zero),
            w: bar_w,
            h: abs(zero - y_v),
            value: v,
            color: bar_color(cfg, s.index, j, color),
            positive: v >= 0,
            last_in_stack: true
          }
        end)
      end)
    end
  end

  defp horizontal_positions(cfg, series, l) do
    bar_cfg = cfg.plot_options.bar
    n_series = length(series)
    slot = l.grid_h / l.n
    zero = Layout.zero_x(l)

    if cfg.chart.stacked do
      bar_h = slot * pct(bar_cfg.bar_height) / 100

      series
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, pos_i} ->
        color = Config.color_at(cfg, s.index)

        Enum.with_index(s.data, fn v, j ->
          v = v || 0
          {pos, neg} = stack_base(series, pos_i, j)
          base = if v >= 0, do: pos, else: neg
          x_from = Layout.x_for(l, clamp(l, base))
          x_to = Layout.x_for(l, clamp(l, base + v))
          y = l.grid_y + slot * j + (slot - bar_h) / 2

          %{
            series: s.index,
            index: j,
            x: min(x_from, x_to),
            y: y,
            w: abs(x_to - x_from),
            h: bar_h,
            value: v,
            color: bar_color(cfg, s.index, j, color),
            positive: v >= 0,
            last_in_stack: last_nonzero?(series, pos_i, j, v)
          }
        end)
      end)
    else
      bar_h = slot / n_series * pct(bar_cfg.bar_height) / 100

      series
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, pos_i} ->
        color = Config.color_at(cfg, s.index)

        s.data
        |> Enum.with_index()
        |> Enum.reject(fn {v, _j} -> v == nil end)
        |> Enum.map(fn {v, j} ->
          x_v = Layout.x_for(l, clamp(l, v))
          group_y = l.grid_y + slot * j + (slot - bar_h * n_series) / 2

          %{
            series: s.index,
            index: j,
            x: min(x_v, zero),
            y: group_y + bar_h * pos_i,
            w: abs(x_v - zero),
            h: bar_h,
            value: v,
            color: bar_color(cfg, s.index, j, color),
            positive: v >= 0,
            last_in_stack: true
          }
        end)
      end)
    end
  end

  # Sum of values stacked below series `i` at datapoint `j`, split by sign.
  defp stack_base(series, i, j) do
    series
    |> Enum.take(i)
    |> Enum.map(fn s -> Enum.at(s.data, j) || 0 end)
    |> Enum.reduce({0, 0}, fn v, {pos, neg} ->
      if v >= 0, do: {pos + v, neg}, else: {pos, neg + v}
    end)
  end

  defp last_nonzero?(series, i, j, v) do
    v != 0 and
      series
      |> Enum.drop(i + 1)
      |> Enum.all?(fn s ->
        val = Enum.at(s.data, j) || 0
        val == 0 or val >= 0 != v >= 0
      end)
  end

  defp clamp(l, v) do
    v |> max(l.scale.nice_min) |> min(l.scale.nice_max)
  end

  # `distributed: true` colors each bar by its data point index.
  defp bar_color(cfg, _i, j, color) do
    if cfg.plot_options.bar.distributed, do: Config.color_at(cfg, j), else: color
  end

  defp stroke_color(cfg, i) do
    case cfg.stroke.colors do
      nil -> nil
      colors when is_list(colors) -> Enum.at(colors, rem(i, length(colors)))
      color -> color
    end
  end

  defp pct(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 70
    end
  end

  defp pct(value) when is_number(value), do: value

  @doc false
  # Builds the bar path, rounding corners according to border_radius settings.
  def bar_path(cfg, r, horizontal?) do
    radius = cfg.plot_options.bar.border_radius
    application = cfg.plot_options.bar.border_radius_application

    rounded? = radius > 0 and (r.last_in_stack or application == :around)

    cond do
      not rounded? ->
        rect_path(r.x, r.y, r.w, r.h)

      application == :around ->
        rounded_rect_path(r, min(radius, min(r.w, r.h) / 2), :all, horizontal?)

      true ->
        rounded_rect_path(r, min(radius, min(r.w, r.h) / 2), :end, horizontal?)
    end
  end

  defp rect_path(x, y, w, h) do
    [move(x, y), line(x + w, y), line(x + w, y + h), line(x, y + h), " Z"]
  end

  # `:end` rounds the two corners at the value end of the bar (which end that
  # is depends on sign and orientation); `:all` rounds every corner.
  defp rounded_rect_path(r, rad, which, horizontal?) do
    %{x: x, y: y, w: w, h: h} = r

    {tl, tr, br, bl} =
      case which do
        :all ->
          {rad, rad, rad, rad}

        :end ->
          if horizontal? do
            if r.positive, do: {0, rad, rad, 0}, else: {rad, 0, 0, rad}
          else
            if r.positive, do: {rad, rad, 0, 0}, else: {0, 0, rad, rad}
          end
      end

    [
      move(x + tl, y),
      line(x + w - tr, y),
      if(tr > 0, do: arc(tr, tr, 0, 0, 1, x + w, y + tr), else: []),
      line(x + w, y + h - br),
      if(br > 0, do: arc(br, br, 0, 0, 1, x + w - br, y + h), else: []),
      line(x + bl, y + h),
      if(bl > 0, do: arc(bl, bl, 0, 0, 1, x, y + h - bl), else: []),
      line(x, y + tl),
      if(tl > 0, do: arc(tl, tl, 0, 0, 1, x + tl, y), else: []),
      " Z"
    ]
  end
end
