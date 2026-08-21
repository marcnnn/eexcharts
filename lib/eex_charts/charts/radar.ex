defmodule EexCharts.Charts.Radar do
  @moduledoc """
  Radar (spider) chart, ported from ApexCharts `src/charts/Radar.js`.

  `N` categories become `N` spokes radiating from the center; the value scale
  (`EexCharts.Scale.nice_scale`) maps each value to a radius, drawn as a
  concentric polygon grid. Each series is a closed polygon (stroke + faint
  fill) with a marker at every vertex.

  Owns its full SVG assembly: `render_chart/3` returns the complete container
  (svg + tooltips).
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, Legend, Renderer, Scale}

  @doc "Renders the complete radar chart container."
  def render_chart(cfg, params, id) do
    all_series = Renderer.normalize_series(params[:series])
    hidden = Renderer.hidden_set(params)
    series = Enum.reject(all_series, &MapSet.member?(hidden, &1.index))

    names = Enum.map(all_series, & &1.name)

    categories =
      case params[:categories] || cfg.xaxis.categories do
        [] -> nil
        cats -> Enum.map(cats, &to_string/1)
      end

    n =
      [
        if(categories, do: length(categories), else: 0)
        | Enum.map(series, &length(&1.data))
      ]
      |> Enum.max()
      |> max(1)

    categories = categories || Enum.map(1..n, &to_string/1)

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

    geo = geometry(cfg, series, categories, n, box_w, box_h)

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
        grid_polygons(cfg, geo),
        category_labels(cfg, geo),
        series_polygons(cfg, geo, series, params),
        markers(cfg, geo, series, params),
        Legend.render(legend, cfg, l,
          hidden: hidden,
          on_click: params[:on_legend_click]
        )
      ])

    Renderer.container(cfg, params, id, svg, tooltips(cfg, geo, series, categories))
  end

  # ── Geometry ───────────────────────────────────────────────────────────────

  defp geometry(cfg, series, categories, n, box_w, box_h) do
    radar = cfg.plot_options.radar
    stroke_w = if cfg.stroke.show, do: cfg.stroke.width, else: 0

    default_size = min(box_w, box_h)

    # ApexCharts (Radar.js) subtracts the drop-shadow blur here unconditionally,
    # even with the shadow disabled — matching it keeps the polygon radius
    # identical.
    blur = 4
    size = default_size / 2.1 - stroke_w - blur

    # Reserve room for perimeter category labels (ApexCharts xAxisLabelsWidth).
    size =
      if cfg.xaxis.labels.show do
        max_label_w =
          categories
          |> Enum.map(&Layout.text_width(&1, cfg.xaxis.labels.style.font_size, Layout.metrics(cfg)))
          |> Enum.max(fn -> 0 end)

        size - max_label_w / 1.75
      else
        size
      end

    size = if is_number(radar.size), do: radar.size, else: max(size, 10)

    cx = box_w / 2 + radar.offset_x
    cy = box_h / 2 + radar.offset_y

    {min_v, max_v} = data_range(series)
    axis = Config.yaxis(cfg)

    scale =
      Scale.nice_scale(min_v, max_v,
        min: axis.min,
        max: axis.max,
        tick_amount: axis.tick_amount,
        step_size: axis.step_size
      )

    range = scale.nice_max - scale.nice_min
    range = if range == 0, do: 1, else: range

    dis_angle = 2 * :math.pi() / n

    %{
      cx: cx,
      cy: cy,
      size: size,
      n: n,
      categories: categories,
      dis_angle: dis_angle,
      scale: scale,
      nice_min: scale.nice_min,
      range: range
    }
  end

  defp data_range(series) do
    values = series |> Enum.flat_map(& &1.data) |> Enum.filter(&is_number/1)

    case values do
      [] -> {0, 1}
      _ -> Enum.min_max(values)
    end
  end

  # Vertex position for value `v` at spoke `j` (angle 0 points up).
  defp point(geo, v, j) do
    radius = (v - geo.nice_min) / geo.range * geo.size
    angle = j * geo.dis_angle
    {geo.cx + radius * :math.sin(angle), geo.cy - radius * :math.cos(angle)}
  end

  # Vertex position on the perimeter for spoke `j`.
  defp spoke_point(geo, radius, j) do
    angle = j * geo.dis_angle
    {geo.cx + radius * :math.sin(angle), geo.cy - radius * :math.cos(angle)}
  end

  # ── Grid ─────────────────────────────────────────────────────────────────────

  defp grid_polygons(cfg, geo) do
    poly = cfg.plot_options.radar.polygons
    layers = length(geo.scale.ticks)

    if layers > 1 do
      layer_dis = geo.size / (layers - 1)
      fill_colors = poly.fill.colors

      # Concentric polygons from the outermost (radius = size) inward.
      rings =
        Enum.map(0..(layers - 1), fn k ->
          radius = geo.size - layer_dis * k

          if radius > 0 do
            points =
              0..(geo.n - 1)
              |> Enum.map(fn j -> spoke_point(geo, radius, j) end)
              |> Enum.map_join(" ", fn {x, y} -> "#{fmt(x)},#{fmt(y)}" end)

            el("polygon", %{
              points: points,
              fill: ring_fill(fill_colors, k),
              stroke: poly.stroke_colors,
              stroke_width: poly.stroke_width
            })
          else
            []
          end
        end)

      # Spokes from each outer vertex to the center.
      spokes =
        Enum.map(0..(geo.n - 1), fn j ->
          {x, y} = spoke_point(geo, geo.size, j)

          el("line", %{
            x1: x,
            y1: y,
            x2: geo.cx,
            y2: geo.cy,
            stroke: connector_color(poly.connector_colors, j),
            stroke_width: poly.stroke_width
          })
        end)

      axis = Config.yaxis(cfg)

      y_labels =
        if axis.show and axis.labels.show do
          y_texts = Enum.reverse(geo.scale.ticks)
          color = y_label_color(axis.labels.style.colors, cfg.chart.fore_color)

          Enum.map(0..(layers - 1), fn k ->
            {x, y} = spoke_point(geo, geo.size - layer_dis * k, 0)
            x = x + axis.labels.offset_x
            y = y + axis.labels.offset_y
            text = Layout.format_y_label(cfg, axis, Enum.at(y_texts, k), k)

            if text == "" do
              []
            else
              el(
                "text",
                %{
                  class: "eexcharts-yaxis-label",
                  x: x,
                  y: y,
                  text_anchor: "middle",
                  dominant_baseline: "central",
                  fill: color,
                  font_size: axis.labels.style.font_size
                },
                esc(text)
              )
            end
          end)
        else
          []
        end

      el("g", %{class: "eexcharts-radar-grid"}, [rings, spokes, y_labels])
    else
      []
    end
  end

  defp ring_fill(nil, _k), do: "none"
  defp ring_fill(colors, k) when is_list(colors), do: Enum.at(colors, rem(k, length(colors)))
  defp ring_fill(color, _k), do: color

  defp connector_color(colors, j) when is_list(colors),
    do: Enum.at(colors, rem(j, length(colors)))

  defp connector_color(color, _j), do: color

  # ── Category (perimeter) labels ────────────────────────────────────────────────

  defp category_labels(cfg, geo) do
    if cfg.xaxis.labels.show do
      style = cfg.xaxis.labels.style
      color = label_color(style.colors)

      labels =
        categories_with_index(geo)
        |> Enum.map(fn {label, j} ->
          {x, y} = spoke_point(geo, geo.size, j)
          {anchor, nx, ny} = text_pos(x - geo.cx, y - geo.cy, geo.size)

          lx = geo.cx + nx
          ly = geo.cy + ny + label_offset_y(cfg, j)

          el(
            "text",
            %{
              x: lx,
              y: ly,
              text_anchor: anchor,
              dominant_baseline: "central",
              fill: color,
              font_size: style.font_size,
              font_weight: style.font_weight,
              class: "eexcharts-xaxis-label",
              data_index: j
            },
            label_content(format_x_label(cfg, label, j), lx)
          )
        end)

      el("g", %{class: "eexcharts-xaxis-labels"}, labels)
    else
      []
    end
  end

  # A formatter may return a list of lines; each extra line becomes a `tspan`
  # one line-height below the previous, anchored at the same x.
  defp label_content(lines, x) when is_list(lines) do
    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, i} ->
      el("tspan", %{x: x, dy: if(i == 0, do: nil, else: "1.2em")}, esc(to_string(line)))
    end)
  end

  defp label_content(text, _x), do: esc(text)

  # `xaxis.labels.offset_y` may be a function of the spoke index, so a single
  # label (e.g. the bottom vertex) can be nudged clear of the plot.
  defp label_offset_y(cfg, j) do
    case cfg.xaxis.labels.offset_y do
      f when is_function(f, 1) -> f.(j)
      n when is_number(n) -> n
      _ -> 0
    end
  end

  # Ported from Radar.getTextPos: nudge labels away from the perimeter.
  defp text_pos(dx, dy, size) do
    limit = 10

    {anchor, nx} =
      cond do
        abs(dx) < limit -> {"middle", dx}
        dx > 0 -> {"start", dx + 10}
        true -> {"end", dx - 10}
      end

    ny =
      cond do
        abs(dy) < size - limit -> dy
        dy < 0 -> dy - 10
        true -> dy + 10
      end

    {anchor, nx, ny}
  end

  defp categories_with_index(geo) do
    geo.categories
    |> Enum.with_index()
    |> Enum.filter(fn {_c, j} -> j < geo.n end)
  end

  defp format_x_label(cfg, label, j) do
    case cfg.xaxis.labels.formatter do
      f when is_function(f, 2) -> f.(label, j)
      f when is_function(f, 1) -> to_string(f.(label))
      _ -> label
    end
  end

  defp label_color([c | _]) when is_binary(c), do: c
  defp label_color(c) when is_binary(c), do: c
  defp label_color(_), do: "#a8a8a8"

  defp y_label_color([c | _], _fore) when is_binary(c), do: c
  defp y_label_color(c, _fore) when is_binary(c), do: c
  defp y_label_color(_, fore), do: fore

  # ── Series polygons ────────────────────────────────────────────────────────────

  defp series_polygons(cfg, geo, series, params) do
    on_click = params[:on_click]

    polys =
      Enum.map(series, fn s ->
        color = Config.color_at(cfg, s.index)
        pts = vertices(geo, s)

        d = polygon_path(pts)

        attrs = %{
          class: "eexcharts-radar-area",
          data_series: s.index,
          d: d,
          fill: color,
          fill_opacity: cfg.fill.opacity,
          stroke: color,
          stroke_width: cfg.stroke.width,
          # ApexCharts leaves the SVG default (miter) on radar polygons; with a
          # thick stroke a round join visibly pulls every vertex in.
          stroke_linecap: cfg.stroke.line_cap
        }

        attrs =
          if on_click do
            Map.merge(attrs, %{"phx-value-series" => s.index})
          else
            attrs
          end

        el("path", attrs)
      end)

    el("g", %{class: "eexcharts-radar-series"}, polys)
  end

  defp vertices(geo, s) do
    0..(geo.n - 1)
    |> Enum.map(fn j ->
      v = Enum.at(s.data, j)
      if is_number(v), do: point(geo, v, j), else: nil
    end)
  end

  defp polygon_path(pts) do
    coords = Enum.reject(pts, &is_nil/1)

    case coords do
      [] ->
        ""

      [{x0, y0} | rest] ->
        [move(x0, y0), Enum.map(rest, fn {x, y} -> line(x, y) end), " Z"]
    end
  end

  # ── Markers ────────────────────────────────────────────────────────────────────

  defp markers(cfg, geo, series, params) do
    on_click = params[:on_click]
    size = cfg.markers.size

    if size > 0 do
      dots =
        Enum.flat_map(series, fn s ->
          color = Config.color_at(cfg, s.index)

          geo
          |> markers_for(s)
          |> Enum.map(fn {x, y, j} ->
            attrs = %{
              class: "eexcharts-marker",
              data_j: j,
              cx: x,
              cy: y,
              r: size,
              fill: color,
              stroke: cfg.markers.stroke_colors,
              stroke_width: cfg.markers.stroke_width
            }

            attrs =
              if on_click do
                Map.merge(attrs, %{
                  "phx-click" => on_click,
                  "phx-value-index" => j,
                  "phx-value-series" => s.index,
                  cursor: "pointer"
                })
              else
                attrs
              end

            el("circle", attrs)
          end)
        end)

      el("g", %{class: "eexcharts-radar-markers"}, dots)
    else
      []
    end
  end

  defp markers_for(geo, s) do
    0..(geo.n - 1)
    |> Enum.map(fn j ->
      v = Enum.at(s.data, j)

      if is_number(v) do
        {x, y} = point(geo, v, j)
        {x, y, j}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  # ── Tooltips (one per category, all visible series) ──────────────────────────────

  defp tooltips(cfg, _geo, series, categories) do
    if cfg.tooltip.enabled do
      n = categories |> length()

      tips =
        Enum.map(0..(max(n, 1) - 1), fn j ->
          title = Enum.at(categories, j, to_string(j + 1))

          rows =
            Enum.map(series, fn s ->
              v = Enum.at(s.data, j)

              if is_number(v) do
                Renderer.tooltip_row(
                  Config.color_at(cfg, s.index),
                  s.name,
                  Renderer.format_tooltip_y(cfg, v)
                )
              else
                []
              end
            end)

          el("div", %{class: "eexcharts-tip", data_j: j, hidden: true}, [
            el(
              "div",
              %{class: "eexcharts-tip-title"},
              esc(Renderer.format_tooltip_x(cfg, title))
            ),
            rows
          ])
        end)

      Renderer.tooltip_container(cfg, tips)
    else
      []
    end
  end
end
