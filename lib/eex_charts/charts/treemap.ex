defmodule EexCharts.Charts.Treemap do
  @moduledoc """
  Treemap chart, ported from ApexCharts `src/charts/Treemap.js`, its
  `common/treemap/Helpers` color logic and the vendored squarified-treemap
  algorithm (`src/libs/Treemap-squared.js`, Bruls/Huizing/van Wijk 2000).

  Data shape: one series with `data: [%{x: label, y: value}, ...]`. Also
  accepts `{label, value}` tuples and plain numbers (labels then come from
  `params[:labels]`). With multiple series, each series gets a proportional
  band of the grid, squarified into cells inside it.

  Nested treemaps (an eexcharts extension): a point may carry `children`
  (same shapes, any depth; see `EexCharts.Hierarchy`). A parent is worth the
  sum of its children (its own `y` is ignored). Groups are squarified
  recursively, in data order like the flat layout, inside their parent: each
  group draws a frame in its branch colour (darker at the top level), a
  header band with its name (`plot_options.treemap.group_header`: `show`
  `true`, `font_size` 12, `font_weight` 600, `color` "#fff"; dropped when the
  group is too small) and `group_padding` (3 px) around its children. Child
  areas are proportional to values within their parent's inner rect. Each
  top-level node is a branch with its own palette colour (numbered across
  series); leaves are shaded by value within their branch (`enable_shades`).
  Tooltips show the path, value and share of parent; `on_click` adds
  `phx-value-path`. Data without any `children` renders exactly as before.

  Colors are either distributed (a color per cell, when
  `plot_options.treemap.distributed`) or per-series shaded by value intensity
  (`enable_shades`, `shade_intensity`). Owns its full SVG assembly:
  `render_chart/3` returns the complete container (svg + tooltips).
  """

  import EexCharts.SVG

  alias EexCharts.{Color, Config, Hierarchy, Layout, Renderer}

  @doc "Renders the complete treemap container."
  def render_chart(cfg, params, id) do
    if Hierarchy.nested?(params[:series]) do
      render_nested(cfg, params, id)
    else
      render_flat(cfg, params, id)
    end
  end

  defp render_flat(cfg, params, id) do
    series = normalize(params)

    l = layout(cfg)
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

  defp layout(cfg) do
    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    pad = cfg.grid.padding

    grid_x = pad.left
    grid_y = title_h + pad.top
    grid_w = max(w - grid_x - pad.right, 10)
    grid_h = max(h - grid_y - pad.bottom, 10)

    %Layout{
      w: w,
      h: h,
      grid_x: grid_x,
      grid_y: grid_y,
      grid_w: grid_w,
      grid_h: grid_h,
      title_h: 0
    }
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
          data_j: c[:key] || "#{c.series}-#{c.j}",
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
            |> Map.merge(click_path(c))
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

  # ── Nested treemap ────────────────────────────────────────────────────────

  defp render_nested(cfg, params, id) do
    l = layout(cfg)
    items = nested_items(cfg, nested_series(params), l)
    {groups, leaves} = Enum.split_with(items, &(&1.kind == :group))

    svg =
      Renderer.svg_open(cfg, l, id, [
        Renderer.background(cfg, l),
        Renderer.title(cfg, l),
        group_rects(cfg, groups, params),
        cell_rects(cfg, leaves, params),
        data_labels(cfg, leaves, [%{points: leaves}]),
        group_headers(cfg, groups)
      ])

    Renderer.container(cfg, params, id, svg, nested_tooltips(cfg, items))
  end

  defp nested_series(params) do
    labels = params[:labels] || []

    params[:series]
    |> Enum.with_index()
    |> Enum.map(fn {s, i} ->
      {name, data} = if is_map(s), do: {s[:name], s[:data] || []}, else: {nil, s}

      %{
        name: to_string(name || "series-#{i + 1}"),
        index: i,
        nodes: Hierarchy.nodes(data, &abs/1, labels)
      }
    end)
  end

  # Series get proportional bands (as in the flat multi-series treemap); each
  # band is then laid out recursively. Top-level nodes are numbered across all
  # series to pick their branch colour.
  defp nested_items(cfg, series, l) do
    sums = Enum.map(series, fn s -> s.nodes |> Enum.map(& &1.value) |> Enum.sum() end)
    bands = treemap_single(sums, l.grid_w, l.grid_h, l.grid_x, l.grid_y)
    tm = cfg.plot_options.treemap
    header = tm.group_header

    opts = %{
      padding: tm.group_padding,
      header_h: if(header.show, do: header.font_size + 6, else: 0)
    }

    shade_cfg = put_in(cfg, [:plot_options, :treemap, :distributed], false)
    has_negs = series |> Enum.flat_map(&leaf_values(&1.nodes)) |> Enum.any?(&(&1 < 0))

    {items, _} =
      series
      |> Enum.zip(bands)
      |> Enum.flat_map_reduce(0, fn {s, [x1, y1, x2, y2]}, offset ->
        items = layout_nested(s.nodes, {x1, y1, x2 - x1, y2 - y1}, opts)
        leaves = Enum.filter(items, &(&1.kind == :leaf))

        colored =
          items
          |> Enum.map(fn item ->
            branch = offset + hd(item.path)
            base = Config.color_at(cfg, branch)

            color =
              case item.kind do
                :group ->
                  Color.shade(base, -0.15 + 0.12 * item.depth)

                :leaf ->
                  branch_leaves = Enum.filter(leaves, &(hd(&1.path) == hd(item.path)))

                  {color_fn, _} =
                    cell_color_fns(shade_cfg, %{points: branch_leaves}, branch, has_negs)

                  color_fn.({item.value, 0})
              end

            Map.merge(item, %{
              series: s.index,
              j: List.last(item.path),
              name: s.name,
              key: Enum.join([s.index | item.path], "-"),
              color: color
            })
          end)

        {colored, offset + length(s.nodes)}
      end)

    items
  end

  defp leaf_values(nodes) do
    Enum.flat_map(nodes, fn
      %{children: [], value: v} -> [v]
      %{children: children} -> leaf_values(children)
    end)
  end

  @doc """
  Recursive squarified layout of hierarchy nodes (see `EexCharts.Hierarchy`)
  inside `{x, y, w, h}`.

  Returns a flat list, parents before their children, of
  `%{kind: :group | :leaf, path, labels, depth, label, value, parent_value,
  x, y, w, h}`; groups also carry `header_h` and the `inner` rect their
  children were laid out in. `opts`: `%{padding: px, header_h: px}`.
  """
  def layout_nested(nodes, rect, opts), do: nest(nodes, rect, opts, 0, [], [])

  defp nest(nodes, {x, y, w, h}, opts, depth, path, labels) do
    values = Enum.map(nodes, & &1.value)
    parent_value = Enum.sum(values)
    rects = treemap_single(values, w, h, x, y)

    nodes
    |> Enum.zip(rects)
    |> Enum.flat_map(fn {node, [x1, y1, x2, y2]} ->
      item = %{
        path: path ++ [node.index],
        labels: labels ++ [node.label],
        depth: depth,
        label: node.label,
        value: node.value,
        parent_value: parent_value,
        x: x1,
        y: y1,
        w: x2 - x1,
        h: y2 - y1
      }

      case node.children do
        [] ->
          [Map.put(item, :kind, :leaf)]

        children ->
          {inner, header_h} = inner_rect(item, opts)
          group = Map.merge(item, %{kind: :group, header_h: header_h, inner: inner})
          [group | nest(children, inner, opts, depth + 1, item.path, item.labels)]
      end
    end)
  end

  # The header band only appears when the group can hold it plus some room
  # for its children; padding is dropped for slivers.
  defp inner_rect(%{x: x, y: y, w: w, h: h}, %{padding: pad, header_h: hh}) do
    hh = if hh > 0 and w >= 2 * pad + 24 and h >= hh + 2 * pad + 12, do: hh, else: 0
    pad = if w > 2 * pad + 2 and h > hh + 2 * pad + 2, do: pad, else: 0
    top = if hh > 0, do: hh, else: pad
    {{x + pad, y + top, max(w - 2 * pad, 0), max(h - top - pad, 0)}, hh}
  end

  defp group_rects(cfg, groups, params) do
    stroke = stroke_color(cfg)
    radius = cfg.plot_options.treemap.border_radius
    on_click = params[:on_click]

    rects =
      groups
      |> Enum.filter(&(&1.w > 0 and &1.h > 0))
      |> Enum.map(fn g ->
        attrs = %{
          class: "eexcharts-treemap-group",
          data_j: g.key,
          x: g.x,
          y: g.y,
          width: g.w,
          height: g.h,
          rx: radius,
          fill: g.color,
          fill_opacity: cfg.fill.opacity,
          stroke: stroke,
          stroke_width: cfg.stroke.width
        }

        attrs =
          if on_click do
            Map.merge(attrs, %{
              "phx-click" => on_click,
              "phx-value-index" => g.j,
              "phx-value-series" => g.series,
              cursor: "pointer"
            })
            |> Map.merge(click_path(g))
          else
            attrs
          end

        el("rect", attrs)
      end)

    el("g", %{class: "eexcharts-treemap-groups"}, rects)
  end

  defp group_headers(cfg, groups) do
    header = cfg.plot_options.treemap.group_header

    texts =
      groups
      |> Enum.filter(&(&1.header_h > 0))
      |> Enum.flat_map(fn g ->
        case fit_text(g.label, header.font_size, g.w - 12) do
          nil ->
            []

          text ->
            [
              el(
                "text",
                %{
                  x: g.x + 6,
                  y: g.y + g.header_h / 2 + cfg.stroke.width / 4,
                  dominant_baseline: "central",
                  fill: header.color,
                  font_size: header.font_size,
                  font_weight: header.font_weight,
                  class: "eexcharts-treemap-header"
                },
                esc(text)
              )
            ]
        end
      end)

    el("g", %{class: "eexcharts-treemap-headers"}, texts)
  end

  # Truncates with an ellipsis to fit `max_w`; nil when not even two
  # characters fit.
  defp fit_text(text, font, max_w) do
    cond do
      Layout.text_width(text, font) <= max_w -> text
      String.length(text) <= 2 -> nil
      true -> fit_ellipsis(String.slice(text, 0..-2//1), font, max_w)
    end
  end

  defp fit_ellipsis(text, font, max_w) do
    cond do
      String.length(text) < 2 -> nil
      Layout.text_width(text <> "…", font) <= max_w -> text <> "…"
      true -> fit_ellipsis(String.slice(text, 0..-2//1), font, max_w)
    end
  end

  defp click_path(%{path: path}), do: %{"phx-value-path" => Enum.join(path, "-")}
  defp click_path(_cell), do: %{}

  defp nested_tooltips(cfg, items) do
    if cfg.tooltip.enabled do
      tips =
        Enum.map(items, fn i ->
          share_label = if i.depth == 0, do: "Share of total", else: "Share of parent"
          pct = Hierarchy.share(i.value, i.parent_value)
          Hierarchy.tooltip(cfg, i.key, i.color, i.labels, i.value, share_label, pct)
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
