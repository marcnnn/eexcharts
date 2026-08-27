defmodule EexCharts.Charts.RadialBar do
  @moduledoc """
  Radial bar (circular gauge) chart, ported from ApexCharts `src/charts/Radial.js`.

  Each series value is a percentage (0–100) rendered as a stroked arc sweeping
  from `plot_options.radial_bar.start_angle` to
  `start + value/100 * total_angle`, over a gray track arc. Multiple series
  become concentric rings. A hollow center (`hollow.size`% of the radius) hosts
  the center data labels.

  Owns its full SVG assembly: `render_chart/3` returns the complete container
  (svg + tooltips), like `EexCharts.Renderer.render/1` does for cartesian
  types.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, Legend, Renderer}

  @doc "Renders the complete radial bar chart container."
  def render_chart(cfg, params, id) do
    all_rings = rings(params)
    hidden = Renderer.hidden_set(params)
    rings = Enum.reject(all_rings, &MapSet.member?(hidden, &1.index))

    names = Enum.map(all_rings, & &1.name)

    w = if is_number(cfg.chart.width), do: cfg.chart.width, else: 600
    h = if is_number(cfg.chart.height), do: cfg.chart.height, else: 350

    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    legend = Legend.measure(cfg, names, w, h)

    {box_w, box_h} =
      case legend.position do
        :right -> {w - legend.w, h - title_h}
        pos when pos in [:bottom, :top] -> {w, h - title_h - legend.h}
        _ -> {w, h - title_h}
      end

    geo = geometry(cfg, all_rings, box_w, box_h)

    cy_shift = if legend.position == :top, do: title_h + legend.h, else: title_h
    geo = %{geo | cy: geo.cy + cy_shift}

    l = %Layout{
      w: w,
      h: h,
      grid_x: 0,
      grid_y: title_h,
      grid_w: box_w,
      grid_h: box_h,
      legend: legend,
      title_h: title_h
    }

    svg =
      Renderer.svg_open(cfg, l, id, [
        Renderer.background(cfg, l),
        Renderer.title(cfg, l),
        tracks(cfg, geo),
        hollow(cfg, geo),
        arcs(cfg, geo, rings, params),
        center_labels(cfg, geo, rings),
        Legend.render(legend, cfg, l,
          hidden: hidden,
          on_click: params[:on_legend_click]
        )
      ])

    Renderer.container(cfg, params, id, svg, tooltips(cfg, geo, rings))
  end

  # ── Geometry ───────────────────────────────────────────────────────────────

  # Ports the radius / stroke-width bookkeeping from Radial.js. `rings` is the
  # full (unfiltered) ring list so the stroke width and concentric spacing stay
  # stable when a ring is hidden via the legend.
  defp geometry(cfg, rings, box_w, box_h) do
    rb = cfg.plot_options.radial_bar
    n = max(length(rings), 1)

    default_size = min(box_w, box_h)
    cx = box_w / 2 + rb.offset_x
    cy = box_h / 2 + rb.offset_y

    size = default_size / 2.05 - cfg.stroke.width
    margin = rb.track.margin

    # Ring band thickness (Radial.getStrokeWidth).
    stroke_w = size * (100 - parse_pct(rb.hollow.size)) / 100 / (n + 1) - margin

    # Radius of ring i (0-indexed). Both tracks and value arcs share this.
    radius_at = fn i -> size - stroke_w / 2 - (i + 1) * (stroke_w + margin) end

    track_sw = parse_pct(rb.track.stroke_width)

    hollow_size =
      size - stroke_w * n - margin * n - stroke_w * track_sw / 100 / 2

    hollow_radius = hollow_size - parse_pct(rb.hollow.margin)

    start_angle = rb.start_angle
    total_angle = abs(rb.end_angle - rb.start_angle)

    %{
      cx: cx,
      cy: cy,
      size: size,
      stroke_w: stroke_w,
      track_sw: track_sw,
      radius_at: radius_at,
      hollow_radius: hollow_radius,
      start_angle: start_angle,
      total_angle: total_angle,
      count: n
    }
  end

  # ── Tracks (gray background arcs) ────────────────────────────────────────────

  defp tracks(cfg, geo) do
    rb = cfg.plot_options.radial_bar

    if rb.track.show do
      # Track spans the whole angular range (endAngle clamped just below full).
      track_end =
        if geo.total_angle >= 360,
          do: geo.start_angle + geo.total_angle - 0.1,
          else: geo.start_angle + geo.total_angle

      arcs =
        Enum.map(0..(geo.count - 1), fn i ->
          el("path", %{
            class: "eexcharts-radialbar-track",
            d: arc_path(geo.cx, geo.cy, geo.radius_at.(i), geo.start_angle, track_end),
            fill: "none",
            stroke: track_background(rb.track.background, i),
            stroke_width: geo.stroke_w * geo.track_sw / 100,
            stroke_opacity: rb.track.opacity,
            stroke_linecap: cfg.stroke.line_cap
          })
        end)

      el("g", %{class: "eexcharts-tracks"}, arcs)
    else
      []
    end
  end

  defp track_background(bg, i) when is_list(bg), do: Enum.at(bg, rem(i, length(bg)))
  defp track_background(bg, _i), do: bg

  # ── Value arcs ──────────────────────────────────────────────────────────────

  defp arcs(cfg, geo, rings, params) do
    on_click = params[:on_click]

    arcs =
      Enum.map(rings, fn r ->
        value = r.value |> max(0) |> min(100)
        angle = geo.total_angle * value / 100
        # Clamp a full sweep so the arc endpoints don't coincide.
        angle = if geo.total_angle >= 360, do: min(angle, geo.total_angle - 0.01), else: angle
        end_angle = geo.start_angle + angle

        attrs = %{
          class: "eexcharts-radialbar-arc",
          data_j: r.index,
          d: arc_path(geo.cx, geo.cy, geo.radius_at.(r.index), geo.start_angle, end_angle),
          fill: "none",
          stroke: Config.color_at(cfg, r.index),
          stroke_width: geo.stroke_w,
          stroke_opacity: cfg.fill.opacity,
          stroke_linecap: cfg.stroke.line_cap
        }

        attrs =
          if on_click do
            Map.merge(attrs, %{
              "phx-click" => on_click,
              "phx-value-index" => r.index,
              "phx-value-series" => r.index,
              cursor: "pointer"
            })
          else
            attrs
          end

        el("path", attrs)
      end)

    el("g", %{class: "eexcharts-radialbar-series"}, arcs)
  end

  # ── Hollow center ─────────────────────────────────────────────────────────────

  defp hollow(cfg, geo) do
    bg = cfg.plot_options.radial_bar.hollow.background

    if geo.hollow_radius > 0 and bg not in [nil, "", "transparent"] do
      el("circle", %{
        class: "eexcharts-radialbar-hollow",
        cx: geo.cx,
        cy: geo.cy,
        r: geo.hollow_radius,
        fill: bg
      })
    else
      []
    end
  end

  # ── Center data labels ────────────────────────────────────────────────────────

  defp center_labels(cfg, geo, rings) do
    dl = cfg.plot_options.radial_bar.data_labels
    fore = cfg.chart.fore_color

    cond do
      not dl.show ->
        []

      dl.total.show ->
        total = rings |> Enum.map(& &1.value) |> Enum.sum()
        avg = if rings == [], do: 0, else: total / length(rings)
        value = total_text(dl.total, avg)
        render_center(cfg, geo, dl, dl.total.label, value, dl.total.color || fore, fore)

      # Single visible series: name + its value.
      match?([_], rings) ->
        [r] = rings
        value = value_text(dl.value, r.value)

        render_center(
          cfg,
          geo,
          dl,
          r.name,
          value,
          dl.name.color || Config.color_at(cfg, r.index),
          fore
        )

      true ->
        []
    end
  end

  defp render_center(_cfg, geo, dl, name, value, name_color, fore) do
    y = geo.cy

    name_el =
      if dl.name.show do
        el(
          "text",
          %{
            x: geo.cx,
            y: y + dl.name.offset_y,
            text_anchor: "middle",
            dominant_baseline: "central",
            fill: name_color,
            font_size: dl.name.font_size,
            font_weight: dl.name.font_weight,
            class: "eexcharts-radialbar-label"
          },
          esc(name)
        )
      else
        []
      end

    value_el =
      if dl.value.show do
        offset = if dl.name.show, do: dl.value.offset_y + 16, else: dl.value.offset_y

        el(
          "text",
          %{
            x: geo.cx,
            y: y + offset,
            text_anchor: "middle",
            dominant_baseline: "central",
            fill: dl.value.color || fore,
            font_size: dl.value.font_size,
            font_weight: dl.value.font_weight,
            class: "eexcharts-radialbar-value"
          },
          esc(value)
        )
      else
        []
      end

    el("g", %{class: "eexcharts-datalabels"}, [name_el, value_el])
  end

  defp value_text(value_cfg, v) do
    case value_cfg.formatter do
      f when is_function(f, 1) -> to_string(f.(v))
      _ -> "#{fmt_value(v)}%"
    end
  end

  defp total_text(total_cfg, avg) do
    case total_cfg.formatter do
      f when is_function(f, 1) -> to_string(f.(avg))
      _ -> "#{fmt_value(round_number(avg))}%"
    end
  end

  # ── Tooltips ─────────────────────────────────────────────────────────────────

  defp tooltips(cfg, _geo, rings) do
    if cfg.tooltip.enabled do
      tips =
        Enum.map(rings, fn r ->
          el("div", %{class: "eexcharts-tip", data_j: r.index, hidden: true}, [
            Renderer.tooltip_row(
              Config.color_at(cfg, r.index),
              r.name,
              "#{fmt_value(r.value)}%"
            )
          ])
        end)

      Renderer.tooltip_container(cfg, tips)
    else
      []
    end
  end

  # ── Series extraction ────────────────────────────────────────────────────────

  # Each ring is one percentage. Accepts a bare list of numbers or a list of
  # `%{name, data}` series (first datum used). Labels (params[:labels]) override
  # the ring names.
  defp rings(params) do
    labels = params[:labels]

    values =
      case params[:series] do
        [%{} | _] = list ->
          Enum.map(list, fn s -> {s[:name], first_number(s[:data])} end)

        list when is_list(list) ->
          Enum.map(list, fn v -> {nil, if(is_number(v), do: v, else: 0)} end)

        _ ->
          []
      end

    values
    |> Enum.with_index()
    |> Enum.map(fn {{name, value}, i} ->
      label = label_at(labels, i) || name || "series-#{i + 1}"
      %{name: to_string(label), value: value, index: i}
    end)
  end

  defp first_number(data) when is_list(data) do
    case Enum.find(data, &is_number/1) do
      nil -> 0
      v -> v
    end
  end

  defp first_number(v) when is_number(v), do: v
  defp first_number(_), do: 0

  defp label_at(nil, _i), do: nil
  defp label_at(labels, i) when is_list(labels), do: Enum.at(labels, i)

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp arc_path(cx, cy, r, start_deg, end_deg) do
    angle = end_deg - start_deg
    large = if abs(angle) > 180, do: 1, else: 0
    sweep = if angle >= 0, do: 1, else: 0
    {x1, y1} = polar(cx, cy, r, start_deg)
    {x2, y2} = polar(cx, cy, r, end_deg)
    [move(x1, y1), arc(r, r, 0, large, sweep, x2, y2)]
  end

  defp polar(cx, cy, r, deg) do
    rad = :math.pi() * (deg - 90) / 180
    {cx + r * :math.cos(rad), cy + r * :math.sin(rad)}
  end

  defp parse_pct(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_pct(v) when is_number(v), do: v

  defp round_number(v) when is_float(v), do: Float.round(v, 2)
  defp round_number(v), do: v
end
