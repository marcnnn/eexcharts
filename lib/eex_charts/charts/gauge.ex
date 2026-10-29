defmodule EexCharts.Charts.Gauge do
  @moduledoc """
  Gauge (dial) chart: one value on a `min..max` scale, drawn as an arc band
  between `start_angle` and `end_angle`, with tick marks, tick labels, a
  needle and a centre value label.

  Series: a number, `[number]`, or `[%{name: "Speed", data: [72]}]` (the first
  number is used). `labels: ["Speed"]` names it.

  ## Options (`plot_options.gauge`)

    * `start_angle` / `end_angle` (default `-90` / `90`, a semicircle).
      Degrees, `0` points up, angles grow clockwise. The value maps linearly:
      `angle = start + (value - min) / (max - min) * (end - start)`.
    * `min` / `max` (default `0` / `100`). Values outside are clamped.
    * `thickness` - band thickness as a share of the radius (default `"18%"`).
    * `track` - `%{show: true, background: "#f2f2f2"}`, the empty band.
    * `bands` - `[%{from: 0, to: 60, color: "#00E396"}, ...]`. When given,
      the coloured bands replace the track and the value arc; the needle
      shows the value. Bands are clipped to `min..max`.
    * `band_gap` - pixels between neighbouring bands (default `2`). The gap
      is constant-width (edges inset parallel to the radial line, see
      `EexCharts.Charts.Sector`).
    * `value_arc` - `%{show: true, color: nil}`: without bands, the band is
      filled from `min` to the value in `color` (default: first palette
      colour).
    * `ticks` - `%{show: true, amount: 10, length: 8, width: 1, color: nil,
      offset: 4, minor: %{amount: 0, length: 4}}`. `amount` major intervals
      (`amount + 1` marks), `minor.amount` extra marks between two majors.
      Ticks point inward from just inside the band.
    * `tick_labels` - `%{show: true, font_size: 11, color: nil, offset: 4,
      formatter: nil}`, one label per major tick, inside the ticks.
    * `needle` - `%{show: true, length: "90%", width: 8, color: nil}`. Length
      is a share of the outer radius, width is the base width in px.
    * `hub` - `%{radius: 8, color: nil, stroke_color: "#fff", stroke_width: 2}`,
      the circle at the needle's pivot (colour defaults to the needle's).
    * `data_labels` - `%{show: true, value: %{font_size: 24, font_weight: 600,
      color: nil, offset_y: 0, formatter: nil}, name: %{show: true,
      font_size: 13, font_weight: 400, color: nil, offset_y: 0}}`. The value
      (and the series name below it) sit under the hub.
    * `offset_x` / `offset_y` (default `0`).

  `nil` colours fall back to `chart.fore_color`, so the dial follows dark
  mode. The radius is fitted to the bounding box of the swept arc plus the
  label block under the hub, so a semicircle uses the full width.

  No legend and no tooltip: the dial shows its one value itself.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, Renderer}
  alias EexCharts.Charts.Sector

  @padding 8

  @doc "Renders the complete gauge container."
  def render_chart(cfg, params, id) do
    g = cfg.plot_options.gauge
    {name, value} = series_value(params)

    w = if is_number(cfg.chart.width), do: cfg.chart.width, else: 600
    h = if is_number(cfg.chart.height), do: cfg.chart.height, else: 350
    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0

    geo = g |> geometry(0, title_h, w, h - title_h, name) |> Map.put(:value, value)

    l = %Layout{
      w: w,
      h: h,
      grid_x: 0,
      grid_y: title_h,
      grid_w: w,
      grid_h: h - title_h,
      title_h: title_h
    }

    svg =
      Renderer.svg_open(cfg, l, id, [
        Renderer.background(cfg, l),
        Renderer.title(cfg, l),
        el("g", %{class: "eexcharts-gauge"}, [
          bands_or_track(cfg, geo),
          ticks(cfg, geo),
          needle(cfg, geo, value),
          value_labels(cfg, geo, name, value)
        ])
      ])

    Renderer.container(cfg, params, id, svg, [])
  end

  @doc """
  Needle angle (degrees, 0 = up, clockwise) for `value` under the gauge
  options `g`: linear in `min..max`, clamped to the sweep.
  """
  def value_angle(g, value) do
    span = g.max - g.min
    frac = if span == 0, do: 0.0, else: (value - g.min) / span
    frac = frac |> max(0.0) |> min(1.0)
    g.start_angle + frac * sweep(g)
  end

  # Signed sweep, clamped just under a full turn so arcs stay drawable.
  defp sweep(g) do
    s = g.end_angle - g.start_angle
    sign = if s < 0, do: -1, else: 1
    sign * min(abs(s), 359.9)
  end

  # ── Geometry ───────────────────────────────────────────────────────────────

  @doc false
  def geometry(g, x0, y0, box_w, box_h, name) do
    {xmin, xmax, ymin, ymax} = arc_extent(g.start_angle, g.start_angle + sweep(g))
    below = label_block(g, name)

    avail_w = max(box_w - 2 * @padding, 1)
    avail_h = max(box_h - 2 * @padding, 1)

    r_w = avail_w / (xmax - xmin)

    r_h1 = avail_h / (ymax - ymin)

    r_h =
      cond do
        r_h1 * ymax >= below -> r_h1
        ymin < 0 -> max((avail_h - below) / -ymin, 1)
        true -> r_h1
      end

    r = r_w |> min(r_h) |> max(1.0)

    content_h = r * -ymin + max(r * ymax, below)
    cx = x0 + @padding + (avail_w - r * (xmax - xmin)) / 2 + r * -xmin + g.offset_x
    cy = y0 + @padding + (avail_h - content_h) / 2 + r * -ymin + g.offset_y

    r_in = r * (1 - pct(g.thickness) / 100)
    %{cx: cx, cy: cy, r: r, r_in: r_in, g: g}
  end

  # Bounding box (unit radius, y down) of the arc from `a0` to `a1` plus the
  # centre: the end points and every axis direction crossed on the way.
  defp arc_extent(a0, a1) do
    {lo, hi} = {min(a0, a1), max(a0, a1)}

    cardinals =
      for k <- floor(lo / 90)..ceil(hi / 90), a = k * 90, a >= lo and a <= hi, do: a

    pts = [{0.0, 0.0} | Enum.map([lo, hi | cardinals], &Sector.pt(1, &1))]
    xs = Enum.map(pts, &elem(&1, 0))
    ys = Enum.map(pts, &elem(&1, 1))
    {Enum.min(xs), max(Enum.max(xs), Enum.min(xs) + 1.0e-6), Enum.min(ys), Enum.max(ys)}
  end

  # Height the hub + value label + name label need below the centre.
  defp label_block(g, name) do
    hub = if g.needle.show, do: g.hub.radius, else: 0
    dl = g.data_labels

    if dl.show do
      name_h = if dl.name.show and name, do: dl.name.font_size + 4, else: 0
      hub + 8 + dl.value.font_size + name_h + 4
    else
      hub + 4
    end
  end

  # ── Bands / track / value arc ───────────────────────────────────────────────

  defp bands_or_track(cfg, %{g: %{bands: [_ | _] = bands}} = geo) do
    g = geo.g
    {lo, hi} = {min(g.min, g.max), max(g.min, g.max)}

    paths =
      bands
      |> Enum.with_index()
      |> Enum.map(fn {b, i} ->
        from = b.from |> max(lo) |> min(hi)
        to = b.to |> max(lo) |> min(hi)

        el("path", %{
          class: "eexcharts-gauge-band",
          d: sector(geo, value_angle(g, from), value_angle(g, to), g.band_gap / 2),
          fill: b[:color] || Config.color_at(cfg, i),
          fill_opacity: cfg.fill.opacity
        })
      end)
      |> Enum.reject(&match?({:el, _, %{d: []}, _}, &1))

    el("g", %{class: "eexcharts-gauge-bands"}, paths)
  end

  defp bands_or_track(cfg, geo) do
    g = geo.g

    track =
      if g.track.show do
        el("path", %{
          class: "eexcharts-gauge-track",
          d: sector(geo, g.start_angle, g.start_angle + sweep(g), 0),
          fill: g.track.background
        })
      else
        []
      end

    value_arc =
      if g.value_arc.show do
        case sector(geo, g.start_angle, value_angle(g, geo.value), 0) do
          [] ->
            []

          d ->
            el("path", %{
              class: "eexcharts-gauge-value",
              d: d,
              fill: g.value_arc.color || Config.color_at(cfg, 0),
              fill_opacity: cfg.fill.opacity
            })
        end
      else
        []
      end

    [track, value_arc]
  end

  defp sector(geo, a, b, inset) do
    {a0, a1} = {min(a, b), max(a, b)}

    geo.r
    |> Sector.build(geo.r_in, a0, a1 - a0, inset, 0)
    |> Sector.path(geo.cx, geo.cy)
  end

  # ── Ticks and tick labels ────────────────────────────────────────────────────

  @doc false
  def tick_values(g) do
    n = max(trunc(g.ticks.amount), 1)
    step = (g.max - g.min) / n
    for i <- 0..n, do: clean(g.min + i * step)
  end

  defp ticks(cfg, geo) do
    g = geo.g
    t = g.ticks
    fore = cfg.chart.fore_color
    majors = tick_values(g)
    r0 = geo.r_in - t.offset

    marks =
      if t.show do
        minor_n = max(trunc(t.minor.amount), 0)

        minors =
          for [a, b] <- Enum.chunk_every(majors, 2, 1, :discard),
              k <- 1..minor_n//1,
              do: a + (b - a) * k / (minor_n + 1)

        Enum.map(majors, &tick_line(geo, r0, t.length, value_angle(g, &1), t, fore)) ++
          Enum.map(minors, &tick_line(geo, r0, t.minor.length, value_angle(g, &1), t, fore))
      else
        []
      end

    tl = g.tick_labels

    labels =
      if tl.show do
        reach = if t.show, do: t.length, else: 0
        lr = r0 - reach - tl.offset - tl.font_size * 0.9

        Enum.map(majors, fn v ->
          {x, y} = polar(geo, max(lr, 0), value_angle(g, v))

          el(
            "text",
            %{
              class: "eexcharts-gauge-tick-label",
              x: x,
              y: y,
              text_anchor: "middle",
              dominant_baseline: "central",
              fill: tl.color || fore,
              font_size: tl.font_size
            },
            esc(format(tl.formatter, v))
          )
        end)
      else
        []
      end

    el("g", %{class: "eexcharts-gauge-ticks"}, [marks, labels])
  end

  defp tick_line(geo, r0, len, angle, t, fore) do
    {x1, y1} = polar(geo, r0, angle)
    {x2, y2} = polar(geo, max(r0 - len, 0), angle)

    el("line", %{
      class: "eexcharts-gauge-tick",
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      stroke: t.color || fore,
      stroke_width: t.width
    })
  end

  # ── Needle and hub ────────────────────────────────────────────────────────────

  defp needle(cfg, geo, value) do
    n = geo.g.needle
    hub = geo.g.hub

    if n.show do
      color = n.color || cfg.chart.fore_color
      angle = value_angle(geo.g, value)
      len = geo.r * pct(n.length) / 100
      {tx, ty} = polar(geo, len, angle)
      {b1x, b1y} = polar(geo, n.width / 2, angle - 90)
      {b2x, b2y} = polar(geo, n.width / 2, angle + 90)

      [
        el("path", %{
          class: "eexcharts-gauge-needle",
          d: [move(b1x, b1y), line(tx, ty), line(b2x, b2y), close()],
          fill: color,
          stroke: color,
          stroke_width: 1,
          stroke_linejoin: "round",
          data_angle: angle
        }),
        el("circle", %{
          class: "eexcharts-gauge-hub",
          cx: geo.cx,
          cy: geo.cy,
          r: hub.radius,
          fill: hub.color || color,
          stroke: hub.stroke_color,
          stroke_width: hub.stroke_width
        })
      ]
    else
      []
    end
  end

  # ── Centre labels ────────────────────────────────────────────────────────────

  defp value_labels(cfg, geo, name, value) do
    dl = geo.g.data_labels
    fore = cfg.chart.fore_color

    if dl.show do
      hub = if geo.g.needle.show, do: geo.g.hub.radius, else: 0
      vy = geo.cy + hub + 8 + dl.value.font_size / 2 + dl.value.offset_y

      value_el =
        el(
          "text",
          %{
            class: "eexcharts-gauge-value-label",
            x: geo.cx,
            y: vy,
            text_anchor: "middle",
            dominant_baseline: "central",
            fill: dl.value.color || fore,
            font_size: dl.value.font_size,
            font_weight: dl.value.font_weight
          },
          esc(format(dl.value.formatter, value))
        )

      name_el =
        if dl.name.show and name do
          el(
            "text",
            %{
              class: "eexcharts-gauge-name-label",
              x: geo.cx,
              y: vy + dl.value.font_size / 2 + 4 + dl.name.font_size / 2 + dl.name.offset_y,
              text_anchor: "middle",
              dominant_baseline: "central",
              fill: dl.name.color || fore,
              font_size: dl.name.font_size,
              font_weight: dl.name.font_weight
            },
            esc(name)
          )
        else
          []
        end

      el("g", %{class: "eexcharts-datalabels"}, [value_el, name_el])
    else
      []
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp series_value(params) do
    {name, value} =
      case params[:series] do
        v when is_number(v) -> {nil, v}
        [%{} = s | _] -> {s[:name], first_number(s[:data])}
        [v | _] when is_number(v) -> {nil, v}
        _ -> {nil, 0}
      end

    name =
      case params[:labels] do
        [label | _] when not is_nil(label) -> to_string(label)
        _ -> name && to_string(name)
      end

    {name, value}
  end

  defp first_number(data) when is_list(data), do: Enum.find(data, 0, &is_number/1)
  defp first_number(v) when is_number(v), do: v
  defp first_number(_), do: 0

  defp format(f, v) when is_function(f, 1), do: to_string(f.(v))
  defp format(_, v), do: fmt_value(v)

  defp clean(v) when is_float(v) do
    r = Float.round(v, 10)
    if r == trunc(r), do: trunc(r), else: r
  end

  defp polar(geo, r, angle) do
    {x, y} = Sector.pt(r, angle)
    {geo.cx + x, geo.cy + y}
  end

  defp pct(v) when is_binary(v) do
    case Float.parse(v) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp pct(v) when is_number(v), do: v
end
