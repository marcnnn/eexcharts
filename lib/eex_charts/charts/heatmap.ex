defmodule EexCharts.Charts.Heatmap do
  @moduledoc """
  Heatmap chart, ported from ApexCharts `src/charts/HeatMap.js` and its
  `common/treemap/Helpers` color logic.

  Each series is a row (name = y label); `data` holds one number per x
  category, or one `%{x: category, y: value}` point per category as in
  ApexCharts. With points and no `xaxis.categories`, the first series' `x`
  values name the columns. A cell without a numeric value is left empty.
  Cells form a grid: row height is `grid_h / n_series`, cell width
  is `grid_w / n_categories`. A cell's color is the series color shaded by the
  value's intensity within the series' `min..max` range (see
  `plot_options.heatmap.shade_intensity`), or — when
  `plot_options.heatmap.color_scale.ranges` are given — the color of the
  matching range.

  With `xaxis.type: :numeric` or `:datetime` the x-axis is continuous: data
  points are `%{x:, y:}` / `[x, y]` (or plain numbers with x values in
  `xaxis.categories`), each cell is placed by its x value on a linear scale
  and sized from the spacing of the data, and missing x values leave gaps.
  See `EexCharts.Charts.Heatmap.XLayout` for the width rule.

  Without colour ranges, `legend: %{gradient: true}` replaces the series
  legend with a continuous colour bar (bottom by default, `:top` or a
  vertical `:right` bar); see `EexCharts.Charts.Heatmap.GradientLegend`.

  As in ApexCharts, the first series (index 0) is drawn at the **bottom** of
  the grid. Owns its full SVG assembly: `render_chart/3` returns the complete
  container (svg + tooltips).
  """

  import EexCharts.SVG

  alias EexCharts.{Color, Config, Layout, Legend, Renderer}
  alias EexCharts.Charts.Heatmap.{GradientLegend, XLayout}

  @doc "Renders the complete heatmap container."
  def render_chart(cfg, params, id) do
    value_x? = XLayout.value_axis?(cfg)

    # A value x-axis resolves points itself (XLayout.points/2); category
    # columns take one plain number per cell.
    all_series = Renderer.normalize_series(params[:series])

    {all_series, cfg} =
      if value_x?,
        do: {all_series, cfg},
        else: {Enum.map(all_series, &cell_values/1), put_point_categories(cfg, params[:series])}

    hidden = Renderer.hidden_set(params)
    series = Enum.reject(all_series, &MapSet.member?(hidden, &1.index))

    names = Enum.map(all_series, & &1.name)
    n_vis = length(series)

    # Value x-axis: every series resolved to `{x, y}` points; the distinct x
    # values across all series (hidden ones too) become the columns.
    points =
      if value_x?, do: Map.new(all_series, &{&1.index, XLayout.points(cfg, &1.data)}), else: %{}

    xs =
      points
      |> Map.values()
      |> Enum.concat()
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.sort()

    x_step = XLayout.step(xs, cfg.xaxis.type)

    n_cats =
      if value_x? do
        length(xs)
      else
        series
        |> Enum.map(&length(&1.data))
        |> Enum.max(fn -> 0 end)
        |> max(length(cfg.xaxis.categories))
      end

    categories = Renderer.categories(cfg, n_cats)
    ranges = normalize_ranges(get_in(cfg, [:plot_options, :heatmap, :color_scale, :ranges]))

    # ApexCharts normalizes heatmap shade intensity against the GLOBAL value
    # range (w.globals.minY/maxY), not per-series, and treats the chart as
    # "negative" if ANY value is < 0 or any configured range starts at <= 0.
    all_values =
      if value_x? do
        Enum.flat_map(series, fn s -> Enum.map(points[s.index], &elem(&1, 1)) end)
      else
        series |> Enum.flat_map(& &1.data) |> Enum.filter(&is_number/1)
      end

    {g_min, g_max} =
      case all_values do
        [] -> {0, 0}
        _ -> Enum.min_max(all_values)
      end

    ctx = %{
      min: g_min,
      max: g_max,
      has_negs: g_min < 0,
      neg_range: Enum.any?(ranges, &(&1.from <= 0)),
      si: get_in(cfg, [:plot_options, :heatmap, :shade_intensity])
    }

    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0

    # Legend: one item per range when ranges are configured, otherwise one per
    # series (rendered through the shared Legend module so hiding works).
    gradient = if n_vis > 0, do: GradientLegend.options(cfg, ranges)
    {g_top, g_bottom, g_right} = GradientLegend.reserve(gradient, cfg, ctx)

    {legend, legend_h, legend_pos} =
      cond do
        gradient != nil ->
          {nil, 0, :none}

        ranges != [] ->
          lh = if cfg.legend.show, do: cfg.legend.font_size + 16, else: 0
          {nil, lh, cfg.legend.position}

        true ->
          lg = Legend.measure(cfg, names, w, h)
          {lg, lg.h, lg.position}
      end

    y_font = cfg.yaxis.labels.style.font_size
    x_font = cfg.xaxis.labels.style.font_size
    pad = cfg.grid.padding

    left_w =
      if cfg.yaxis.show and cfg.yaxis.labels.show and names != [] do
        names |> Enum.map(&Layout.text_width(&1, y_font)) |> Enum.max()
      else
        0
      end

    x_tick_h = if value_x? and cfg.xaxis.axis_ticks.show, do: cfg.xaxis.axis_ticks.height, else: 0
    x_label_h = if cfg.xaxis.labels.show, do: x_font + 12 + x_tick_h, else: 4 + x_tick_h

    top_legend_h = if(legend_pos == :top, do: legend_h, else: 0) + g_top
    bottom_legend_h = if(legend_pos == :bottom, do: legend_h, else: 0) + g_bottom
    right_legend_w = if(legend_pos == :right, do: (legend && legend.w) || 0, else: 0) + g_right

    grid_x = pad.left + left_w + if(left_w > 0, do: 10, else: 0)
    grid_y = title_h + top_legend_h + pad.top + 6
    grid_w = max(w - grid_x - pad.right - right_legend_w, 10)
    grid_h = max(h - grid_y - x_label_h - pad.bottom - bottom_legend_h, 10)

    l = %Layout{
      w: w,
      h: h,
      grid_x: grid_x,
      grid_y: grid_y,
      grid_w: grid_w,
      grid_h: grid_h,
      legend: legend,
      title_h: 0
    }

    l =
      if value_x? do
        domain = XLayout.domain(cfg, XLayout.extents(xs, x_step))
        %{l | x_scale: XLayout.x_scale(cfg, domain, grid_w), x_type: cfg.xaxis.type}
      else
        l
      end

    cells =
      if value_x? do
        value_cells(cfg, series, points, xs, x_step, l, ranges, ctx)
      else
        category_cells(cfg, series, categories, n_cats, l, ranges, ctx)
      end

    svg =
      Renderer.svg_open(cfg, l, id, [
        Renderer.background(cfg, l),
        Renderer.title(cfg, l),
        cell_rects(cfg, cells, params),
        data_labels(cfg, cells),
        series_labels(cfg, series, l, n_vis),
        if(value_x?,
          do: value_x_labels(cfg, l),
          else: category_labels(cfg, categories, l, n_cats)
        ),
        legend_io(cfg, l, legend, ranges, legend_pos, legend_h, hidden, params),
        gradient_legend(gradient, cfg, l, id, series, ctx)
      ])

    Renderer.container(cfg, params, id, svg, tooltips(cfg, cells))
  end

  defp category_cells(cfg, series, categories, n_cats, l, ranges, ctx) do
    %Layout{grid_x: grid_x, grid_y: grid_y, grid_w: grid_w, grid_h: grid_h} = l
    n_vis = length(series)

    cells =
      if n_vis > 0 and n_cats > 0 do
        y_div = grid_h / n_vis
        x_div = grid_w / n_cats

        series
        |> Enum.with_index()
        |> Enum.flat_map(fn {s, p} ->
          # Series 0 sits at the bottom (ApexCharts draws bottom-up).
          y = grid_y + (n_vis - 1 - p) * y_div
          {color_fn, fore_fn} = cell_color_fns(cfg, s, ranges, ctx)

          0..(n_cats - 1)
          |> Enum.map(fn j -> {j, Enum.at(s.data, j)} end)
          |> Enum.reject(fn {_j, v} -> is_nil(v) end)
          |> Enum.map(fn {j, v} ->
            %{
              series: s.index,
              j: j,
              x: grid_x + j * x_div,
              y: y,
              w: x_div,
              h: y_div,
              value: v,
              color: color_fn.(v),
              fore: fore_fn.(v),
              name: s.name,
              category: Enum.at(categories, j, to_string(j + 1))
            }
          end)
        end)
      else
        []
      end

    cells
  end

  # Value x-axis: each cell spans its `XLayout.extents/2` interval, clipped
  # to the axis domain; `j` is the column's index among the distinct x values.
  defp value_cells(_cfg, [], _points, _xs, _step, _l, _ranges, _ctx), do: []

  defp value_cells(cfg, series, points, xs, step, l, ranges, ctx) do
    n_vis = length(series)
    y_div = l.grid_h / n_vis
    extents = XLayout.extents(xs, step)
    col = xs |> Enum.with_index() |> Map.new()
    %{nice_min: lo, nice_max: hi} = l.x_scale

    series
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, p} ->
      y = l.grid_y + (n_vis - 1 - p) * y_div
      {color_fn, fore_fn} = cell_color_fns(cfg, s, ranges, ctx)

      for {x, v} <- points[s.index],
          {left, right} = extents[x],
          left = max(left, lo),
          right = min(right, hi),
          right > left do
        x0 = Layout.x_value_pos(l, left)

        %{
          series: s.index,
          j: col[x],
          x: x0,
          y: y,
          w: Layout.x_value_pos(l, right) - x0,
          h: y_div,
          value: v,
          color: color_fn.(v),
          fore: fore_fn.(v),
          name: s.name,
          category: XLayout.title(x, cfg.xaxis.type, step)
        }
      end
    end)
  end

  # ── Cells ──────────────────────────────────────────────────────────────

  defp cell_rects(cfg, cells, params) do
    stroke = stroke_color(cfg)
    radius = get_in(cfg, [:plot_options, :heatmap, :radius])
    on_click = params[:on_click]

    rects =
      Enum.map(cells, fn c ->
        attrs = %{
          class: "eexcharts-heatmap-rect",
          data_j: "#{c.series}-#{c.j}",
          x: c.x,
          y: c.y,
          width: c.w,
          height: c.h,
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

    el("g", %{class: "eexcharts-heatmap"}, rects)
  end

  # Returns `{color_fn, fore_fn}` faithfully porting `TreemapHelpers`
  # `determineColor` + `getShadeColor` for the heatmap chart type. The base
  # hue comes from the series' color; the value's shade intensity is
  # normalized against the global range (or a matching color-scale range) and
  # applied via `Color.shade/2` (heatmap `enableShades` defaults to true).
  defp cell_color_fns(cfg, s, ranges, ctx) do
    base = Config.color_at(cfg, s.index)
    default_fore = data_label_color(cfg)

    color_fn = fn v ->
      {color, _fore, percent} = determine_color(base, v, ranges, ctx, default_fore)
      Color.shade(color, shade_percent(percent, ctx))
    end

    fore_fn = fn v ->
      {_color, fore, _percent} = determine_color(base, v, ranges, ctx, default_fore)
      fore
    end

    {color_fn, fore_fn}
  end

  defp cell_values(s), do: %{s | data: Enum.map(s.data, &cell_value/1)}

  defp cell_value(v) when is_number(v), do: v
  defp cell_value(%{y: y}) when is_number(y), do: y
  defp cell_value(_), do: nil

  # ApexCharts heatmaps take `{x, y}` points and read the column names from
  # the first series' `x` values.
  defp put_point_categories(%{xaxis: %{categories: []}} = cfg, [%{data: [_ | _] = data} | _]) do
    if Enum.all?(data, &match?(%{x: _}, &1)),
      do: put_in(cfg, [:xaxis, :categories], Enum.map(data, & &1.x)),
      else: cfg
  end

  defp put_point_categories(cfg, _series), do: cfg

  # Port of `determineColor`: returns `{color, fore_color, percent}`.
  defp determine_color(base, v, ranges, ctx, default_fore) do
    total = safe_total(ctx.max, ctx.min)
    percent = 100 * v / total

    case find_range(ranges, v) do
      nil ->
        {base, default_fore, percent}

      r ->
        r_total = safe_total(r.to, r.from)
        {r.color, r.fore_color || default_fore, 100 * v / r_total}
    end
  end

  # Port of `getShadeColor` (heatmap, light mode, reverseNegativeShade false).
  defp shade_percent(percent, ctx) do
    if ctx.has_negs or ctx.neg_range do
      if percent <= 0 do
        1 - (1 + percent / 100) * ctx.si
      else
        (1 - percent / 100) * ctx.si
      end
    else
      1 - percent / 100
    end
  end

  defp safe_total(max, min) do
    total = abs(max) + abs(min)
    if total == 0, do: -1.0e-6, else: total
  end

  defp find_range(ranges, v) do
    Enum.find(ranges, fn r -> v >= r.from and v <= r.to end)
  end

  # ── Data labels ─────────────────────────────────────────────────────────

  defp data_labels(cfg, cells) do
    if cfg.data_labels.enabled do
      style = cfg.data_labels.style

      labels =
        Enum.map(cells, fn c ->
          el(
            "text",
            %{
              x:
                c.x + c.w / 2 +
                  EexCharts.DataLabels.offset(cfg.data_labels.offset_x, c.value, c.series, c.j),
              y:
                c.y + c.h / 2 +
                  EexCharts.DataLabels.offset(cfg.data_labels.offset_y, c.value, c.series, c.j),
              text_anchor: "middle",
              dominant_baseline: "central",
              fill: c.fore,
              font_size: style.font_size,
              font_weight: style.font_weight,
              class: "eexcharts-datalabel"
            },
            esc(format_data_label(cfg, c.value))
          )
        end)

      el("g", %{class: "eexcharts-datalabels"}, labels)
    else
      []
    end
  end

  defp format_data_label(cfg, v) do
    case cfg.data_labels.formatter do
      f when is_function(f, 1) -> to_string(f.(v))
      _ -> fmt_value(v)
    end
  end

  defp data_label_color(cfg) do
    case cfg.data_labels.style.colors do
      [c | _] -> c
      c when is_binary(c) -> c
      _ -> "#fff"
    end
  end

  # ── Axis labels ───────────────────────────────────────────────────────────

  defp series_labels(cfg, series, l, n_vis) do
    if cfg.yaxis.show and cfg.yaxis.labels.show and n_vis > 0 do
      style = cfg.yaxis.labels.style
      color = label_color(style.colors, cfg.chart.fore_color)
      y_div = l.grid_h / n_vis

      labels =
        series
        |> Enum.with_index()
        |> Enum.map(fn {s, p} ->
          y = l.grid_y + (n_vis - 1 - p) * y_div + y_div / 2

          el(
            "text",
            %{
              x: l.grid_x - 8,
              y: y,
              text_anchor: "end",
              dominant_baseline: "central",
              fill: color,
              font_size: style.font_size,
              font_weight: style.font_weight
            },
            esc(s.name)
          )
        end)

      el("g", %{class: "eexcharts-yaxis-labels"}, labels)
    else
      []
    end
  end

  defp category_labels(cfg, categories, l, n_cats) do
    if cfg.xaxis.labels.show and n_cats > 0 do
      style = cfg.xaxis.labels.style
      color = label_color(style.colors, cfg.chart.fore_color)
      x_div = l.grid_w / n_cats

      labels =
        categories
        |> Enum.with_index()
        |> Enum.map(fn {c, j} ->
          el(
            "text",
            %{
              x: l.grid_x + (j + 0.5) * x_div,
              y: l.grid_y + l.grid_h + style.font_size + 4,
              text_anchor: "middle",
              fill: color,
              font_size: style.font_size,
              font_weight: style.font_weight
            },
            esc(to_string(c))
          )
        end)

      el("g", %{class: "eexcharts-xaxis-labels"}, labels)
    else
      []
    end
  end

  # Value x-axis: the shared value-axis labels plus small tick marks at each
  # labelled value, so the reader can see where a value falls inside a cell.
  defp value_x_labels(cfg, l) do
    ticks =
      if cfg.xaxis.axis_ticks.show and cfg.xaxis.labels.show do
        y0 = l.grid_y + l.grid_h

        marks =
          Enum.map(l.x_scale.ticks, fn %{value: v} ->
            x = Layout.x_value_pos(l, v)

            el("line", %{
              x1: x,
              x2: x,
              y1: y0,
              y2: y0 + cfg.xaxis.axis_ticks.height,
              stroke: cfg.xaxis.axis_ticks.color
            })
          end)

        el("g", %{class: "eexcharts-xaxis-ticks"}, marks)
      else
        []
      end

    [ticks, Renderer.value_x_axis_labels(cfg, l)]
  end

  defp label_color(nil, fore), do: fore
  defp label_color([], fore), do: fore
  defp label_color([c | _], _fore), do: c
  defp label_color(c, _fore) when is_binary(c), do: c

  # ── Legend ────────────────────────────────────────────────────────────────

  defp legend_io(_cfg, _l, nil, [], _pos, _lh, _hidden, _params), do: []

  # Ranges present: render swatches ourselves (range name + color).
  defp legend_io(cfg, l, nil, ranges, pos, legend_h, _hidden, _params) do
    if cfg.legend.show do
      font = cfg.legend.font_size
      m = 12
      swatch = 12

      items =
        Enum.map(ranges, fn r ->
          %{text: r.name, color: r.color, w: swatch + 4 + Layout.text_width(r.name, font) + m}
        end)

      total_w = items |> Enum.map(& &1.w) |> Enum.sum()

      y =
        case pos do
          :bottom -> l.h - legend_h / 2
          # Center the legend in the reserved band just above the grid.
          _ -> max(l.grid_y - legend_h / 2, font)
        end

      start_x = max((l.w - total_w) / 2, 4)

      {io, _} =
        Enum.reduce(items, {[], start_x}, fn item, {acc, x} ->
          marker =
            el("rect", %{
              x: x,
              y: y - swatch / 2,
              width: swatch,
              height: swatch,
              rx: 2,
              fill: item.color
            })

          text =
            el(
              "text",
              %{
                x: x + swatch + 4,
                y: y,
                fill: cfg.legend.labels.colors || cfg.chart.fore_color,
                font_size: font,
                font_weight: cfg.legend.font_weight,
                dominant_baseline: "central"
              },
              esc(item.text)
            )

          {[acc, el("g", %{class: "eexcharts-legend-item"}, [marker, text])], x + item.w}
        end)

      el("g", %{class: "eexcharts-legend"}, io)
    else
      []
    end
  end

  # Series legend via the shared module (colors by series index, hiding works).
  defp legend_io(cfg, l, legend, _ranges, _pos, _lh, hidden, params) do
    Legend.render(legend, cfg, l, hidden: hidden, on_click: params[:on_legend_click])
  end

  defp gradient_legend(nil, _cfg, _l, _id, _series, _ctx), do: []

  defp gradient_legend(opts, cfg, l, id, [s | _], ctx) do
    {color_fn, _fore_fn} = cell_color_fns(cfg, s, [], ctx)
    GradientLegend.render(opts, cfg, l, id, ctx, color_fn)
  end

  # ── Tooltips ──────────────────────────────────────────────────────────────

  defp tooltips(cfg, cells) do
    if cfg.tooltip.enabled do
      tips =
        Enum.map(cells, fn c ->
          el("div", %{class: "eexcharts-tip", data_j: "#{c.series}-#{c.j}", hidden: true}, [
            el("div", %{class: "eexcharts-tip-title"}, esc(to_string(c.category))),
            Renderer.tooltip_row(c.color, c.name, Renderer.format_tooltip_y(cfg, c.value))
          ])
        end)

      Renderer.tooltip_container(cfg, tips)
    else
      []
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

  defp normalize_ranges(nil), do: []

  defp normalize_ranges(ranges) when is_list(ranges) do
    Enum.map(ranges, fn r ->
      %{
        from: Map.get(r, :from, 0),
        to: Map.get(r, :to, 0),
        color: Map.get(r, :color, "#008FFB"),
        name: to_string(Map.get(r, :name) || range_name(r)),
        fore_color: Map.get(r, :fore_color) || Map.get(r, :foreColor)
      }
    end)
  end

  defp normalize_ranges(_), do: []

  defp range_name(r), do: "#{Map.get(r, :from, 0)} - #{Map.get(r, :to, 0)}"

  defp dim(v, _default) when is_number(v), do: v
  defp dim(_, default), do: default
end
