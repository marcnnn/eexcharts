defmodule EexCharts.Renderer do
  @moduledoc """
  Assembles a complete chart: SVG (grid, axes, series, legend, hover zones)
  plus server-rendered tooltip HTML. Everything the user hovers over is
  rendered here — the JS hook only toggles visibility and positions the
  tooltip box.
  """

  import EexCharts.SVG

  alias EexCharts.{Charts, Config, Layout, Legend}

  # Circular / hierarchical types own their full SVG assembly.
  @standalone_types %{
    radial_bar: Charts.RadialBar,
    radar: Charts.Radar,
    heatmap: Charts.Heatmap,
    treemap: Charts.Treemap
  }

  @doc """
  Renders a chart to iodata (a `<div>` containing the SVG and tooltips).

  Params (map): `:id` (required), `:type`, `:series`, `:categories`,
  `:labels`, `:width`, `:height`, `:options`, `:on_click`, `:push_hover`,
  `:on_legend_click`, `:hidden_series`, `:class`.
  """
  def render(params) do
    type = params[:type] || :line
    id = params[:id] || "eexcharts"
    params = if params[:static], do: staticize_params(params), else: params

    opts =
      (params[:options] || %{})
      |> put_if(params[:width], [:chart, :width])
      |> put_if(params[:height], [:chart, :height])
      |> put_if(params[:categories], [:xaxis, :categories])

    cfg = Config.build(type, opts)
    cfg = if params[:static], do: staticize_cfg(cfg), else: cfg

    cond do
      type in [:pie, :donut, :polar_area] ->
        render_pie(cfg, params, id)

      mod = @standalone_types[type] ->
        mod.render_chart(cfg, params, id)

      true ->
        render_cartesian(cfg, params, id)
    end
  end

  @doc "Set of series indexes hidden via legend toggling."
  def hidden_set(params) do
    MapSet.new(params[:hidden_series] || [])
  end

  # ── Static mode (`EexCharts.to_svg/4`) ───────────────────────────────────
  #
  # Static output goes to a rasterizer, not a browser: there is no hook, no
  # hover, and no CSS. Dropping the interactive params keeps `phx-*` bindings
  # out; disabling the tooltip suppresses everything that exists only for the
  # hook (tooltip HTML, crosshair, hover zones, hover markers).

  defp staticize_params(params) do
    Map.drop(params, [:on_click, :push_hover, :on_legend_click])
  end

  defp staticize_cfg(cfg) do
    cfg
    |> put_in([:tooltip, :enabled], false)
    |> resolve_cfg_vars()
  end

  # Rasterizers render `var(…)` as black (the fallback inside is ignored), so
  # resolve fallbacks to their literals config-wide. Doing it on the config —
  # rather than the emitted SVG — also means `Color.shade/2` sees plain hex
  # and never emits `color-mix()`, which rasterizers can't parse either.
  defp resolve_cfg_vars(%{} = map),
    do: Map.new(map, fn {k, v} -> {k, resolve_cfg_vars(v)} end)

  defp resolve_cfg_vars(list) when is_list(list), do: Enum.map(list, &resolve_cfg_vars/1)
  defp resolve_cfg_vars(value) when is_binary(value), do: EexCharts.Color.resolve_vars(value)
  defp resolve_cfg_vars(value), do: value

  defp put_if(opts, nil, _path), do: opts

  defp put_if(opts, value, path) do
    nested = path |> Enum.reverse() |> Enum.reduce(value, fn key, acc -> %{key => acc} end)
    Config.deep_merge(opts, nested)
  end

  # ── Cartesian (line / area / bar) ────────────────────────────────────────

  defp render_cartesian(cfg, params, id) do
    all_series = normalize_series(params[:series])
    hidden = hidden_set(params)
    series = Enum.reject(all_series, &MapSet.member?(hidden, &1.index))

    names = Enum.map(all_series, & &1.name)
    n = series |> Enum.map(&length(&1.data)) |> Enum.max(fn -> 0 end)
    n = max(n, length(cfg.xaxis.categories))

    {y_min, y_max} = data_range(cfg, series)

    y_axes = Config.yaxes(cfg)

    y_ranges =
      if length(y_axes) > 1 do
        per_axis_y_ranges(cfg, series, y_axes)
      else
        [{y_min, y_max}]
      end

    x_range = if Layout.value_x?(cfg), do: x_value_range(cfg, series, n), else: nil

    l = Layout.build(cfg, names, n, y_ranges, x_range)

    categories = categories(cfg, n)

    bar? = cfg.chart.type == :bar

    series_io =
      case cfg.chart.type do
        :bar ->
          {io, _bars} = Charts.Bar.render(cfg, series, l, on_click: params[:on_click])
          io

        :candlestick ->
          Charts.Candlestick.render(cfg, series, l, on_click: params[:on_click])

        :box_plot ->
          Charts.BoxPlot.render(cfg, series, l, on_click: params[:on_click])

        :range_bar ->
          Charts.RangeBar.render(cfg, series, l, on_click: params[:on_click])

        t when t in [:scatter, :bubble] ->
          Charts.Scatter.render(cfg, series, l, id)

        _ ->
          Charts.Line.render(cfg, series, l, id)
      end

    hover_markers =
      if cfg.chart.type in [:line, :area] and !params[:static],
        do: Charts.Line.hover_markers(cfg, series, l),
        else: []

    # For bar charts the zones sit *behind* the bars, so bars keep their
    # :hover styling and phx-click; the bars themselves carry data-j for the
    # tooltip. For line/area the zones sit on top of everything. Value x-axes
    # (numeric/datetime/scatter) have no category slots, so the markers
    # themselves are the hover targets — no band zones.
    zones = if Layout.value_x?(cfg), do: [], else: hover_zones(cfg, l, params)

    svg =
      svg_open(cfg, l, id, [
        background(cfg, l),
        title(cfg, l),
        grid_lines(cfg, l),
        if(bar?, do: zones, else: []),
        el("g", %{class: "eexcharts-inner"}, series_io),
        data_labels(cfg, series, l),
        EexCharts.Annotations.render(cfg, l),
        axes(cfg, l, categories),
        Legend.render(l.legend, cfg, l,
          hidden: hidden,
          on_click: params[:on_legend_click]
        ),
        hover_markers,
        crosshair(cfg, l),
        if(bar?, do: [], else: zones)
      ])

    container(cfg, params, id, svg, cartesian_tooltips(cfg, series, categories, n))
  end

  @doc """
  Normalizes user series input into `[%{name: binary, data: list, index: i}]`
  where `index` is the series' original position (colors stay stable when
  series are hidden via the legend).
  """
  def normalize_series(nil), do: []

  def normalize_series(series) when is_list(series) do
    if series != [] and Enum.all?(series, &is_number/1) do
      # A bare list of numbers is a single anonymous series.
      [%{name: "series-1", data: series, index: 0}]
    else
      series
      |> Enum.with_index()
      |> Enum.map(fn
        {%{} = s, i} ->
          %{name: to_string(s[:name] || "series-#{i + 1}"), data: s[:data] || [], index: i}

        {other, i} ->
          %{name: "series-#{i + 1}", data: List.wrap(other), index: i}
      end)
    end
  end

  defp data_range(cfg, series) do
    case cfg.chart.type do
      :candlestick -> Charts.Candlestick.data_range(series)
      :box_plot -> Charts.BoxPlot.data_range(series)
      :range_bar -> Charts.RangeBar.data_range(series)
      t when t in [:scatter, :bubble] -> Charts.Scatter.data_range(series)
      _ -> numeric_data_range(cfg, series)
    end
  end

  # Per-y-axis value ranges for multiple y-axes.
  defp per_axis_y_ranges(cfg, series, y_axes) do
    Enum.map(0..(length(y_axes) - 1), fn ai ->
      ys =
        for s <- series,
            Layout.axis_index_for(y_axes, s) == ai,
            {_j, _x, y, _z} <- Layout.series_points(cfg, s.data),
            is_number(y),
            do: y

      case ys do
        [] -> {nil, nil}
        _ -> Enum.min_max(ys)
      end
    end)
  end

  # Overall x-value range for numeric / datetime / scatter x-axes.
  defp x_value_range(cfg, series, n) do
    xs =
      for s <- series,
          {_j, x, _y, _z} <- Layout.series_points(cfg, s.data),
          is_number(x),
          do: x

    case xs do
      [] -> {0, max(n, 1)}
      _ -> Enum.min_max(xs)
    end
  end

  defp numeric_data_range(cfg, series) do
    values =
      if cfg.chart.stacked and cfg.chart.type == :bar do
        # Stacked: extremes are the per-category positive and negative sums.
        n = series |> Enum.map(&length(&1.data)) |> Enum.max(fn -> 0 end)

        Enum.flat_map(0..max(n - 1, 0), fn j ->
          vals = Enum.map(series, fn s -> Enum.at(s.data, j) end) |> Enum.filter(&is_number/1)
          pos = vals |> Enum.filter(&(&1 >= 0)) |> Enum.sum()
          neg = vals |> Enum.filter(&(&1 < 0)) |> Enum.sum()
          [pos, neg]
        end)
      else
        series |> Enum.flat_map(& &1.data) |> Enum.filter(&is_number/1)
      end

    case values do
      [] ->
        {nil, nil}

      _ ->
        {min_v, max_v} = Enum.min_max(values)

        # ApexCharts: bar baselines sit at zero.
        if cfg.chart.type == :bar do
          cond do
            min_v >= 0 -> {0, max_v}
            max_v <= 0 -> {min_v, 0}
            true -> {min_v, max_v}
          end
        else
          {min_v, max_v}
        end
    end
  end

  @doc false
  def categories(cfg, n) do
    case cfg.xaxis.categories do
      [] -> Enum.map(1..max(n, 1), &to_string/1)
      cats -> Enum.map(cats, &to_string/1)
    end
  end

  @doc false
  def svg_open(cfg, l, id, children) do
    el(
      "svg",
      %{
        id: "#{id}-svg",
        viewBox: "0 0 #{fmt(l.w)} #{fmt(l.h)}",
        xmlns: "http://www.w3.org/2000/svg",
        class: "eexcharts-svg",
        font_family: cfg.chart.font_family,
        style: "width:100%;height:auto;display:block;"
      },
      children
    )
  end

  @doc false
  def background(cfg, l) do
    if cfg.chart.background not in [nil, ""] do
      el("rect", %{x: 0, y: 0, width: l.w, height: l.h, fill: cfg.chart.background})
    else
      []
    end
  end

  @doc false
  def title(cfg, l) do
    if cfg.title.text do
      style = cfg.title.style

      {x, anchor} =
        case cfg.title.align do
          :center -> {l.w / 2, "middle"}
          :right -> {l.w - 10, "end"}
          _ -> {10, "start"}
        end

      el(
        "text",
        %{
          x: x + cfg.title.offset_x,
          y: cfg.title.margin + style.font_size + cfg.title.offset_y,
          text_anchor: anchor,
          fill: style.color || cfg.chart.fore_color,
          font_size: style.font_size,
          font_weight: style.font_weight,
          class: "eexcharts-title"
        },
        esc(cfg.title.text)
      )
    else
      []
    end
  end

  defp grid_lines(cfg, l) do
    if cfg.grid.show do
      dash = if cfg.grid.stroke_dash_array > 0, do: cfg.grid.stroke_dash_array

      value_lines =
        if cfg.grid.yaxis_lines do
          Enum.map(l.scale.ticks, fn t ->
            if l.horizontal do
              x = Layout.x_for(l, t)
              grid_line(cfg, x, l.grid_y, x, l.grid_y + l.grid_h, dash)
            else
              y = Layout.y_for(l, t)
              grid_line(cfg, l.grid_x, y, l.grid_x + l.grid_w, y, dash)
            end
          end)
        else
          []
        end

      category_lines =
        cond do
          not cfg.grid.xaxis_lines ->
            []

          l.horizontal ->
            Enum.map(0..(l.n - 1), fn i ->
              p = Layout.category_pos(l, i)
              grid_line(cfg, l.grid_x, p, l.grid_x + l.grid_w, p, dash)
            end)

          true ->
            Enum.map(x_tick_positions(l), fn p ->
              grid_line(cfg, p, l.grid_y, p, l.grid_y + l.grid_h, dash)
            end)
        end

      el("g", %{class: "eexcharts-grid"}, [value_lines, category_lines])
    else
      []
    end
  end

  defp grid_line(cfg, x1, y1, x2, y2, dash) do
    el("line", %{
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      stroke: cfg.grid.border_color,
      stroke_dasharray: dash
    })
  end

  # ── Axes ─────────────────────────────────────────────────────────────────

  defp axes(cfg, l, categories) do
    [
      axis_border(cfg, l),
      value_axis_labels(cfg, l),
      category_axis_labels(cfg, l, categories),
      y_axis_title(cfg, l)
    ]
  end

  defp axis_border(cfg, l) do
    border =
      if cfg.xaxis.axis_border.show do
        el("line", %{
          x1: l.grid_x,
          y1: l.grid_y + l.grid_h,
          x2: l.grid_x + l.grid_w,
          y2: l.grid_y + l.grid_h,
          stroke: cfg.xaxis.axis_border.color,
          stroke_width: cfg.xaxis.axis_border.height
        })
      else
        []
      end

    ticks =
      if cfg.xaxis.axis_ticks.show and not l.horizontal do
        Enum.map(x_tick_positions(l), fn x ->
          el("line", %{
            x1: x,
            y1: l.grid_y + l.grid_h,
            x2: x,
            y2: l.grid_y + l.grid_h + cfg.xaxis.axis_ticks.height,
            stroke: cfg.xaxis.axis_ticks.color
          })
        end)
      else
        []
      end

    [border, ticks]
  end

  # X positions for tick marks / vertical grid lines: scale ticks for a value
  # x-axis, category slots otherwise.
  defp x_tick_positions(%Layout{x_scale: xs} = l) when is_map(xs) do
    Enum.map(xs.ticks, fn %{value: v} -> Layout.x_value_pos(l, v) end)
  end

  defp x_tick_positions(l), do: Enum.map(0..(l.n - 1), fn i -> Layout.category_pos(l, i) end)

  # Value labels: left/right for vertical charts (one group per y-axis;
  # `opposite: true` axes render on the right), bottom for horizontal bars.
  defp value_axis_labels(cfg, l) do
    if l.horizontal do
      horizontal_value_labels(cfg, l)
    else
      labels =
        l.y_axes
        |> Enum.zip(l.scales)
        |> Enum.map(fn {axis, scale} -> vertical_axis_labels(cfg, l, axis, scale) end)

      el("g", %{class: "eexcharts-yaxis-labels"}, labels)
    end
  end

  defp vertical_axis_labels(cfg, l, axis, scale) do
    if axis.show and axis.labels.show do
      style = axis.labels.style
      color = axis_label_color(style.colors, cfg.chart.fore_color)

      {x, anchor} =
        if axis.opposite,
          do: {l.grid_x + l.grid_w + 8, "start"},
          else: {l.grid_x - 8, "end"}

      Enum.map(scale.ticks, fn t ->
        el(
          "text",
          %{
            x: x,
            y: Layout.y_for(l, t, scale),
            text_anchor: anchor,
            dominant_baseline: "central",
            fill: color,
            font_size: style.font_size,
            font_weight: style.font_weight
          },
          esc(Layout.format_y_label(cfg, axis, t))
        )
      end)
    else
      []
    end
  end

  defp horizontal_value_labels(cfg, l) do
    axis = hd(l.y_axes)

    if axis.show and axis.labels.show do
      style = axis.labels.style
      color = axis_label_color(style.colors, cfg.chart.fore_color)

      labels =
        Enum.map(l.scale.ticks, fn t ->
          el(
            "text",
            %{
              x: Layout.x_for(l, t),
              y: l.grid_y + l.grid_h + style.font_size + 8,
              text_anchor: "middle",
              fill: color,
              font_size: style.font_size,
              font_weight: style.font_weight
            },
            esc(Layout.format_y_label(cfg, axis, t))
          )
        end)

      el("g", %{class: "eexcharts-yaxis-labels"}, labels)
    else
      []
    end
  end

  # Value x-axis (numeric / datetime): labels sit at scale-tick positions,
  # placed by x value rather than category slot.
  defp category_axis_labels(cfg, %Layout{x_scale: xs} = l, _categories) when is_map(xs) do
    if cfg.xaxis.labels.show do
      style = cfg.xaxis.labels.style
      color = axis_label_color(style.colors, cfg.chart.fore_color)
      tick_h = if cfg.xaxis.axis_ticks.show, do: cfg.xaxis.axis_ticks.height, else: 0

      labels =
        Enum.map(xs.ticks, fn %{value: v, label: label} ->
          el(
            "text",
            %{
              x: Layout.x_value_pos(l, v),
              y: l.grid_y + l.grid_h + tick_h + style.font_size + 4,
              text_anchor: "middle",
              fill: color,
              font_size: style.font_size,
              font_weight: style.font_weight
            },
            esc(format_x_label(cfg, label))
          )
        end)

      el("g", %{class: "eexcharts-xaxis-labels"}, labels)
    else
      []
    end
  end

  # Category labels: bottom for vertical charts, left for horizontal bars.
  defp category_axis_labels(cfg, l, categories) do
    if cfg.xaxis.labels.show do
      style = cfg.xaxis.labels.style
      color = axis_label_color(style.colors, cfg.chart.fore_color)
      tick_h = if cfg.xaxis.axis_ticks.show, do: cfg.xaxis.axis_ticks.height, else: 0

      max_label_w =
        categories |> Enum.map(&Layout.text_width(&1, style.font_size)) |> Enum.max(fn -> 0 end)

      # Thin labels that would overlap (ApexCharts hideOverlappingLabels).
      step =
        if l.horizontal or l.n <= 1 do
          1
        else
          max(1, ceil(l.n * (max_label_w + 10) / l.grid_w))
        end

      labels =
        categories
        |> Enum.with_index()
        |> Enum.filter(fn {_c, i} -> rem(i, step) == 0 end)
        |> Enum.map(fn {c, i} ->
          text = format_x_label(cfg, c)

          if l.horizontal do
            el(
              "text",
              %{
                x: l.grid_x - 8,
                y: Layout.category_pos(l, i),
                text_anchor: "end",
                dominant_baseline: "central",
                fill: color,
                font_size: style.font_size,
                font_weight: style.font_weight
              },
              esc(text)
            )
          else
            el(
              "text",
              %{
                x: Layout.category_pos(l, i),
                y: l.grid_y + l.grid_h + tick_h + style.font_size + 4,
                text_anchor: "middle",
                fill: color,
                font_size: style.font_size,
                font_weight: style.font_weight
              },
              esc(text)
            )
          end
        end)

      el("g", %{class: "eexcharts-xaxis-labels"}, labels)
    else
      []
    end
  end

  defp format_x_label(cfg, c) do
    case cfg.xaxis.labels.formatter do
      f when is_function(f, 1) -> to_string(f.(c))
      _ -> to_string(c)
    end
  end

  defp axis_label_color(nil, fore), do: fore
  defp axis_label_color([], fore), do: fore
  defp axis_label_color([c | _], _fore), do: c
  defp axis_label_color(c, _fore) when is_binary(c), do: c

  defp y_axis_title(cfg, l) do
    Enum.map(l.y_axes, fn axis -> one_y_axis_title(cfg, l, axis) end)
  end

  defp one_y_axis_title(cfg, l, axis) do
    if axis.title.text do
      style = axis.title.style
      x = if axis.opposite, do: l.w - style.font_size, else: style.font_size
      y = l.grid_y + l.grid_h / 2
      rotate = if axis.opposite, do: 90, else: -90

      el(
        "text",
        %{
          x: x,
          y: y,
          transform: "rotate(#{rotate} #{fmt(x)} #{fmt(y)})",
          text_anchor: "middle",
          fill: style.color || cfg.chart.fore_color,
          font_size: style.font_size,
          font_weight: style.font_weight
        },
        esc(axis.title.text)
      )
    else
      []
    end
  end

  # ── Data labels ──────────────────────────────────────────────────────────

  defp data_labels(cfg, series, l) do
    if cfg.data_labels.enabled do
      case cfg.chart.type do
        :bar -> bar_data_labels(cfg, series, l)
        _ -> point_data_labels(cfg, series, l)
      end
    else
      []
    end
  end

  defp bar_data_labels(cfg, series, l) do
    dl = cfg.data_labels
    position = cfg.plot_options.bar.data_labels.position

    labels =
      cfg
      |> Charts.Bar.positions(series, l)
      |> Enum.reject(&(&1.h == 0 and &1.w == 0))
      |> Enum.map(fn r ->
        {x, y} =
          cond do
            l.horizontal and position == :center -> {r.x + r.w / 2, r.y + r.h / 2}
            l.horizontal -> {r.x + r.w - 10, r.y + r.h / 2}
            true -> bar_label_pos(position, r, dl)
          end

        el(
          "text",
          %{
            x: x + dl.offset_x,
            y: y + dl.offset_y,
            text_anchor: "middle",
            dominant_baseline: "central",
            fill: data_label_color(dl, r.series, r.color),
            font_size: dl.style.font_size,
            font_weight: dl.style.font_weight,
            class: "eexcharts-datalabel"
          },
          esc(format_data_label(cfg, r.value))
        )
      end)

    el("g", %{class: "eexcharts-datalabels"}, labels)
  end

  # For a vertical bar the position names an edge of the rect, not the end the
  # value sits at. The top edge of a bar hanging below zero is the zero line,
  # so :top and :bottom stay distinct on either side of zero.
  defp bar_label_pos(:center, r, _dl), do: {r.x + r.w / 2, r.y + r.h / 2}
  defp bar_label_pos(:bottom, r, _dl), do: {r.x + r.w / 2, r.y + r.h - 4}
  defp bar_label_pos(_top, r, dl), do: {r.x + r.w / 2, r.y + dl.style.font_size}

  defp point_data_labels(cfg, series, l) do
    dl = cfg.data_labels

    labels =
      Enum.flat_map(series, fn s ->
        i = s.index
        color = Config.color_at(cfg, i)

        s.data
        |> Enum.with_index()
        |> Enum.filter(fn {v, _j} -> is_number(v) end)
        |> Enum.map(fn {v, j} ->
          x = Layout.category_pos(l, j) + dl.offset_x
          y = Layout.y_for(l, v) - 10 + dl.offset_y
          text = format_data_label(cfg, v)

          pill =
            if dl.background.enabled do
              tw = Layout.text_width(text, dl.style.font_size)
              pad = dl.background.padding

              el("rect", %{
                x: x - tw / 2 - pad,
                y: y - dl.style.font_size / 2 - pad,
                width: tw + pad * 2,
                height: dl.style.font_size + pad * 2,
                rx: dl.background.border_radius,
                fill: color,
                fill_opacity: dl.background.opacity,
                stroke: dl.background.border_color,
                stroke_width: dl.background.border_width
              })
            else
              []
            end

          text_color =
            if dl.background.enabled,
              do: dl.background.fore_color,
              else: data_label_color(dl, i, color)

          [
            pill,
            el(
              "text",
              %{
                x: x,
                y: y,
                text_anchor: "middle",
                dominant_baseline: "central",
                fill: text_color,
                font_size: dl.style.font_size,
                font_weight: dl.style.font_weight,
                class: "eexcharts-datalabel"
              },
              esc(text)
            )
          ]
        end)
      end)

    el("g", %{class: "eexcharts-datalabels"}, labels)
  end

  defp data_label_color(dl, i, fallback) do
    case dl.style.colors do
      nil -> fallback
      [] -> fallback
      colors -> Enum.at(colors, rem(i, length(colors))) || fallback
    end
  end

  defp format_data_label(cfg, v) do
    case cfg.data_labels.formatter do
      f when is_function(f, 1) -> to_string(f.(v))
      _ -> fmt_value(v)
    end
  end

  # ── Hover zones, crosshair, tooltips ─────────────────────────────────────

  defp hover_zones(cfg, l, params) do
    if cfg.tooltip.enabled or params[:on_click] do
      zones =
        Enum.map(0..(l.n - 1), fn j ->
          pos = Layout.category_pos(l, j)

          attrs =
            if l.horizontal do
              slot = l.grid_h / l.n

              %{
                x: l.grid_x,
                y: l.grid_y + slot * j,
                width: l.grid_w,
                height: slot,
                data_cy: pos
              }
            else
              slot =
                if l.tick_placement == :between or l.n == 1,
                  do: l.grid_w / l.n,
                  else: l.grid_w / max(l.n - 1, 1)

              x = max(pos - slot / 2, l.grid_x)
              x_end = min(pos + slot / 2, l.grid_x + l.grid_w)

              %{
                x: x,
                y: l.grid_y,
                width: x_end - x,
                height: l.grid_h,
                data_cx: pos
              }
            end

          attrs =
            Map.merge(attrs, %{
              class: "eexcharts-zone",
              data_j: j,
              fill: "transparent"
            })

          attrs = maybe_click(attrs, params, j)
          el("rect", attrs)
        end)

      el("g", %{class: "eexcharts-zones"}, zones)
    else
      []
    end
  end

  defp maybe_click(attrs, params, j) do
    if params[:on_click] do
      Map.merge(attrs, %{
        "phx-click" => params[:on_click],
        "phx-value-index" => j,
        cursor: "pointer"
      })
    else
      attrs
    end
  end

  defp crosshair(cfg, l) do
    if cfg.tooltip.enabled do
      if l.horizontal do
        el("line", %{
          class: "eexcharts-crosshair",
          x1: l.grid_x,
          x2: l.grid_x + l.grid_w,
          y1: 0,
          y2: 0,
          stroke: "#b6b6b6",
          stroke_dasharray: 3
        })
      else
        el("line", %{
          class: "eexcharts-crosshair",
          x1: 0,
          x2: 0,
          y1: l.grid_y,
          y2: l.grid_y + l.grid_h,
          stroke: "#b6b6b6",
          stroke_dasharray: 3
        })
      end
    else
      []
    end
  end

  defp cartesian_tooltips(cfg, series, categories, n) do
    if cfg.tooltip.enabled and n > 0 do
      tips =
        Enum.map(0..(n - 1), fn j ->
          title = Enum.at(categories, j, to_string(j + 1))
          title = format_tooltip_x(cfg, title)

          rows =
            Enum.map(series, fn s ->
              v = Enum.at(s.data, j)

              if v == nil do
                []
              else
                tooltip_row(Config.color_at(cfg, s.index), s.name, tooltip_value(cfg, v))
              end
            end)

          el("div", %{class: "eexcharts-tip", data_j: j, hidden: true}, [
            el("div", %{class: "eexcharts-tip-title"}, esc(title)),
            rows
          ])
        end)

      tooltip_container(cfg, tips)
    else
      []
    end
  end

  @doc false
  def tooltip_row(color, label, value) do
    el("div", %{class: "eexcharts-tip-row"}, [
      el("span", %{class: "eexcharts-tip-marker", style: "background:#{color}"}, ""),
      el("span", %{class: "eexcharts-tip-label"}, [esc(label), ": "]),
      el("span", %{class: "eexcharts-tip-value"}, esc(value))
    ])
  end

  @doc false
  def tooltip_container(cfg, tips) do
    el(
      "div",
      %{
        class: tooltip_class(cfg.tooltip.theme),
        data_theme: tooltip_data_theme(cfg.tooltip.theme),
        style: "font-size:#{fmt(cfg.tooltip.style.font_size)}px"
      },
      tips
    )
  end

  # daisyUI selects its own themes with `data-theme`, so the daisy tooltip is
  # picked out by class and leaves the attribute off — that way the tooltip
  # inherits whichever daisyUI theme is active on an ancestor instead of
  # declaring one of its own.
  defp tooltip_class(:daisy), do: "eexcharts-tooltip eexcharts-tooltip-daisy"
  defp tooltip_class(_theme), do: "eexcharts-tooltip"

  defp tooltip_data_theme(:daisy), do: nil
  defp tooltip_data_theme(theme), do: theme

  # Structured data points (OHLC, ranges) format their own tooltip values.
  defp tooltip_value(cfg, v) do
    case cfg.chart.type do
      :candlestick -> Charts.Candlestick.tooltip_value(cfg, v)
      :box_plot -> Charts.BoxPlot.tooltip_value(cfg, v)
      :range_bar -> Charts.RangeBar.tooltip_value(cfg, v)
      t when t in [:scatter, :bubble] -> Charts.Scatter.tooltip_value(cfg, v)
      _ -> format_tooltip_y(cfg, point_y(v))
    end
  end

  # Tolerate `[x, y]` / `%{x:, y:}` data points on plain cartesian charts.
  defp point_y([_x, y | _]), do: y
  defp point_y(%{y: y}), do: y
  defp point_y(v), do: v

  @doc false
  def format_tooltip_x(cfg, title) do
    case cfg.tooltip.x_formatter do
      f when is_function(f, 1) -> to_string(f.(title))
      _ -> title
    end
  end

  @doc false
  def format_tooltip_y(cfg, v) do
    case cfg.tooltip.y_formatter do
      f when is_function(f, 1) -> to_string(f.(v))
      _ -> fmt_value(v)
    end
  end

  # ── Pie / donut ──────────────────────────────────────────────────────────

  defp render_pie(cfg, params, id) do
    {all_values, all_labels} = pie_values_labels(cfg, params)
    hidden = hidden_set(params)

    {values, labels, indices} =
      all_values
      |> Enum.with_index()
      |> Enum.reject(fn {_v, i} -> MapSet.member?(hidden, i) end)
      |> Enum.map(fn {v, i} -> {v, Enum.at(all_labels, i), i} end)
      |> Enum.reduce({[], [], []}, fn {v, lab, i}, {vs, ls, is} ->
        {[v | vs], [lab | ls], [i | is]}
      end)
      |> then(fn {vs, ls, is} -> {Enum.reverse(vs), Enum.reverse(ls), Enum.reverse(is)} end)

    w = if is_number(cfg.chart.width), do: cfg.chart.width, else: 600
    h = if is_number(cfg.chart.height), do: cfg.chart.height, else: 350

    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    legend = Legend.measure(cfg, all_labels, w, h)

    {box_w, box_h} =
      case legend.position do
        :right -> {w - legend.w, h - title_h}
        pos when pos in [:bottom, :top] -> {w, h - title_h - legend.h}
        _ -> {w, h - title_h}
      end

    geo = Charts.Pie.geometry(cfg, values, labels, box_w, box_h, indices: indices)

    geo =
      case legend.position do
        :top -> %{geo | cy: geo.cy + title_h + legend.h}
        _ -> %{geo | cy: geo.cy + title_h}
      end

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

    pie_io = Charts.Pie.render(cfg, geo, on_click: params[:on_click])

    svg =
      svg_open(cfg, l, id, [
        background(cfg, l),
        title(cfg, l),
        pie_io,
        Legend.render(legend, cfg, l,
          hidden: hidden,
          on_click: params[:on_legend_click]
        )
      ])

    container(cfg, params, id, svg, pie_tooltips(cfg, geo))
  end

  defp pie_values_labels(cfg, params) do
    values =
      case params[:series] do
        [%{data: data} | _] -> data
        list when is_list(list) -> list
        _ -> []
      end

    values = Enum.filter(values, &is_number/1)

    labels =
      (params[:labels] || cfg.xaxis.categories || [])
      |> Enum.map(&to_string/1)

    labels =
      if length(labels) < length(values) do
        labels ++ Enum.map((length(labels) + 1)..length(values), &"series-#{&1}")
      else
        labels
      end

    {values, labels}
  end

  defp pie_tooltips(cfg, geo) do
    if cfg.tooltip.enabled do
      tips =
        Enum.map(geo.slices, fn s ->
          el("div", %{class: "eexcharts-tip", data_j: s.index, hidden: true}, [
            tooltip_row(s.color, s.label, format_tooltip_y(cfg, s.value))
          ])
        end)

      tooltip_container(cfg, tips)
    else
      []
    end
  end

  # ── Container ────────────────────────────────────────────────────────────

  # Static mode wants the bare `<svg>`: no wrapper div, no hook, no tooltip
  # HTML. The `data-j`/`data-cx`/`data-cy` hover-lookup attributes are emitted
  # unconditionally by the chart modules, so they are stripped here instead of
  # threading a flag through every one of them. Safe as a regex because `el/3`
  # escapes `"` inside attribute values.
  @doc false
  def container(_cfg, %{static: true}, _id, svg, _tooltips) do
    svg
    |> IO.iodata_to_binary()
    |> String.replace(~r/ data-(?:j|cx|cy)="[^"]*"/, "")
  end

  def container(cfg, params, id, svg, tooltips) do
    max_w = if is_number(cfg.chart.width), do: "max-width:#{fmt(cfg.chart.width)}px;", else: ""

    el(
      "div",
      %{
        id: id,
        class: ["eexcharts", if(params[:class], do: [" ", esc(params[:class])], else: [])],
        "phx-hook": if(params[:hook] == false, do: nil, else: "EexCharts"),
        "phx-update": "replace",
        data_push_hover: params[:push_hover] || nil,
        style: "position:relative;#{max_w}"
      },
      [svg, tooltips]
    )
  end
end
