defmodule EexCharts.Charts.Line do
  @moduledoc """
  Line and area series rendering, ported from ApexCharts `src/charts/Line.js`.

  Supported `stroke.curve` values: `:smooth` (cubic beziers with control
  points offset by 35% of the x-gap — ApexCharts' constant), `:straight`,
  `:stepline`, `:monotone_cubic` (Fritsch–Carlson monotone spline). `nil`
  values split the line into segments.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout}

  @smooth_factor 0.35

  @doc "Renders all series of a line/area chart as an SVG group."
  def render(cfg, series, %Layout{} = l, id) do
    area? = cfg.chart.type == :area
    base_y = area_base_y(l)

    defs =
      if area? and cfg.fill.type == :gradient do
        el(
          "defs",
          %{},
          Enum.map(series, fn s -> gradient_def(cfg, s.index, id) end)
        )
      else
        []
      end

    groups =
      Enum.map(series, fn s ->
        i = s.index
        color = Config.color_at(cfg, i)
        points = points_for(s.data, l)
        segments = segments(points)

        area =
          if area? do
            fill =
              if cfg.fill.type == :gradient,
                do: "url(##{id}-grad-#{i})",
                else: color

            opacity = if cfg.fill.type == :gradient, do: nil, else: cfg.fill.opacity

            Enum.map(segments, fn seg ->
              el("path", %{
                d: [line_path(seg, curve(cfg)), area_close(seg, base_y)],
                fill: fill,
                fill_opacity: opacity,
                stroke: "none"
              })
            end)
          else
            []
          end

        line =
          if cfg.stroke.show do
            Enum.map(segments, fn
              [_only_one] ->
                []

              seg ->
                el("path", %{
                  d: line_path(seg, curve(cfg)),
                  fill: "none",
                  stroke: color,
                  stroke_width: cfg.stroke.width,
                  stroke_linecap: cfg.stroke.line_cap,
                  stroke_linejoin: "round",
                  stroke_dasharray: dash(cfg.stroke.dash_array, i)
                })
            end)
          else
            []
          end

        el("g", %{class: "eexcharts-series", seriesName: nil}, [
          area,
          line,
          markers(cfg, points, color, i)
        ])
      end)

    [defs, groups]
  end

  @doc "Hover markers (hidden until the hook activates a data point index)."
  def hover_markers(cfg, series, %Layout{} = l) do
    r = hover_radius(cfg)

    Enum.map(series, fn s ->
      color = Config.color_at(cfg, s.index)

      s.data
      |> points_for(l)
      |> Enum.map(fn
        {_j, nil, _x} ->
          []

        {j, _v, {x, y}} ->
          el("circle", %{
            class: "eexcharts-hover-marker",
            data_j: j,
            cx: x,
            cy: y,
            r: r,
            fill: color,
            stroke: cfg.markers.stroke_colors,
            stroke_width: cfg.markers.stroke_width
          })
      end)
    end)
  end

  defp hover_radius(cfg) do
    cfg.markers.hover.size || max(cfg.markers.size, 2) + cfg.markers.hover.size_offset
  end

  defp curve(cfg), do: cfg.stroke.curve

  defp dash(0, _i), do: nil
  defp dash(n, _i) when is_number(n), do: to_string(n)
  defp dash(list, i) when is_list(list), do: to_string(Enum.at(list, i, 0))

  # Area fills fall to the zero baseline (clamped into the grid).
  defp area_base_y(l), do: Layout.zero_y(l)

  defp points_for(data, l) do
    Enum.with_index(data, fn v, j ->
      if is_number(v) do
        {j, v, {Layout.category_pos(l, j), Layout.y_for(l, v)}}
      else
        {j, nil, nil}
      end
    end)
  end

  # Splits into lists of consecutive non-nil points.
  defp segments(points) do
    points
    |> Enum.chunk_by(fn {_j, v, _} -> v == nil end)
    |> Enum.reject(fn [{_j, v, _} | _] -> v == nil end)
    |> Enum.map(fn seg -> Enum.map(seg, fn {_j, _v, xy} -> xy end) end)
  end

  @doc false
  def line_path([{x, y}], _curve), do: move(x, y)

  def line_path([{x0, y0} | _] = pts, :smooth) do
    body =
      pts
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [{px, py}, {x, y}] ->
        len = (x - px) * @smooth_factor
        curve(px + len, py, x - len, y, x, y)
      end)

    [move(x0, y0), body]
  end

  def line_path([{x0, y0} | rest], :stepline) do
    body = Enum.map(rest, fn {x, y} -> [hline(x), vline(y)] end)
    [move(x0, y0), body]
  end

  def line_path([{x0, y0} | _] = pts, :monotone_cubic) do
    [move(x0, y0), monotone_beziers(pts)]
  end

  def line_path([{x0, y0} | rest], _straight) do
    [move(x0, y0), Enum.map(rest, fn {x, y} -> line(x, y) end)]
  end

  defp area_close(pts, base_y) do
    {x_first, _} = List.first(pts)
    {x_last, _} = List.last(pts)
    [line(x_last, base_y), line(x_first, base_y), close()]
  end

  # Fritsch–Carlson monotone cubic tangents, port of
  # apexcharts src/libs/monotone-cubic.js.
  defp monotone_beziers([_] = _pts), do: []

  defp monotone_beziers(pts) do
    xs = Enum.map(pts, &elem(&1, 0))
    ys = Enum.map(pts, &elem(&1, 1))
    n = length(pts)

    slopes =
      Enum.zip(Enum.chunk_every(pts, 2, 1, :discard), 0..(n - 2))
      |> Enum.map(fn {[{x1, y1}, {x2, y2}], _i} ->
        if x2 == x1, do: 0.0, else: (y2 - y1) / (x2 - x1)
      end)

    # Initial tangents: average of adjacent secants.
    m0 =
      [List.first(slopes)] ++
        (slopes
         |> Enum.chunk_every(2, 1, :discard)
         |> Enum.map(fn [a, b] -> (a + b) / 2 end)) ++
        [List.last(slopes)]

    # Fritsch–Carlson clamp for monotonicity.
    m =
      Enum.reduce(0..(n - 2), List.to_tuple(m0), fn i, m ->
        d = Enum.at(slopes, i)

        cond do
          abs(d) < 1.0e-6 ->
            m |> put_elem(i, 0.0) |> put_elem(i + 1, 0.0)

          true ->
            a = elem(m, i) / d
            b = elem(m, i + 1) / d
            s = a * a + b * b

            if s > 9 do
              s = 3 * d / :math.sqrt(s)
              m |> put_elem(i, s * a) |> put_elem(i + 1, s * b)
            else
              m
            end
        end
      end)

    # Control arms: 1/6 of the neighbour x-spacing, damped by slope.
    tangents =
      Enum.map(0..(n - 1), fn i ->
        prev_x = Enum.at(xs, max(i - 1, 0))
        next_x = Enum.at(xs, min(i + 1, n - 1))
        mi = elem(m, i)
        s = (next_x - prev_x) / (6 * (1 + mi * mi))
        {s, mi * s}
      end)

    Enum.map(0..(n - 2), fn i ->
      {x1, y1} = {Enum.at(xs, i), Enum.at(ys, i)}
      {x2, y2} = {Enum.at(xs, i + 1), Enum.at(ys, i + 1)}
      {tx1, ty1} = Enum.at(tangents, i)
      {tx2, ty2} = Enum.at(tangents, i + 1)
      curve(x1 + tx1, y1 + ty1, x2 - tx2, y2 - ty2, x2, y2)
    end)
  end

  defp markers(cfg, points, color, _i) do
    if cfg.markers.size > 0 do
      Enum.map(points, fn
        {_j, nil, _} ->
          []

        {j, _v, {x, y}} ->
          el("circle", %{
            class: "eexcharts-marker",
            data_j: j,
            cx: x,
            cy: y,
            r: cfg.markers.size,
            fill: cfg.markers.colors || color,
            fill_opacity: cfg.markers.fill_opacity,
            stroke: cfg.markers.stroke_colors,
            stroke_width: cfg.markers.stroke_width,
            stroke_opacity: cfg.markers.stroke_opacity
          })
      end)
    else
      []
    end
  end

  # Area gradient: ApexCharts area defaults — vertical, light shade,
  # opacity 0.65 -> 0.5, the "to" color blended toward white.
  defp gradient_def(cfg, i, id) do
    color = Config.color_at(cfg, i)
    g = cfg.fill.gradient
    to_color = EexCharts.Color.shade(color, g.shade_intensity)

    el(
      "linearGradient",
      %{id: "#{id}-grad-#{i}", x1: 0, y1: 0, x2: 0, y2: 1},
      [
        el("stop", %{offset: "0%", stop_color: color, stop_opacity: g.opacity_from}),
        el("stop", %{offset: "100%", stop_color: to_color, stop_opacity: g.opacity_to})
      ]
    )
  end
end
