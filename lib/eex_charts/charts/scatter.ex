defmodule EexCharts.Charts.Scatter do
  @moduledoc """
  Scatter and bubble series rendering, ported from ApexCharts
  `src/charts/Scatter.js`.

  Data shapes: scatter `[y, ...]` or `[[x, y], ...]`; bubble `[[x, y, z], ...]`.
  Scatter markers use `markers.size`; bubble radii scale from the `z` value by
  `z / zRatio`, where `zRatio = (zRange / gridHeight) * 16` (clamped by the
  optional `min_bubble_radius` / `max_bubble_radius`). Every marker carries a
  `data-j` slot index so the shared tooltip/crosshair hook keeps working.

  ## Clicks

  Pass `on_click: "event-name"` and every marker gets `phx-click` plus
  `phx-value-series` / `phx-value-index`, the same contract the bar and box-plot
  renderers use. A scatter cannot reuse the hover *zones* the category charts
  get: zones are one rect per category slot, and `Layout.value_x?/1` is true for
  a numeric x axis, so the renderer skips them entirely. Here the marker itself
  is the target, which is what you want anyway — a scatter point is an entity,
  not a slot on an axis.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, Marker}

  @doc """
  Renders scatter/bubble series into the cartesian grid.

  Options: `:on_click` — a LiveView event name to fire per marker.

  `markers.discrete` restyles single points, as in ApexCharts: a list of
  `%{series_index:, data_point_index:}` maps with any of `fill_color`,
  `stroke_color`, `stroke_width`, `size` and `shape`. A restyled marker also
  gets the `eexcharts-marker-discrete` class, so CSS can re-tint it per theme.
  """
  def render(cfg, series, %Layout{} = l, _id, opts \\ []) do
    bubble? = cfg.chart.type == :bubble
    zratio = if bubble?, do: z_ratio(series, l), else: nil

    groups =
      Enum.map(series, fn s ->
        color = Config.color_at(cfg, s.index)
        scale = Layout.scale_for_series(l, s)
        shape = Marker.shape_for(cfg.markers.shape, s.index)
        discrete = discrete_for(cfg, s.index)

        markers =
          cfg
          |> Layout.series_points(s.data)
          |> Enum.map(fn {j, x, y, z} ->
            if is_number(x) and is_number(y) do
              cx = Layout.x_value_pos(l, x)
              cy = Layout.y_for(l, y, scale)
              r = radius(cfg, z, zratio)
              d = Map.get(discrete, j)

              attrs =
                maybe_click(
                  apply_discrete(
                    %{
                      class: "eexcharts-marker",
                      data_j: j,
                      data_cx: cx,
                      fill: Config.color_for(cfg.markers.colors, s.index) || color,
                      fill_opacity: cfg.fill.opacity,
                      stroke: Config.color_for(cfg.markers.stroke_colors, s.index),
                      stroke_width: cfg.markers.stroke_width,
                      stroke_opacity: cfg.markers.stroke_opacity
                    },
                    d
                  ),
                  opts[:on_click],
                  s.index,
                  j
                )

              Marker.render(
                discrete_value(d, :shape, shape),
                cx,
                cy,
                discrete_value(d, :size, r),
                attrs
              )
            else
              []
            end
          end)

        el("g", %{class: "eexcharts-series"}, markers)
      end)

    el("g", %{class: "eexcharts-scatter"}, groups)
  end

  # `markers.discrete` entries for one series, keyed by data point index.
  defp discrete_for(cfg, series_index) do
    for d <- Map.get(cfg.markers, :discrete) || [],
        d.series_index == series_index,
        into: %{},
        do: {d.data_point_index, d}
  end

  defp apply_discrete(attrs, nil), do: attrs

  defp apply_discrete(attrs, d) do
    %{
      attrs
      | class: attrs.class <> " eexcharts-marker-discrete",
        fill: discrete_value(d, :fill_color, attrs.fill),
        stroke: discrete_value(d, :stroke_color, attrs.stroke),
        stroke_width: discrete_value(d, :stroke_width, attrs.stroke_width)
    }
  end

  defp discrete_value(nil, _key, default), do: default
  defp discrete_value(d, key, default), do: Map.get(d, key) || default

  # Same attribute contract as Bar/BoxPlot: the handler gets both indexes, so a
  # caller can map (series, index) back to whatever entity the point stands for.
  defp maybe_click(attrs, nil, _i, _j), do: attrs

  defp maybe_click(attrs, event, i, j) do
    Map.merge(attrs, %{
      "phx-click" => event,
      "phx-value-series" => i,
      "phx-value-index" => j,
      cursor: "pointer"
    })
  end

  # Bubble radius scaling: zRatio = (zRange / gridHeight) * 16
  # (CoreUtils.getCoordinates); radius = z / zRatio (Scatter.js drawPoint).
  defp z_ratio(series, %Layout{} = l) do
    zs = for s <- series, v <- s.data, z = point_z(v), is_number(z), do: z

    case zs do
      [] ->
        1

      _ ->
        {zmin, zmax} = Enum.min_max(zs)
        ratio = abs(zmax - zmin) / l.grid_h * 16
        if ratio == 0, do: 1, else: ratio
    end
  end

  defp point_z([_x, _y, z | _]), do: z
  defp point_z(%{z: z}), do: z
  defp point_z(%{"z" => z}), do: z
  defp point_z(_), do: nil

  defp radius(cfg, _z, nil) do
    # Scatter: fixed marker size.
    max(cfg.markers.size, 0)
  end

  defp radius(cfg, z, zratio) when is_number(z) do
    b = cfg.plot_options.bubble
    r = if b.z_scaling, do: z / zratio, else: z

    r =
      if is_number(b.min_bubble_radius) and r < b.min_bubble_radius,
        do: b.min_bubble_radius,
        else: r

    r =
      if is_number(b.max_bubble_radius) and r > b.max_bubble_radius,
        do: b.max_bubble_radius,
        else: r

    max(r, 0)
  end

  defp radius(_cfg, _z, _zratio), do: 0

  @doc "Returns `{y_min, y_max}` for the given series (y is the 2nd element)."
  def data_range(series) do
    ys = for s <- series, v <- s.data, y = point_y(v), is_number(y), do: y

    case ys do
      [] -> {nil, nil}
      _ -> Enum.min_max(ys)
    end
  end

  defp point_y(v) when is_number(v), do: v
  defp point_y([_x, y | _]), do: y
  defp point_y(%{y: y}), do: y
  defp point_y(%{"y" => y}), do: y
  defp point_y(_), do: nil

  @doc "Formats one data point for the tooltip."
  def tooltip_value(_cfg, [x, y, z | _]),
    do: "#{fmt_value(x)}, #{fmt_value(y)} (#{fmt_value(z)})"

  def tooltip_value(_cfg, [x, y | _]), do: "#{fmt_value(x)}, #{fmt_value(y)}"
  def tooltip_value(_cfg, %{x: x, y: y}), do: "#{fmt_value(x)}, #{fmt_value(y)}"
  def tooltip_value(_cfg, %{"x" => x, "y" => y}), do: "#{fmt_value(x)}, #{fmt_value(y)}"
  def tooltip_value(_cfg, v) when is_number(v), do: fmt_value(v)
  def tooltip_value(_cfg, _v), do: ""
end
