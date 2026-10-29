defmodule EexCharts.Charts.Heatmap.GradientLegend do
  @moduledoc """
  Continuous colour-bar legend for heatmaps shaded without colour ranges.

  Enable it with `legend: %{gradient: true}` or a map of options:

      legend: %{gradient: %{position: :right, thickness: 12, length: 200}}

    * `:position` - `:bottom` (default, horizontal bar under the x labels),
      `:top` (horizontal, between title and plot) or `:right` (vertical bar,
      maximum at the top).
    * `:thickness` - bar thickness in px (default `10`).
    * `:length` - bar length in px. Defaults to half the plot width clamped
      to 120-360px for horizontal bars, and the full plot height for `:right`.

  The bar is a `linearGradient` whose stops are produced by the same shade
  function that colours the cells, at the global minimum, at zero (when the
  data spans it, where the shading changes direction) and at the maximum.
  Between stops the shading is linear in the value, so the bar matches the
  cells exactly. Tick labels mark the minimum and maximum (plus zero when
  it sits well inside the range); they use `data_labels.formatter` when one
  is set.

  The bar is drawn in the hue of the first visible series, so it describes
  the chart faithfully when every row shares one colour (set a single
  `colors` entry, or `plot_options.heatmap.distributed: false` with one
  colour). It is ignored when `plot_options.heatmap.color_scale.ranges` are
  configured (the range legend is shown) or when `legend.show` is false.
  """

  import EexCharts.SVG

  alias EexCharts.Layout

  @pad 8
  @gap 4

  @doc "Resolves the gradient legend options, or `nil` when it is off."
  def options(cfg, ranges) do
    case {Map.get(cfg.legend, :gradient, false), ranges, cfg.legend.show} do
      {false, _, _} -> nil
      {nil, _, _} -> nil
      {_, [_ | _], _} -> nil
      {_, _, false} -> nil
      {true, [], true} -> resolve(%{})
      {%{} = g, [], true} -> if Map.get(g, :enabled, true), do: resolve(g)
    end
  end

  defp resolve(g) do
    %{
      position: Map.get(g, :position, :bottom),
      thickness: Map.get(g, :thickness, 10),
      length: Map.get(g, :length)
    }
  end

  @doc """
  Tick values for the bar: min, max and zero when it lies inside the range.
  """
  def tick_values(%{min: min, max: max}) do
    if min < 0 and max > 0, do: [min, 0, max], else: Enum.uniq([min, max])
  end

  @doc """
  Gradient stops as `[{value, fraction, color}]`, `fraction` running from 0
  (minimum) to 1 (maximum). `color_fn` is the cell shade function.
  """
  def stops(ctx, color_fn) do
    span = ctx.max - ctx.min

    ctx
    |> tick_values()
    |> Enum.map(fn v ->
      frac = if span == 0, do: 0.0, else: (v - ctx.min) / span
      {v, frac, color_fn.(v)}
    end)
  end

  @doc """
  Space the legend takes: `{top_h, bottom_h, right_w}`.
  """
  def reserve(nil, _cfg, _ctx), do: {0, 0, 0}

  def reserve(opts, cfg, ctx) do
    font = cfg.legend.font_size

    case opts.position do
      :right ->
        label_w =
          ctx
          |> tick_values()
          |> Enum.map(&Layout.text_width(label(cfg, &1), font))
          |> Enum.max(fn -> 0 end)

        {0, 0, @pad + opts.thickness + @gap + 2 + label_w + @pad}

      :top ->
        {band_h(opts, font), 0, 0}

      _ ->
        {0, band_h(opts, font), 0}
    end
  end

  defp band_h(opts, font), do: @pad + opts.thickness + @gap + font + @pad

  @doc "Renders the bar, its gradient definition and tick labels."
  def render(nil, _cfg, _l, _id, _ctx, _color_fn), do: []

  def render(opts, cfg, %Layout{} = l, id, ctx, color_fn) do
    font = cfg.legend.font_size
    fore = cfg.legend.labels.colors || cfg.chart.fore_color
    grad_id = "#{id}-heatmap-legend-grad"
    t = opts.thickness
    stops = stops(ctx, color_fn)
    vertical? = opts.position == :right

    # Zero always gets a stop (the shading turns there) but only a label
    # when it is far enough from the ends not to collide with theirs.
    labelled =
      Enum.reject(stops, fn {v, f, _} ->
        v == 0 and (f < 0.15 or f > 0.85) and length(stops) == 3
      end)

    {x1, y1, x2, y2} = if vertical?, do: {0, 1, 0, 0}, else: {0, 0, 1, 0}

    gradient =
      el("defs", %{}, [
        el(
          "linearGradient",
          %{id: grad_id, x1: x1, y1: y1, x2: x2, y2: y2},
          Enum.map(stops, fn {_v, f, c} ->
            el("stop", %{offset: "#{fmt(f * 100)}%", stop_color: c})
          end)
        )
      ])

    {bar, ticks} =
      if vertical? do
        len = opts.length || l.grid_h
        bx = l.grid_x + l.grid_w + @pad + cfg.legend.offset_x
        by = l.grid_y + (l.grid_h - len) / 2 + cfg.legend.offset_y

        ticks =
          Enum.map(labelled, fn {v, f, _c} ->
            y = by + len * (1 - f)

            [
              el("line", %{x1: bx + t, x2: bx + t + 3, y1: y, y2: y, stroke: fore}),
              el(
                "text",
                %{
                  class: "eexcharts-legend-text",
                  x: bx + t + @gap + 2,
                  y: y,
                  fill: fore,
                  font_size: font,
                  font_weight: cfg.legend.font_weight,
                  dominant_baseline: "central"
                },
                esc(label(cfg, v))
              )
            ]
          end)

        {rect(grad_id, bx, by, t, len), ticks}
      else
        len = opts.length || (l.grid_w / 2) |> max(120) |> min(360) |> min(l.grid_w)
        bx = l.grid_x + (l.grid_w - len) / 2 + cfg.legend.offset_x

        by =
          case opts.position do
            :top -> l.grid_y - band_h(opts, font) + @pad
            _ -> l.h - band_h(opts, font) + @pad
          end + cfg.legend.offset_y

        ticks =
          Enum.map(labelled, fn {v, f, _c} ->
            x = bx + len * f

            anchor =
              cond do
                f == 0 -> "start"
                f == 1 -> "end"
                true -> "middle"
              end

            [
              el("line", %{x1: x, x2: x, y1: by + t, y2: by + t + 3, stroke: fore}),
              el(
                "text",
                %{
                  class: "eexcharts-legend-text",
                  x: x,
                  y: by + t + @gap + font * 0.8,
                  fill: fore,
                  font_size: font,
                  font_weight: cfg.legend.font_weight,
                  text_anchor: anchor
                },
                esc(label(cfg, v))
              )
            ]
          end)

        {rect(grad_id, bx, by, len, t), ticks}
      end

    el("g", %{class: "eexcharts-legend eexcharts-heatmap-gradient-legend"}, [
      gradient,
      bar,
      ticks
    ])
  end

  defp rect(grad_id, x, y, w, h) do
    el("rect", %{
      class: "eexcharts-heatmap-gradient-bar",
      x: x,
      y: y,
      width: w,
      height: h,
      rx: 2,
      fill: "url(##{grad_id})"
    })
  end

  defp label(cfg, v) do
    case cfg.data_labels.formatter do
      f when is_function(f, 1) -> to_string(f.(v))
      _ -> fmt_value(v)
    end
  end
end
