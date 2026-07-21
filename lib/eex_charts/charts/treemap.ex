defmodule EexCharts.Charts.Treemap do
  @moduledoc """
  Treemap chart, ported from ApexCharts `src/charts/Treemap.js`, its
  `common/treemap/Helpers` color logic and the vendored squarified-treemap
  algorithm (`src/libs/Treemap-squared.js`, Bruls/Huizing/van Wijk 2000).

  Data shape: one series with `data: [%{x: label, y: value}, ...]`. Also
  accepts `{label, value}` tuples and plain numbers (labels then come from
  `params[:labels]`). With multiple series, each series gets a proportional
  band of the grid, squarified into cells inside it.

  Colors are either distributed (a color per cell, when
  `plot_options.treemap.distributed`) or per-series shaded by value intensity
  (`enable_shades`, `shade_intensity`). Owns its full SVG assembly:
  `render_chart/3` returns the complete container (svg + tooltips).
  """

  import EexCharts.SVG

  alias EexCharts.{Color, Config, Layout, Renderer}

  @doc "Renders the complete treemap container."
  def render_chart(cfg, params, id) do
    series = normalize(params)

    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    pad = cfg.grid.padding

    grid_x = pad.left
    grid_y = title_h + pad.top
    grid_w = max(w - grid_x - pad.right, 10)
    grid_h = max(h - grid_y - pad.bottom, 10)

    l = %Layout{
      w: w,
      h: h,
      grid_x: grid_x,
      grid_y: grid_y,
      grid_w: grid_w,
      grid_h: grid_h,
      title_h: 0
    }

    cells = build_cells(cfg, series, l)

    svg =
      Renderer.svg_open(cfg, l, id, [
        Renderer.background(cfg, l),
        Renderer.title(cfg, l),
        cell_rects(cfg, cells, params),
        data_labels(cfg, cells, series)
      ])

    Renderer.container(cfg, params, id, svg, tooltips(cfg, cells))
  end

  # ── Cell geometry ───────────────────────────────────────────────────────

  defp build_cells(cfg, series, l) do
    values = Enum.map(series, fn s -> Enum.map(s.points, &abs(&1.value)) end)

    if series == [] or Enum.all?(values, &(&1 == [])) do
      []
    else
      nodes = generate(values, l.grid_w, l.grid_h)

      # ApexCharts' `w.globals.hasNegs` is computed across ALL series.
      has_negs =
        series
        |> Enum.flat_map(fn s -> Enum.map(s.points, & &1.value) end)
        |> Enum.any?(&(&1 < 0))

      series
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, i} ->
        node = Enum.at(nodes, i) || []
        {color_fn, _} = cell_color_fns(cfg, s, i, has_negs)

        s.points
        |> Enum.with_index()
        |> Enum.map(fn {pt, j} ->
          [x1, y1, x2, y2] = Enum.at(node, j, [0, 0, 0, 0])

          %{
            series: s.index,
            j: j,
            x: l.grid_x + x1,
            y: l.grid_y + y1,
            w: x2 - x1,
            h: y2 - y1,
            value: pt.value,
            label: pt.label,
            color: color_fn.({pt.value, j}),
            name: s.name
          }
        end)
      end)
    end
  end

  # ── Colors (port of TreemapHelpers.getShadeColor) ─────────────────────────

  defp cell_color_fns(cfg, s, series_index, has_negs) do
    tm = cfg.plot_options.treemap
    distributed = tm.distributed
    enable_shades = tm.enable_shades
    si = tm.shade_intensity

    nums = Enum.map(s.points, & &1.value)

    {min_v, max_v} =
      case nums do
        [] -> {0, 0}
        _ -> Enum.min_max(nums)
      end

    total = abs(max_v) + abs(min_v)
    total = if total == 0, do: -1.0e-6, else: total

    color_fn = fn {v, j} ->
      base = if distributed, do: Config.color_at(cfg, j), else: Config.color_at(cfg, series_index)

      if enable_shades do
        percent = 100 * v / total

        shade_percent =
          if has_negs do
            if percent <= 0 do
              1 - (1 + percent / 100) * si
            else
              (1 - percent / 100) * si
            end
          else
            (1 - percent / 100) * (si * 1.25)
          end

        Color.shade(base, shade_percent)
      else
        base
      end
    end

    {color_fn, nil}
  end

  # ── Rects ─────────────────────────────────────────────────────────────────

  defp cell_rects(cfg, cells, params) do
    stroke = stroke_color(cfg)
    radius = cfg.plot_options.treemap.border_radius
    on_click = params[:on_click]

    rects =
      Enum.map(cells, fn c ->
        attrs = %{
          class: "eexcharts-treemap-rect",
          data_j: "#{c.series}-#{c.j}",
          x: c.x,
          y: c.y,
          width: max(c.w, 0),
          height: max(c.h, 0),
          rx: radius,
          fill: c.color,
          fill_opacity: cfg.fill.opacity,
          stroke: stroke,
          stroke_width: cfg.stroke.width
        }

        attrs =
          if on_click do
            Map.merge(attrs, %{
              "phx-click" => on_click,
              "phx-value-index" => c.j,
              "phx-value-series" => c.series,
              cursor: "pointer"
            })
          else
            attrs
          end

        el("rect", attrs)
      end)

    el("g", %{class: "eexcharts-treemap"}, rects)
  end

  # ── Data labels ─────────────────────────────────────────────────────────

  defp data_labels(cfg, cells, series) do
    if cfg.data_labels.enabled do
      style = cfg.data_labels.style
      color = data_label_color(cfg)
      avg = avg_label_size(series)

      labels =
        cells
        |> Enum.filter(&(&1.value != 0))
        |> Enum.flat_map(fn c ->
          font = font_size(c.w, c.h, avg, style.font_size)
          text = format_data_label(cfg, c.label)

          # Hide labels that would not fit inside the cell.
          if font >= 6 and Layout.text_width(text, font) <= c.w - 4 and font * 1.2 <= c.h do
            [
              el(
                "text",
                %{
                  x: c.x + c.w / 2 + cfg.data_labels.offset_x,
                  y: c.y + c.h / 2 + cfg.stroke.width / 2 + font / 3 + cfg.data_labels.offset_y,
                  text_anchor: "middle",
                  dominant_baseline: "central",
                  fill: color,
                  font_size: font,
                  font_weight: style.font_weight,
                  class: "eexcharts-datalabel"
                },
                esc(text)
              )
            ]
          else
            []
          end
        end)

      el("g", %{class: "eexcharts-datalabels"}, labels)
    else
      []
    end
  end

  # ApexCharts scales the font by average label length vs cell area.
  defp font_size(w, h, avg, max_font) do
    area = max(w, 0) * max(h, 0)
    if avg <= 0, do: max_font, else: min(:math.sqrt(area) / avg, max_font)
  end

  defp avg_label_size(series) do
    labels = Enum.flat_map(series, fn s -> Enum.map(s.points, &String.length(&1.label)) end)

    case labels do
      [] -> 1
      _ -> Enum.sum(labels) / length(labels)
    end
  end

  defp format_data_label(cfg, label) do
    case cfg.data_labels.formatter do
      f when is_function(f, 1) -> to_string(f.(label))
      _ -> to_string(label)
    end
  end

  defp data_label_color(cfg) do
    case cfg.data_labels.style.colors do
      [c | _] -> c
      c when is_binary(c) -> c
      _ -> "#fff"
    end
  end

  # ── Tooltips ──────────────────────────────────────────────────────────────

  defp tooltips(cfg, cells) do
    if cfg.tooltip.enabled do
      tips =
        Enum.map(cells, fn c ->
          el("div", %{class: "eexcharts-tip", data_j: "#{c.series}-#{c.j}", hidden: true}, [
            el("div", %{class: "eexcharts-tip-title"}, esc(to_string(c.label))),
            Renderer.tooltip_row(c.color, c.name, Renderer.format_tooltip_y(cfg, c.value))
          ])
        end)

      Renderer.tooltip_container(cfg, tips)
    else
      []
    end
  end

  # ── Input normalization ───────────────────────────────────────────────────

  defp normalize(params) do
    labels = params[:labels] || []

    case params[:series] do
      nil ->
        []

      [] ->
        []

      series when is_list(series) ->
        if Enum.all?(series, &is_number/1) do
          [%{name: "series-1", index: 0, points: points_from(series, labels)}]
        else
          series
          |> Enum.with_index()
          |> Enum.map(fn {s, i} -> normalize_series(s, i, labels) end)
        end

      _ ->
        []
    end
  end

  defp normalize_series(%{} = s, i, labels) do
    %{
      name: to_string(s[:name] || "series-#{i + 1}"),
      index: i,
      points: points_from(s[:data] || [], labels)
    }
  end

  defp normalize_series(list, i, labels) when is_list(list) do
    %{name: "series-#{i + 1}", index: i, points: points_from(list, labels)}
  end

  defp normalize_series(_other, i, _labels) do
    %{name: "series-#{i + 1}", index: i, points: []}
  end

  defp points_from(data, labels) when is_list(data) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {pt, j} -> to_point(pt, j, labels) end)
  end

  defp points_from(_data, _labels), do: []

  defp to_point(%{x: x, y: y}, _j, _labels), do: %{label: to_string(x), value: num(y)}

  defp to_point(%{label: label, value: value}, _j, _labels),
    do: %{label: to_string(label), value: num(value)}

  defp to_point({label, value}, _j, _labels), do: %{label: to_string(label), value: num(value)}

  defp to_point(v, j, labels) when is_number(v) do
    %{label: to_string(Enum.at(labels, j) || j + 1), value: v}
  end

  defp to_point(_v, j, labels) do
    %{label: to_string(Enum.at(labels, j) || j + 1), value: 0}
  end

  defp num(v) when is_number(v), do: v
  defp num(_), do: 0

  # ── Squarified treemap (port of Treemap-squared.js) ───────────────────────

  # Multidimensional data (list of series). Returns `[[coords], ...]` — one
  # list of `[x1, y1, x2, y2]` per series.
  defp generate(data, width, height), do: treemap_multidimensional(data, width, height, 0, 0)

  defp treemap_multidimensional(data, width, height, xoff, yoff) do
    if data != [] and is_list(hd(data)) do
      merged = Enum.map(data, &sum_multi/1)
      merged_treemap = treemap_single(merged, width, height, xoff, yoff)

      data
      |> Enum.with_index()
      |> Enum.map(fn {d, i} ->
        [x1, y1, x2, y2] = Enum.at(merged_treemap, i)
        treemap_multidimensional(d, x2 - x1, y2 - y1, x1, y1)
      end)
    else
      treemap_single(data, width, height, xoff, yoff)
    end
  end

  defp treemap_single(data, width, height, xoff, yoff) do
    container = %{xoffset: xoff, yoffset: yoff, width: width, height: height}

    normalize_areas(data, width * height)
    |> squarify([], container, [])
    |> Enum.concat()
  end

  defp normalize_areas(data, area) do
    sum = sum_array(data)
    multiplier = if sum == 0, do: 0, else: area / sum
    Enum.map(data, &(&1 * multiplier))
  end

  defp squarify([], currentrow, container, stack) do
    stack ++ [get_coordinates(container, currentrow)]
  end

  defp squarify([next | rest] = data, currentrow, container, stack) do
    length = min(container.height, container.width)

    if improves_ratio?(currentrow, next, length) do
      squarify(rest, currentrow ++ [next], container, stack)
    else
      newcontainer = cut_area(container, sum_array(currentrow))
      squarify(data, [], newcontainer, stack ++ [get_coordinates(container, currentrow)])
    end
  end

  defp get_coordinates(%{width: width, height: height} = c, row) do
    sum = sum_array(row)
    areawidth = if height == 0, do: 0, else: sum / height
    areaheight = if width == 0, do: 0, else: sum / width

    if width >= height do
      {coords, _} =
        Enum.map_reduce(row, c.yoffset, fn v, suby ->
          seg = if areawidth == 0, do: 0, else: v / areawidth
          {[c.xoffset, suby, c.xoffset + areawidth, suby + seg], suby + seg}
        end)

      coords
    else
      {coords, _} =
        Enum.map_reduce(row, c.xoffset, fn v, subx ->
          seg = if areaheight == 0, do: 0, else: v / areaheight
          {[subx, c.yoffset, subx + seg, c.yoffset + areaheight], subx + seg}
        end)

      coords
    end
  end

  defp cut_area(%{width: width, height: height} = c, area) do
    if width >= height do
      areawidth = if height == 0, do: 0, else: area / height

      %{
        xoffset: c.xoffset + areawidth,
        yoffset: c.yoffset,
        width: width - areawidth,
        height: height
      }
    else
      areaheight = if width == 0, do: 0, else: area / width

      %{
        xoffset: c.xoffset,
        yoffset: c.yoffset + areaheight,
        width: width,
        height: height - areaheight
      }
    end
  end

  defp improves_ratio?([], _next, _length), do: true

  defp improves_ratio?(currentrow, next, length) do
    newrow = currentrow ++ [next]
    calculate_ratio(currentrow, length) >= calculate_ratio(newrow, length)
  end

  defp calculate_ratio(row, length) do
    min = Enum.min(row)
    max = Enum.max(row)
    sum = sum_array(row)

    cond do
      sum == 0 -> :infinity
      min == 0 -> :infinity
      true -> Kernel.max(length * length * max / (sum * sum), sum * sum / (length * length * min))
    end
  end

  defp sum_array(arr), do: Enum.sum(arr)

  defp sum_multi(arr) do
    if arr != [] and is_list(hd(arr)) do
      Enum.reduce(arr, 0, fn a, acc -> acc + sum_multi(a) end)
    else
      sum_array(arr)
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp stroke_color(cfg) do
    case cfg.stroke.colors do
      [c | _] -> c
      c when is_binary(c) -> c
      _ -> "#fff"
    end
  end

  defp dim(v, _default) when is_number(v), do: v
  defp dim(_, default), do: default
end
