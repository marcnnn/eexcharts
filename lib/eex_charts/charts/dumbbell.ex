defmodule EexCharts.Charts.Dumbbell do
  @moduledoc """
  Dumbbell charts: two values per category joined by a line, with a dot at
  each end. Ported from ApexCharts v4.7.0 `plotOptions.bar.isDumbbell`, which
  turns a range bar into a thin bar with a round "goal" marker at both ends.

  ## Usage

      EexCharts.chart(id: "d", type: :dumbbell,
        series: [%{name: "Salary", ends: ["2015", "2025"],
                   data: [%{x: "Design", y: [42, 61]}, %{x: "Ops", y: [38, 45]}]}])

  Data is the range-bar shape: `[[from, to], ...]` or
  `[%{x: label, y: [from, to]}, ...]` (the `x` labels become the categories
  when none are given). `plot_options.bar.horizontal: true` lays the
  dumbbells out sideways. `type: :dumbbell` is shorthand for `:range_bar`
  with `plot_options.bar.is_dumbbell: true`.

  ## Options

    * `plot_options.bar.is_dumbbell` (`false`) — draw range bars as dumbbells.
    * `plot_options.bar.dumbbell_colors` — the end colours, as in v4.7.0: a
      list indexed by series whose entries are a colour (both ends) or a
      `[start, end]` pair. `nil` (the v4.7.0 default) uses the series colour
      for both ends; `:pairs` (the `:dumbbell` shorthand default) gives series
      `i` the palette colours `2i` and `2i + 1`, so the ends are told apart.
    * `plot_options.bar.column_width` / `bar_height` — connector thickness: a
      number is pixels (v4.7.0 sets `2` for dumbbells), a `"n%"` string is a
      share of the series' slot.
    * `markers.size` — dot radius (dumbbell default `6`); `markers.stroke_colors`
      / `markers.stroke_width` outline the dots.
    * `stroke.colors` — connector colour per series (falls back to the series
      colour; the shorthand uses a neutral grey).

  ## Legend

  A series with `ends: [start_label, end_label]` contributes one legend item
  per end, each in its end colour. `legend.custom_legend_items` (with
  `legend.markers.fill_colors`) replaces the legend outright. Otherwise the
  legend lists series names, marked with each series' end colour.
  """

  import EexCharts.SVG

  alias EexCharts.{Charts, Config, Layout}

  @doc "Config applied when `is_dumbbell` is on (ApexCharts `Defaults.dumbbell()`)."
  def defaults do
    %{
      plot_options: %{bar: %{bar_height: 2, column_width: 2}},
      markers: %{size: 6, stroke_colors: "#fff", stroke_width: 2}
    }
  end

  @doc "Extra defaults for the `type: :dumbbell` shorthand."
  def alias_defaults do
    %{
      plot_options: %{bar: %{is_dumbbell: true, dumbbell_colors: :pairs}},
      stroke: %{colors: ["#b6b6b6"]},
      legend: %{show_for_single_series: true, markers: %{shape: :circle}}
    }
  end

  @doc "`{start_color, end_color}` for series `i`."
  def end_colors(cfg, i) do
    case cfg.plot_options.bar.dumbbell_colors do
      nil ->
        {Config.color_at(cfg, i), Config.color_at(cfg, i)}

      :pairs ->
        {Config.color_at(cfg, 2 * i), Config.color_at(cfg, 2 * i + 1)}

      list when is_list(list) ->
        case Config.color_for(list, i) do
          [a, b | _] -> {a, b}
          c -> {c, c}
        end

      c when is_binary(c) ->
        {c, c}
    end
  end

  @doc """
  Fills in the legend for dumbbells: items for series `ends`, and marker
  colours matching the dots. Explicit legend options win.
  """
  def legend_config(cfg, raw_series) do
    series = if is_list(raw_series), do: Enum.filter(raw_series, &is_map/1), else: []
    custom? = match?([_ | _], cfg.legend.custom_legend_items)

    {items, colors} =
      series
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, i} ->
        {c0, c1} = end_colors(cfg, i)

        case s[:ends] do
          [a, b | _] -> [{to_string(a), c0}, {to_string(b), c1}]
          _ -> [{to_string(s[:name] || "series-#{i + 1}"), c1}]
        end
      end)
      |> Enum.unzip()

    any_ends? = Enum.any?(series, &match?([_, _ | _], &1[:ends]))

    cfg =
      if not custom? and any_ends?,
        do: put_in(cfg, [:legend, :custom_legend_items], items),
        else: cfg

    cond do
      cfg.legend.markers.fill_colors != nil ->
        cfg

      custom? ->
        # One item per end, in series order.
        n = length(cfg.legend.custom_legend_items)

        fill =
          Enum.map(0..(n - 1)//1, fn k ->
            {c0, c1} = end_colors(cfg, div(k, 2))
            if rem(k, 2) == 0, do: c0, else: c1
          end)

        put_in(cfg, [:legend, :markers, :fill_colors], fill)

      true ->
        put_in(cfg, [:legend, :markers, :fill_colors], colors)
    end
  end

  @doc "Renders dumbbell series into the cartesian grid."
  def render(cfg, series, %Layout{} = l, opts \\ []) do
    on_click = opts[:on_click]

    series
    |> positions(cfg, l)
    |> Enum.group_by(& &1.series)
    |> Enum.sort_by(fn {i, _} -> i end)
    |> Enum.map(fn {i, dbs} ->
      line_color = Config.color_for(cfg.stroke.colors, i) || Config.color_at(cfg, i)
      r = Config.color_for(cfg.markers.size, i) || 6
      dot_stroke = Config.color_for(cfg.markers.stroke_colors, i)
      dot_stroke_w = cfg.markers.stroke_width

      el(
        "g",
        %{class: "eexcharts-series eexcharts-dumbbell"},
        Enum.map(dbs, fn d ->
          click =
            if on_click,
              do: %{
                "phx-click" => on_click,
                "phx-value-index" => d.index,
                "phx-value-series" => d.series,
                cursor: "pointer"
              },
              else: %{}

          dot = fn {x, y}, color, which ->
            el(
              "circle",
              Map.merge(
                %{
                  class: "eexcharts-dumbbell-dot eexcharts-dumbbell-#{which}",
                  data_j: d.index,
                  cx: x,
                  cy: y,
                  r: r,
                  fill: color,
                  stroke: dot_stroke,
                  stroke_width: if(dot_stroke, do: dot_stroke_w)
                },
                click
              )
            )
          end

          {x1, y1} = d.from
          {x2, y2} = d.to

          el("g", %{class: "eexcharts-bar", data_j: d.index}, [
            el("line", %{
              class: "eexcharts-dumbbell-line",
              x1: x1,
              y1: y1,
              x2: x2,
              y2: y2,
              stroke: line_color,
              stroke_width: d.thickness,
              stroke_linecap: "round"
            }),
            dot.(d.from, d.start_color, "start"),
            dot.(d.to, d.end_color, "end")
          ])
        end)
      )
    end)
  end

  @doc """
  One entry per data point: `%{series, index, from: {x, y}, to: {x, y},
  thickness, start_color, end_color}` in SVG coordinates.
  """
  def positions(series, cfg, %Layout{} = l) do
    n_series = max(length(series), 1)
    bar = cfg.plot_options.bar

    {slot, thickness_opt} =
      if l.horizontal,
        do: {l.grid_h / l.n, bar.bar_height},
        else: {l.grid_w / l.n, bar.column_width}

    sub = slot * 0.7 / n_series

    thickness =
      if is_number(thickness_opt),
        do: thickness_opt,
        else: sub * Charts.Bar.pct(thickness_opt) / 100

    series
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, pos_i} ->
      {c0, c1} = end_colors(cfg, s.index)
      offset = slot * 0.15 + sub * (pos_i + 0.5)

      s.data
      |> Enum.with_index()
      |> Enum.flat_map(fn {p, j} ->
        case Charts.RangeBar.range(p) do
          [from, to] when is_number(from) and is_number(to) ->
            {a, b} =
              if l.horizontal do
                c = l.grid_y + slot * j + offset
                {{Layout.x_for(l, clamp(l, from)), c}, {Layout.x_for(l, clamp(l, to)), c}}
              else
                c = l.grid_x + slot * j + offset
                {{c, Layout.y_for(l, clamp(l, from))}, {c, Layout.y_for(l, clamp(l, to))}}
              end

            [
              %{
                series: s.index,
                index: j,
                from: a,
                to: b,
                thickness: thickness,
                start_color: c0,
                end_color: c1
              }
            ]

          _ ->
            []
        end
      end)
    end)
  end

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)
end
