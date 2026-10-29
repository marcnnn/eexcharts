defmodule EexCharts.Charts.LevelMeter do
  @moduledoc """
  Level meter (`type: :level_meter`): each value is a row of `segments`
  discrete segments, filled up to the value. A fractional value (a mean of
  2.4) fills the partial segment with an inner rect, so 0.4 of the third
  segment is coloured. Every segment is its own `<rect>`, which keeps the
  output crisp in PDF.

  Own design; it is not a port of any ApexCharts source.

  ## Data

    * **Matrix**: several series. Each series is a row (its `name` is the
      row label) and each data point is a column. Points are numbers or
      `%{x: category, y: value}` maps, matched to columns by position; the
      column labels come from `categories:` (`xaxis.categories`), else from
      the points' `x`.
    * **List**: one series. Each data point is a row, labelled by its `x`
      (or by `categories:` / `labels:`), and there are no column labels.
      `[3, 2, 4]` with `labels:` works too.

  `layout: :matrix` or `:list` forces one of the two (a single series as a
  one-row matrix, say).

  A map point may carry:

    * `previous` - the earlier value (see below);
    * `target` - this point's own target (a series `target` works too; the
      plot option is the default);
    * `fill_color`, `stroke_color`, `fill` - per-point paint, as for bars
      (`EexCharts.PointStyle`): it beats the series and below-target colours.

  A series may carry `summary: true` (an "Average" row): a rule is drawn
  above it and its row label and value are bold.

  Values are clamped to `0..segments`. A missing point (`nil`) leaves its
  cell empty: no track is drawn.

  ## Options (`plot_options.level_meter`)

    * `layout` - `:auto` (default: one series is a list, more are a matrix),
      `:matrix` or `:list`.
    * `segments` - segments per meter (default `5`).
    * `segment_width` / `segment_height` - px; `nil` (default) fits them:
      the height is 45% of the row pitch (6-18 px), the width fills the
      column but stays at most twice the height.
    * `row_height` - max row pitch in px (default `44`); rows start at the
      top, so a short list does not spread over the whole chart.
    * `gap` - px between neighbouring segments (default `3`).
    * `radius` - corner radius of a segment (default `2`).
    * `track` - `%{show: true, color: "#f2f2f2"}`, the empty segments.
      Dark mode uses `"#4b4f52"`, daisyUI `var(--color-base-200)`.
    * `distributed` - `false` (default): every row takes the first palette
      colour; `true`: each series takes its own palette colour.
    * `target` - level a value should reach (default `nil`, none). A value
      below its target has **all** its filled segments (full and partial) in
      `below_target_color`; a value at or above keeps the row colour. The
      empty track is never recoloured.
    * `below_target_color` - default `"#FEB019"`, daisyUI
      `var(--color-warning)`.
    * `target_gap` - extra px between segment `floor(target)` and the next
      one (default `4`), so the target sits at a visible break. No gap when
      the target is `<= 0` or `>= segments`. Columns line up only when their
      rows share the target.
    * `gained_color` - colour of the part of the fill above `previous`;
      `nil` (default) draws it in the row's own colour at `gained_opacity`.
    * `gained_opacity` - default `0.45`, used when `gained_color` is `nil`.
    * `lost` - `%{show: true, dash: "2 2", width: 1.5}`. When a value
      dropped below `previous`, the segments it lost stay empty track but get
      a dashed outline in the row's colour, so the drop reads as "was here".
    * `show_value` - draw the value beside the meter (default `true`).
    * `value_label` - `%{font_size: 12, font_weight: 400, color: nil,
      formatter: nil, show_previous: true}`. `formatter` is `fn value ->
      text end`; the default prints integers as is and other values with
      one decimal. With a `previous` value and `show_previous`, the text is
      `"<previous> → <value>"`.
    * `row_labels` - `%{show: true, font_size: 13, font_weight: 400,
      color: nil}`.
    * `column_labels` - `%{show: true, font_size: 13, font_weight: 600,
      color: nil}` (matrix only).

  `nil` label colours fall back to `chart.fore_color`, so labels follow dark
  mode and daisyUI. The summary rule is drawn in `chart.fore_color` too.

  ## Interaction

  Hovering a cell shows a tooltip (column, row, value, previous, target);
  `on_click` sends `index` (the column, or the row in a list) and `series`.
  There is no legend: rows are labelled in place, and the colours mean
  states rather than series.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, PointStyle, Renderer}

  @col_gap 16
  @value_gap 6
  @label_gap 16
  @summary_gap 12

  @doc "Renders the complete level meter container."
  def render_chart(cfg, params, id) do
    geo = geometry(cfg, params)
    {cells, defs} = PointStyle.link(geo.cells, id)
    l = geo.layout

    svg =
      Renderer.svg_open(cfg, l, id, [
        Renderer.background(cfg, l),
        Renderer.title(cfg, l),
        defs,
        el("g", %{class: "eexcharts-level-meter"}, [
          column_labels(cfg, geo),
          row_labels(cfg, geo),
          summary_rules(cfg, geo),
          Enum.map(cells, &cell(cfg, geo, &1, params[:on_click]))
        ])
      ])

    Renderer.container(cfg, params, id, svg, tooltips(cfg, cells))
  end

  # ── Geometry ─────────────────────────────────────────────────────────────

  @doc """
  Computes the layout without rendering it.

  Returns `:rows` (`%{label:, summary:, y:}`, `y` the row centre),
  `:columns` (`%{label:, x:}`), `:cells` (one per drawn meter, with its
  `:segments` rects), `:seg_w`, `:seg_h`, `:label_w` and the `:layout`.
  """
  def geometry(cfg, params) do
    o = cfg.plot_options.level_meter
    n = max(trunc(o.segments), 1)
    {mode, rows, columns, points} = normalize(cfg, params, o.layout)

    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    pad = cfg.grid.padding
    metrics = Layout.metrics(cfg)

    rl = o.row_labels
    cl = o.column_labels

    label_w =
      if rl.show and rows != [] do
        rows
        |> Enum.map(&Layout.text_width(&1.label, rl.font_size, metrics))
        |> Enum.max()
        |> Kernel.+(@label_gap)
      else
        0
      end

    header_h = if mode == :matrix and cl.show, do: cl.font_size + 12, else: 0

    points = Enum.map(points, &Map.put(&1, :text, value_text(o, &1)))

    value_w =
      if o.show_value do
        points
        |> Enum.map(&Layout.text_width(&1.text, o.value_label.font_size, metrics))
        |> Enum.max(fn -> 0 end)
        |> Kernel.+(@value_gap)
      else
        0
      end

    x0 = pad.left + 10
    y0 = title_h + pad.top + 10
    gw = max(w - x0 - pad.right - 10, 10)
    gh = max(h - y0 - pad.bottom - 10, 10)

    n_rows = max(length(rows), 1)
    n_summary = Enum.count(rows, & &1.summary)
    pitch = min((gh - header_h - n_summary * @summary_gap) / n_rows, o.row_height)
    seg_h = o.segment_height || pitch |> Kernel.*(0.45) |> max(6) |> min(18)

    n_cols = max(length(columns), 1)
    col_w = (gw - label_w) / n_cols
    # Room for the target gap when any meter has one (targets may be per point).
    tgap = if Enum.any?(points, &gap_after(&1.target, n)), do: o.target_gap, else: 0
    room = col_w - value_w - @col_gap - (n - 1) * o.gap - tgap
    seg_w = o.segment_width || (room / n) |> min(seg_h * 2) |> max(2)

    {rows, _} =
      Enum.map_reduce(rows, y0 + header_h, fn r, y ->
        y = if r.summary, do: y + @summary_gap, else: y
        {Map.put(r, :y, y + pitch / 2), y + pitch}
      end)

    columns =
      Enum.with_index(columns, fn c, i -> %{label: c, x: x0 + label_w + i * col_w} end)

    geo = %{
      mode: mode,
      rows: rows,
      columns: columns,
      seg_w: seg_w,
      seg_h: seg_h,
      pitch: pitch,
      label_w: label_w,
      x0: x0,
      x1: x0 + gw,
      layout: %Layout{
        w: w,
        h: h,
        grid_x: x0,
        grid_y: y0,
        grid_w: gw,
        grid_h: gh,
        title_h: title_h
      }
    }

    Map.put(geo, :cells, Enum.flat_map(points, &cell_geometry(cfg, o, n, geo, &1)))
  end

  defp cell_geometry(_cfg, _o, _n, _geo, %{value: nil}), do: []

  defp cell_geometry(cfg, o, n, geo, p) do
    row = Enum.at(geo.rows, p.row)
    col = Enum.at(geo.columns, p.col)
    target = p.target
    below? = is_number(target) and p.value < target
    base = if below?, do: o.below_target_color, else: p.color
    style = PointStyle.resolve(cfg, p.series, p.point, base)
    break = gap_after(target, n)
    y = row.y - geo.seg_h / 2

    segments =
      for k <- 1..n do
        x =
          col.x + (k - 1) * (geo.seg_w + o.gap) +
            if(break && k > break, do: o.target_gap, else: 0)

        segment(k, x, y, geo.seg_w, p.value, p.previous)
      end

    meter_end = col.x + n * geo.seg_w + (n - 1) * o.gap + if(break, do: o.target_gap, else: 0)

    [
      Map.merge(p, %{
        y: row.y,
        top: y,
        segments: segments,
        style: style,
        below: below?,
        text_x: meter_end + @value_gap,
        category: if(geo.mode == :matrix, do: col.label, else: nil),
        row_label: row.label,
        summary: row.summary
      })
    ]
  end

  # One segment `k` (1-based, covering levels `k - 1 .. k`): the filled part
  # up to `value` is split at `previous` into kept and gained shares, and the
  # part between `value` and `previous` is lost.
  defp segment(k, x, y, w, value, previous) do
    prev = previous || value

    %{
      k: k,
      x: x,
      y: y,
      w: w,
      kept: share(k, 0, min(value, prev)),
      gained: share(k, prev, value),
      lost: share(k, value, prev) > 0
    }
  end

  # Fraction (0..1) of segment `k` that lies between levels `lo` and `hi`.
  defp share(k, lo, hi), do: (min(hi, k) - max(lo, k - 1)) |> max(0) |> min(1)

  defp gap_after(target, n) when is_number(target) do
    t = trunc(Float.floor(target / 1))
    if t > 0 and t < n, do: t
  end

  defp gap_after(_target, _n), do: nil

  # ── Marks ────────────────────────────────────────────────────────────────

  defp cell(cfg, geo, c, on_click) do
    o = cfg.plot_options.level_meter
    style = c.style
    h = geo.seg_h

    rects =
      Enum.map(c.segments, fn s ->
        [
          track(o, s, h),
          fill_rect(o, s, h, 0, s.kept, style, nil),
          fill_rect(o, s, h, s.kept, s.gained, style, :gained),
          lost_outline(o, s, h, style)
        ]
      end)

    attrs =
      %{class: "eexcharts-level-meter-cell", data_j: "#{c.series.index}-#{c.j}"}
      |> click(on_click, c.j, c.series.index)

    el("g", attrs, [rects, value_label(cfg, o, c)])
  end

  # A fully filled segment needs no track behind it.
  defp track(o, s, h) do
    if o.track.show and s.kept + s.gained < 1 do
      el("rect", %{
        class: "eexcharts-level-meter-track",
        x: s.x,
        y: s.y,
        width: s.w,
        height: h,
        rx: radius(o, s.w, h),
        fill: o.track.color
      })
    else
      []
    end
  end

  defp fill_rect(_o, _s, _h, _from, share, _style, _kind) when share <= 0, do: []

  defp fill_rect(o, s, h, from, share, style, kind) do
    w = s.w * share
    {fill, opacity} = paint(o, style, kind)

    el("rect", %{
      class: fill_class(kind, share, style),
      x: s.x + s.w * from,
      y: s.y,
      width: w,
      height: h,
      rx: radius(o, w, h),
      fill: fill,
      fill_opacity: opacity,
      stroke: style.stroke,
      stroke_width: if(style.stroke, do: style.stroke_width)
    })
  end

  defp paint(_o, style, nil), do: {style.fill, style.fill_opacity}
  defp paint(%{gained_color: nil} = o, style, :gained), do: {style.fill, o.gained_opacity}
  defp paint(o, _style, :gained), do: {o.gained_color, 1}

  defp fill_class(kind, share, style) do
    [
      "eexcharts-level-meter-fill",
      if(kind == :gained, do: " eexcharts-level-meter-gained", else: ""),
      if(share < 1, do: " eexcharts-level-meter-partial", else: ""),
      if(style.class, do: [" ", style.class], else: "")
    ]
  end

  defp lost_outline(%{lost: %{show: true} = lost} = o, %{lost: true} = s, h, style) do
    sw = lost.width

    el("rect", %{
      class: "eexcharts-level-meter-lost",
      x: s.x + sw / 2,
      y: s.y + sw / 2,
      width: max(s.w - sw, 0),
      height: max(h - sw, 0),
      rx: radius(o, s.w - sw, h - sw),
      fill: "none",
      stroke: style.stroke || style.fill,
      stroke_width: sw,
      stroke_dasharray: lost.dash
    })
  end

  defp lost_outline(_o, _s, _h, _style), do: []

  defp radius(o, w, h), do: o.radius |> min(w / 2) |> min(h / 2) |> max(0)

  defp click(attrs, nil, _j, _series), do: attrs

  defp click(attrs, on_click, j, series) do
    Map.merge(attrs, %{
      "phx-click" => on_click,
      "phx-value-index" => j,
      "phx-value-series" => series,
      cursor: "pointer"
    })
  end

  # ── Labels ───────────────────────────────────────────────────────────────

  defp value_label(cfg, %{show_value: true} = o, c) do
    v = o.value_label

    el(
      "text",
      %{
        class: "eexcharts-level-meter-value",
        x: c.text_x,
        y: c.y,
        dominant_baseline: "central",
        fill: v.color || cfg.chart.fore_color,
        font_size: v.font_size,
        font_weight: if(c.summary, do: 700, else: v.font_weight)
      },
      esc(c.text)
    )
  end

  defp value_label(_cfg, _o, _c), do: []

  defp row_labels(cfg, geo) do
    rl = cfg.plot_options.level_meter.row_labels

    if rl.show do
      el(
        "g",
        %{class: "eexcharts-level-meter-row-labels"},
        Enum.map(geo.rows, fn r ->
          el(
            "text",
            %{
              x: geo.x0,
              y: r.y,
              dominant_baseline: "central",
              fill: rl.color || cfg.chart.fore_color,
              font_size: rl.font_size,
              font_weight: if(r.summary, do: 700, else: rl.font_weight)
            },
            esc(r.label)
          )
        end)
      )
    else
      []
    end
  end

  defp column_labels(cfg, %{mode: :matrix} = geo) do
    cl = cfg.plot_options.level_meter.column_labels

    if cl.show do
      y = geo.layout.grid_y + cl.font_size / 2

      el(
        "g",
        %{class: "eexcharts-level-meter-column-labels"},
        Enum.map(geo.columns, fn c ->
          el(
            "text",
            %{
              x: c.x,
              y: y,
              dominant_baseline: "central",
              fill: cl.color || cfg.chart.fore_color,
              font_size: cl.font_size,
              font_weight: cl.font_weight
            },
            esc(c.label)
          )
        end)
      )
    else
      []
    end
  end

  defp column_labels(_cfg, _geo), do: []

  defp summary_rules(cfg, geo) do
    geo.rows
    |> Enum.filter(& &1.summary)
    |> Enum.map(fn r ->
      y = r.y - geo.pitch / 2 - @summary_gap / 2

      el("line", %{
        class: "eexcharts-level-meter-rule",
        x1: geo.x0,
        y1: y,
        x2: geo.x1,
        y2: y,
        stroke: cfg.chart.fore_color,
        stroke_width: 1
      })
    end)
  end

  defp value_text(o, %{value: v, previous: prev}) do
    f = o.value_label.formatter
    text = format(f, v)

    if is_number(prev) and o.value_label.show_previous,
      do: "#{format(f, prev)} → #{text}",
      else: text
  end

  defp format(_f, nil), do: ""
  defp format(f, v) when is_function(f, 1), do: to_string(f.(v))
  defp format(_f, v) when is_integer(v), do: Integer.to_string(v)

  defp format(_f, v) do
    r = Float.round(v / 1, 1)
    if r == trunc(r), do: Integer.to_string(trunc(r)), else: Float.to_string(r)
  end

  # ── Tooltips ─────────────────────────────────────────────────────────────

  defp tooltips(cfg, cells) do
    if cfg.tooltip.enabled do
      cells
      |> Enum.map(fn c ->
        color = if is_binary(c.style.fill), do: c.style.fill, else: c.color
        title = c.category || c.row_label
        name = if c.category, do: c.row_label, else: c.series.name

        el("div", %{class: "eexcharts-tip", data_j: "#{c.series.index}-#{c.j}", hidden: true}, [
          el("div", %{class: "eexcharts-tip-title"}, esc(to_string(title))),
          Renderer.tooltip_row(color, name, Renderer.format_tooltip_y(cfg, c.value)),
          extra_row("Previous", c.previous, cfg),
          extra_row("Target", c.target, cfg)
        ])
      end)
      |> then(&Renderer.tooltip_container(cfg, &1))
    else
      []
    end
  end

  defp extra_row(_label, nil, _cfg), do: []

  defp extra_row(label, v, cfg) do
    el("div", %{class: "eexcharts-tip-row"}, [
      el("span", %{class: "eexcharts-tip-label"}, [esc(label), ": "]),
      el("span", %{class: "eexcharts-tip-value"}, esc(Renderer.format_tooltip_y(cfg, v)))
    ])
  end

  # ── Input normalization ──────────────────────────────────────────────────

  # Returns `{mode, rows, columns, points}`; every point knows its row and
  # column index, its series, its clamped value and the resolved target.
  defp normalize(cfg, params, layout) do
    o = cfg.plot_options.level_meter
    series = Renderer.normalize_series(params[:series])
    mode = mode(layout, series)
    cats = Enum.map(cfg.xaxis.categories, &to_string/1)
    labels = Enum.map(params[:labels] || [], &to_string/1)

    case mode do
      :matrix ->
        n_cols = series |> Enum.map(&length(&1.data)) |> Enum.max(fn -> 0 end)
        xs = Enum.flat_map(series, &Enum.with_index(&1.data))
        columns = Enum.map(0..(n_cols - 1)//1, &column_label(cats, xs, &1))

        rows =
          Enum.map(series, &%{label: &1.name, summary: &1[:summary] == true})

        points =
          for s <- series,
              {pt, j} <- Enum.with_index(s.data),
              do: point(cfg, o, s, pt, j, s.index, j)

        {:matrix, rows, columns, points}

      :list ->
        s = List.first(series) || %{name: "series-1", data: [], index: 0}

        rows =
          Enum.with_index(s.data, fn pt, i ->
            label = Enum.at(cats, i) || Enum.at(labels, i) || x_of(pt) || "#{i + 1}"
            %{label: to_string(label), summary: is_map(pt) and pt[:summary] == true}
          end)

        points = Enum.with_index(s.data, fn pt, i -> point(cfg, o, s, pt, i, i, 0) end)
        {:list, rows, [nil], points}
    end
  end

  defp mode(:matrix, _series), do: :matrix
  defp mode(:list, _series), do: :list
  defp mode(_auto, [_one]), do: :list
  defp mode(_auto, _series), do: :matrix

  defp column_label(cats, xs, j) do
    Enum.at(cats, j) ||
      Enum.find_value(xs, "#{j + 1}", fn {pt, i} -> i == j and x_of(pt) end)
      |> to_string()
  end

  defp x_of(%{x: x}) when not is_nil(x), do: x
  defp x_of(_pt), do: nil

  defp point(cfg, o, s, pt, j, row, col) do
    n = max(trunc(o.segments), 1)

    color =
      s[:color] || Config.color_at(cfg, if(o.distributed, do: s.index, else: 0))

    %{
      series: s,
      point: pt,
      j: j,
      row: row,
      col: col,
      color: color,
      value: clamp(y_of(pt), n),
      previous: clamp(field(pt, :previous), n),
      target: field(pt, :target) || s[:target] || o.target
    }
  end

  defp y_of(%{y: y}), do: y
  defp y_of(v) when is_number(v), do: v
  defp y_of(_), do: nil

  defp field(%{} = pt, key), do: Map.get(pt, key)
  defp field(_pt, _key), do: nil

  defp clamp(v, n) when is_number(v), do: v |> max(0) |> min(n)
  defp clamp(_v, _n), do: nil

  defp dim(v, _default) when is_number(v), do: v
  defp dim(_, default), do: default
end
