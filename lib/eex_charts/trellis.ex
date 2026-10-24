defmodule EexCharts.Trellis do
  @moduledoc """
  Small multiples ("trellis" / facet grids) for cartesian charts.

  A chart with a `trellis` option is split into a grid of panels, one per
  series or per series group. Every panel is a complete cartesian chart of the
  same type (`:line`, `:area`, `:bar`, `:scatter`, `:bubble`), rendered by the
  ordinary renderer, with the group name as a small panel title.

      EexCharts.render("sales", :line, series,
        categories: months,
        options: %{trellis: %{by: :series, columns: 3}}
      )

  ## Options (`options.trellis`)

    * `:by` — `:series` (default) gives each series its own panel. `:group`
      puts series sharing a `group:` key on the same panel, in order of first
      appearance; series without a `group:` share one untitled panel.
    * `:columns` — panels per row. Defaults to `ceil(sqrt(panel_count))`.
    * `:shared_y` — `true` (default) gives every panel the same value axis;
      only the left column then shows value labels. `false` lets each panel
      scale to its own data and label its own axis.
    * `:shared_x` — `true` (default) gives every panel the same x domain (the
      same categories, or the same numeric/datetime range); only the panel
      with nothing below it shows x labels. `false` frees it.
    * `:gap` — space between panels in px (default `12`).
    * `:title` — panel title: `%{show: true, align: :center, offset_x: 0,
      margin: 4, style: %{font_size: 12, font_weight: 600, color: nil}}`.
      `align` places the title over the panel's plot area, not the panel box.
      A panel without a title (or `show: false`) reserves no title band.

  ## Behaviour

    * The chart-level `title` and the legend are drawn once for the whole
      trellis. Legend items, colors and `hidden_series` indexes are keyed by
      distinct series *name*: with `by: :group` and the same names in every
      group ("Web", "Retail" per region) each name is one legend item and one
      color across all panels, and toggling it (`on_legend_click` +
      `hidden_series`) hides that series in every panel. With unique names
      this is the plain series index. A shared scale follows the visible
      data.
    * Plot areas are aligned: every panel in a column has the same plot left
      and right edges, every panel in a row the same plot top and bottom. The
      columns and rows carrying axis labels are widened instead of squeezing
      their plots.
    * Axis titles follow the labels: with a shared axis only the edge panels
      show its title.
    * Each panel gets its own DOM id, `"<id>-p<k>"`, so ids, clip paths,
      gradients, hover zones and tooltips stay unique per panel. In LiveView
      every panel is its own hooked container laid over a frame SVG that
      carries the title and legend, so hovering one panel never lights up
      another. `push_hover` events report the panel id.
    * Under `EexCharts.to_svg/4` the panels are nested `<svg>` elements of one
      standalone SVG.

  ## Limitations

    * A shared value axis is computed for a single, linear y-axis. With a
      list of y-axes or a logarithmic axis each panel keeps its own scale
      (labels are still suppressed on inner panels when `shared_y` is on).
    * Series-indexed option lists other than `colors` (`stroke.dash_array`,
      `markers.shape`, ...) are indexed per panel, not globally.
    * `on_click` payloads carry the category index only, not the panel.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, Legend, Renderer, Scale}

  @supported [:line, :area, :bar, :scatter, :bubble]

  @defaults %{
    by: :series,
    columns: nil,
    shared_y: true,
    shared_x: true,
    gap: 12,
    title: %{
      show: true,
      align: :center,
      offset_x: 0,
      margin: 4,
      style: %{font_size: 12, font_weight: 600, color: nil}
    }
  }

  @doc "Default `options.trellis` settings."
  def defaults, do: @defaults

  @doc """
  Renders a trellis chart. Takes the same params map as
  `EexCharts.Renderer.render/1`, whose `options` carry a `trellis` map.
  """
  def render(params) do
    type = params[:type] || :line
    id = params[:id] || "eexcharts"

    unless type in @supported do
      raise ArgumentError,
            "trellis supports #{inspect(@supported)} charts, got #{inspect(type)}"
    end

    {tcfg, base_opts} = Map.pop(params[:options] || %{}, :trellis)
    tcfg = Config.deep_merge(@defaults, tcfg)

    base_opts =
      base_opts
      |> put_if(params[:width], [:chart, :width])
      |> put_if(params[:height], [:chart, :height])
      |> put_if(params[:categories], [:xaxis, :categories])

    raw = raw_series(params[:series])

    # The shared legend has one item per distinct series name: a name that
    # recurs across groups ("Web" in every region) is one legend entry, one
    # color, and one `hidden_series` index. Panel members carry that index.
    names = raw |> Enum.map(fn {s, _i} -> to_string(s.name) end) |> Enum.uniq()
    key = names |> Enum.with_index() |> Map.new()

    panels =
      raw
      |> panels(tcfg.by)
      |> Enum.map(fn p ->
        %{p | members: Enum.map(p.members, fn {s, _i} -> {s, key[to_string(s.name)]} end)}
      end)

    if panels == [] do
      params |> Map.put(:options, base_opts) |> Renderer.render()
    else
      render_trellis(params, type, id, tcfg, base_opts, names, panels)
    end
  end

  # ── Panels ───────────────────────────────────────────────────────────────

  # `[{series_map, global_index}]`, mirroring `Renderer.normalize_series/1`.
  defp raw_series(nil), do: []

  defp raw_series(series) when is_list(series) do
    if series != [] and Enum.all?(series, &is_number/1) do
      [{%{name: "series-1", data: series}, 0}]
    else
      series
      |> Enum.map(fn
        %{} = s -> s
        other -> %{data: List.wrap(other)}
      end)
      |> Enum.with_index()
      |> Enum.map(fn {s, i} -> {Map.put_new(s, :name, "series-#{i + 1}"), i} end)
    end
  end

  defp panels(raw, :group) do
    raw
    |> Enum.group_by(fn {s, _i} -> s[:group] end)
    |> Enum.sort_by(fn {_g, [{_s, i} | _]} -> i end)
    |> Enum.map(fn {g, members} ->
      %{title: if(is_nil(g), do: nil, else: to_string(g)), members: members}
    end)
  end

  defp panels(raw, _series) do
    Enum.map(raw, fn {s, _i} = m -> %{title: to_string(s.name), members: [m]} end)
  end

  # ── Assembly ─────────────────────────────────────────────────────────────

  defp render_trellis(params, type, id, tcfg, base_opts, names, panels) do
    static? = params[:static] == true
    hidden = Renderer.hidden_set(params)

    cfg = Config.build(type, base_opts)
    cfg = if static?, do: Renderer.staticize_cfg(cfg), else: cfg

    count = length(panels)
    cols = min(max(tcfg.columns || ceil(:math.sqrt(count)), 1), count)
    rows = ceil(count / cols)

    frame = frame(cfg, names)
    gap = tcfg.gap

    horizontal? =
      type == :bar and get_in(cfg, [:plot_options, :bar, :horizontal]) == true

    panel_h0 = (frame.ah - (rows - 1) * gap) / rows
    panel_w0 = (frame.aw - (cols - 1) * gap) / cols

    shared =
      shared_scales(
        cfg,
        base_opts,
        tcfg,
        panels,
        hidden,
        if(horizontal?, do: panel_w0, else: panel_h0)
      )

    specs =
      panels
      |> Enum.with_index()
      |> Enum.map(fn {panel, k} ->
        col = rem(k, cols)
        row = div(k, cols)
        left? = col == 0
        bottom? = k + cols >= count

        # Horizontal bars swap the axes: categories run down the left gutter
        # and values along the bottom.
        {show_left, show_bottom} =
          if horizontal?,
            do: {not tcfg.shared_x or left?, not tcfg.shared_y or bottom?},
            else: {not tcfg.shared_y or left?, not tcfg.shared_x or bottom?}

        members = panel.members
        local_hidden = for {{_s, i}, li} <- Enum.with_index(members), i in hidden, do: li

        title = if tcfg.title.show, do: panel.title

        %{
          k: k,
          col: col,
          row: row,
          title: title,
          series: Enum.map(members, &elem(&1, 0)),
          colors: Enum.map(members, fn {_s, i} -> Config.color_at(cfg, i) end),
          hidden: local_hidden,
          show_left: show_left,
          show_bottom: show_bottom
        }
      end)

    base_pad = cfg.grid.padding
    sizing = solve(type, base_opts, specs, shared, tcfg, base_pad, frame, cols, rows, gap)

    panel_nodes =
      Enum.map(specs, fn spec ->
        col_w = Enum.at(sizing.col_w, spec.col)
        row_h = Enum.at(sizing.row_h, spec.row)
        x = frame.ax + Enum.sum(Enum.take(sizing.col_w, spec.col)) + spec.col * gap
        y = frame.ay + Enum.sum(Enum.take(sizing.row_h, spec.row)) + spec.row * gap
        pad = Map.fetch!(sizing.pads, spec.k)
        l_inset = Enum.at(sizing.left, spec.col)
        plot_w = col_w - l_inset - Enum.at(sizing.right, spec.col)

        opts =
          panel_opts(base_opts, spec, shared, tcfg, col_w, row_h, pad)
          |> put_title_offset(spec, tcfg, col_w, l_inset, plot_w)

        node =
          Renderer.render(%{
            id: "#{id}-p#{spec.k}",
            type: type,
            series: spec.series,
            options: opts,
            hidden_series: spec.hidden,
            static: params[:static],
            on_click: params[:on_click],
            push_hover: params[:push_hover],
            hook: params[:hook]
          })

        place(node, static?, frame, x, y, col_w, row_h)
      end)

    first_left = frame.ax + hd(sizing.left)

    legend_layout = %Layout{
      w: frame.w,
      h: frame.h,
      grid_x: first_left,
      grid_y: frame.legend_grid_y,
      grid_h: frame.ah,
      title_h: frame.title_h
    }

    frame_layout = %Layout{w: frame.w, h: frame.h, title_h: frame.title_h}

    frame_children = [
      Renderer.background(cfg, frame_layout),
      Renderer.title(cfg, frame_layout),
      Legend.render(frame.legend, cfg, legend_layout,
        hidden: hidden,
        on_click: params[:on_legend_click]
      )
    ]

    if static? do
      Renderer.svg_open(cfg, frame_layout, id, [frame_children, panel_nodes])
      |> set_attr(:class, "eexcharts-svg eexcharts-trellis")
    else
      svg = Renderer.svg_open(cfg, frame_layout, id, frame_children)
      container(cfg, params, id, [svg, panel_nodes])
    end
  end

  # ── Frame: chart title + shared legend + the panel area ──────────────────

  defp frame(cfg, names) do
    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    legend = Legend.measure(cfg, names, w, h)

    {ax, ay, aw, ah, legend_grid_y} =
      case {legend.show, legend.position} do
        {false, _} ->
          {0, title_h, w, h - title_h, title_h}

        {true, :top} ->
          # `Legend.render/4` puts a top legend at `title_h + 4` when the
          # grid starts at `legend.h + 12`.
          top = title_h + legend.h + 4
          {0, top, w, h - top, legend.h + 12}

        {true, :right} ->
          {0, title_h, w - legend.w, h - title_h, title_h}

        {true, :bottom} ->
          {0, title_h, w, h - title_h - legend.h, title_h}
      end

    %{
      w: w,
      h: h,
      title_h: title_h,
      legend: legend,
      legend_grid_y: legend_grid_y,
      ax: ax,
      ay: ay,
      aw: aw,
      ah: ah
    }
  end

  # ── Shared scales ────────────────────────────────────────────────────────

  defp shared_scales(cfg, base_opts, tcfg, panels, hidden, svg_dim) do
    visible =
      for p <- panels do
        for {s, i} <- p.members, i not in hidden, do: s
      end

    %{
      y: if(tcfg.shared_y, do: shared_y(cfg, visible, svg_dim)),
      x: if(tcfg.shared_x, do: shared_x(cfg, base_opts, panels))
    }
  end

  # One nice scale over every panel's data, then forced on each panel as
  # `min`/`max`/`tick_amount` so they all draw identical ticks whatever their
  # height.
  defp shared_y(%{yaxis: %{} = axis} = cfg, visible, svg_dim) do
    axis = Config.deep_merge(Config.defaults().yaxis, axis)

    if axis.logarithmic do
      nil
    else
      ranges = Enum.map(visible, &panel_y_range(cfg, &1))
      mins = for {mn, _} <- ranges, is_number(mn), do: mn
      maxs = for {_, mx} <- ranges, is_number(mx), do: mx

      scale =
        Scale.nice_scale(Enum.min(mins, fn -> nil end), Enum.max(maxs, fn -> nil end),
          min: axis.min,
          max: axis.max,
          tick_amount: axis.tick_amount,
          step_size: axis.step_size,
          svg_height: svg_dim
        )

      %{min: scale.nice_min, max: scale.nice_max, tick_amount: length(scale.ticks) - 1}
    end
  end

  defp shared_y(_cfg, _visible, _svg_dim), do: nil

  defp panel_y_range(cfg, series) do
    values =
      if cfg.chart.stacked and cfg.chart.type == :bar do
        series
        |> Enum.flat_map(&Layout.series_points(cfg, &1[:data] || []))
        |> Enum.group_by(fn {j, _x, _y, _z} -> j end, fn {_j, _x, y, _z} -> y end)
        |> Enum.flat_map(fn {_j, ys} ->
          ys = Enum.filter(ys, &is_number/1)

          [
            ys |> Enum.filter(&(&1 >= 0)) |> Enum.sum(),
            ys |> Enum.filter(&(&1 < 0)) |> Enum.sum()
          ]
        end)
      else
        for s <- series,
            {_j, _x, y, _z} <- Layout.series_points(cfg, s[:data] || []),
            is_number(y),
            do: y
      end

    case values do
      [] ->
        {nil, nil}

      _ ->
        {mn, mx} = Enum.min_max(values)
        if cfg.chart.type == :bar, do: {min(mn, 0), max(mx, 0)}, else: {mn, mx}
    end
  end

  # Value x-axes share one `min`/`max`; category axes share one category list.
  defp shared_x(cfg, base_opts, panels) do
    all = for p <- panels, {s, _i} <- p.members, do: s

    if Layout.value_x?(cfg) do
      xs =
        for s <- all,
            {_j, x, _y, _z} <- Layout.series_points(cfg, s[:data] || []),
            is_number(x),
            do: x

      case xs do
        [] ->
          nil

        _ ->
          {mn, mx} = Enum.min_max(xs)

          %{
            min: if(is_number(cfg.xaxis.min), do: cfg.xaxis.min, else: mn),
            max: if(is_number(cfg.xaxis.max), do: cfg.xaxis.max, else: mx)
          }
      end
    else
      user_cats = get_in(base_opts, [:xaxis, :categories]) || []
      n = all |> Enum.map(&length(&1[:data] || [])) |> Enum.max(fn -> 0 end)

      if user_cats == [] and n > 0,
        do: %{categories: Enum.map(1..n, &to_string/1)},
        else: nil
    end
  end

  # ── Panel options ────────────────────────────────────────────────────────

  defp panel_opts(base_opts, spec, shared, tcfg, w, h, pad) do
    title =
      if spec.title do
        %{
          text: spec.title,
          align: tcfg.title.align,
          margin: tcfg.title.margin,
          offset_x: 0,
          offset_y: 0,
          style: tcfg.title.style
        }
      else
        %{text: nil}
      end

    base_opts
    |> Config.deep_merge(%{
      chart: %{width: w, height: h, parent_height_offset: 0, max_width: false},
      legend: %{show: false},
      title: title,
      colors: spec.colors,
      grid: %{padding: pad}
    })
    |> Map.update(:yaxis, yaxis_override(spec, shared), &merge_yaxis(&1, spec, shared))
    |> Map.update(
      :xaxis,
      xaxis_override(spec, shared),
      &Config.deep_merge(&1, xaxis_override(spec, shared))
    )
  end

  defp yaxis_override(spec, shared) do
    labels = if spec.show_left, do: %{}, else: %{labels: %{show: false}, title: %{text: nil}}
    Config.deep_merge(labels, (shared.y && Map.take(shared.y, [:min, :max, :tick_amount])) || %{})
  end

  # A list of y-axes keeps its own scales; only labels are suppressed.
  defp merge_yaxis(axes, spec, _shared) when is_list(axes) do
    if spec.show_left,
      do: axes,
      else: Enum.map(axes, &Config.deep_merge(&1, %{labels: %{show: false}, title: %{text: nil}}))
  end

  defp merge_yaxis(%{} = axis, spec, shared),
    do: Config.deep_merge(axis, yaxis_override(spec, shared))

  defp xaxis_override(spec, shared) do
    labels = if spec.show_bottom, do: %{}, else: %{labels: %{show: false}, title: %{text: nil}}
    Config.deep_merge(labels, shared.x || %{})
  end

  defp put_title_offset(opts, %{title: nil}, _tcfg, _w, _l, _p), do: opts

  defp put_title_offset(opts, _spec, tcfg, w, l_inset, plot_w) do
    offset =
      case tcfg.title.align do
        :left -> l_inset - 10
        :right -> l_inset + plot_w - (w - 10)
        _ -> l_inset + plot_w / 2 - w / 2
      end

    put_in(opts, [:title, :offset_x], offset + tcfg.title.offset_x)
  end

  # ── Sizing ───────────────────────────────────────────────────────────────
  #
  # Each panel's insets (space between its box and its plot rectangle) depend
  # on which labels it shows and on its own size. Columns take the widest
  # left/right insets of their panels and rows the tallest top/bottom ones;
  # every panel then pads up to its column/row insets, so all plots of a
  # column (row) line up and every plot gets the same width (height). A few
  # rounds settle the size-dependent parts (tick counts, label overhang).

  defp solve(type, base_opts, specs, shared, tcfg, base_pad, frame, cols, rows, gap) do
    col_w = List.duplicate((frame.aw - (cols - 1) * gap) / cols, cols)
    row_h = List.duplicate((frame.ah - (rows - 1) * gap) / rows, rows)
    zero = Map.new(specs, &{&1.k, %{top: 0, right: 0, bottom: 0, left: 0}})

    Enum.reduce(1..4, %{col_w: col_w, row_h: row_h, extra: zero}, fn _round, acc ->
      insets =
        Map.new(specs, fn spec ->
          w = Enum.at(acc.col_w, spec.col)
          h = Enum.at(acc.row_h, spec.row)
          extra = acc.extra[spec.k]
          pad = add_pad(base_pad, extra)
          {gx, gr, gy, gb} = measure(type, base_opts, spec, shared, tcfg, w, h, pad)

          {spec.k,
           %{
             left: gx - extra.left,
             right: gr - extra.right,
             top: gy - extra.top,
             bottom: gb - extra.bottom
           }}
        end)

      max_by = fn key, group ->
        for i <- 0..(group_count(key, cols, rows) - 1) do
          specs
          |> Enum.filter(&(Map.fetch!(&1, group) == i))
          |> Enum.map(&insets[&1.k][key])
          |> Enum.max(fn -> 0 end)
        end
      end

      left = max_by.(:left, :col)
      right = max_by.(:right, :col)
      top = max_by.(:top, :row)
      bottom = max_by.(:bottom, :row)

      plot_w = max((frame.aw - (cols - 1) * gap - Enum.sum(left) - Enum.sum(right)) / cols, 10)
      plot_h = max((frame.ah - (rows - 1) * gap - Enum.sum(top) - Enum.sum(bottom)) / rows, 10)

      extra =
        Map.new(specs, fn spec ->
          ins = insets[spec.k]

          {spec.k,
           %{
             left: Enum.at(left, spec.col) - ins.left,
             right: Enum.at(right, spec.col) - ins.right,
             top: Enum.at(top, spec.row) - ins.top,
             bottom: Enum.at(bottom, spec.row) - ins.bottom
           }}
        end)

      %{
        col_w: Enum.zip_with(left, right, &(&1 + plot_w + &2)),
        row_h: Enum.zip_with(top, bottom, &(&1 + plot_h + &2)),
        extra: extra,
        left: left,
        right: right
      }
    end)
    |> then(fn acc ->
      pads = Map.new(acc.extra, fn {k, extra} -> {k, add_pad(base_pad, extra)} end)
      Map.put(acc, :pads, pads)
    end)
  end

  defp group_count(key, cols, _rows) when key in [:left, :right], do: cols
  defp group_count(_key, _cols, rows), do: rows

  defp add_pad(base, extra) do
    %{
      top: base.top + extra.top,
      right: base.right + extra.right,
      bottom: base.bottom + extra.bottom,
      left: base.left + extra.left
    }
  end

  # `{left, right, top, bottom}` insets of the plot rectangle in a panel.
  defp measure(type, base_opts, spec, shared, tcfg, w, h, pad) do
    cfg = Config.build(type, panel_opts(base_opts, spec, shared, tcfg, w, h, pad))
    series = Renderer.normalize_series(spec.series)
    visible = Enum.reject(series, &(&1.index in spec.hidden))
    names = Enum.map(series, & &1.name)

    n =
      visible
      |> Enum.map(&length(&1.data))
      |> Enum.max(fn -> 0 end)
      |> max(length(cfg.xaxis.categories))

    y_range = panel_y_range(cfg, visible)

    x_range =
      if Layout.value_x?(cfg) do
        xs =
          for s <- visible,
              {_j, x, _y, _z} <- Layout.series_points(cfg, s.data),
              is_number(x),
              do: x

        if xs == [], do: {0, max(n, 1)}, else: Enum.min_max(xs)
      end

    y_ranges = Enum.map(Config.yaxes(cfg), fn _ -> y_range end)
    l = Layout.build(cfg, names, n, y_ranges, x_range)
    {l.grid_x, l.w - l.grid_x - l.grid_w, l.grid_y, l.h - l.grid_y - l.grid_h}
  end

  # ── Placement / containers ───────────────────────────────────────────────

  # Static: the panel's bare `<svg>` becomes a nested viewport.
  defp place({:el, "svg", attrs, children}, true, _frame, x, y, w, h) do
    attrs = attrs |> Map.delete(:style) |> Map.merge(%{x: x, y: y, width: w, height: h})
    {:el, "svg", attrs, children}
  end

  # Live: the panel container (its own hook, tooltips and hover zones) is laid
  # over the frame SVG at the panel's position, in percent so it scales with
  # the frame.
  defp place(node, false, frame, x, y, w, h) do
    pct = fn v, total -> "#{fmt(v / total * 100)}%" end

    el(
      "div",
      %{
        class: "eexcharts-trellis-panel",
        style:
          "position:absolute;left:#{pct.(x, frame.w)};top:#{pct.(y, frame.h)};" <>
            "width:#{pct.(w, frame.w)};height:#{pct.(h, frame.h)};"
      },
      node
    )
  end

  defp container(cfg, params, id, children) do
    fixed? = cfg.chart.max_width != false and is_number(cfg.chart.width)
    max_w = if fixed?, do: "max-width:#{fmt(cfg.chart.width)}px;", else: ""

    min_h =
      if fixed? and is_number(cfg.chart.height) and cfg.chart.parent_height_offset > 0,
        do: "min-height:#{fmt(cfg.chart.height + cfg.chart.parent_height_offset)}px;",
        else: ""

    el(
      "div",
      %{
        id: id,
        class: [
          "eexcharts eexcharts-trellis",
          if(params[:class], do: [" ", esc(params[:class])], else: [])
        ],
        style: "position:relative;#{max_w}#{min_h}"
      },
      children
    )
  end

  defp set_attr({:el, tag, attrs, children}, key, value),
    do: {:el, tag, Map.put(attrs, key, value), children}

  defp put_if(opts, nil, _path), do: opts

  defp put_if(opts, value, path) do
    nested = path |> Enum.reverse() |> Enum.reduce(value, fn key, acc -> %{key => acc} end)
    Config.deep_merge(opts, nested)
  end

  defp dim(v, _default) when is_number(v), do: v
  defp dim(_, default), do: default
end
