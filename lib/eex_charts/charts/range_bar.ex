defmodule EexCharts.Charts.RangeBar do
  @moduledoc """
  Range bar / column series rendering, ported from ApexCharts `Bar.js` with
  range (`[from, to]`) values.

  Data shape: `[[from, to], ...]` or `[%{x: label, y: [from, to]}, ...]`
  (categories come from the x-axis). Each bar spans `from`..`to` rather than
  a zero baseline. Vertical columns are grouped side-by-side in the category
  slot (`slot / series_count * column_width%`); when the layout is horizontal
  (`plot_options.bar.horizontal`), bars run from `x_for(from)` to `x_for(to)`
  using `bar_height%`. `plot_options.bar.border_radius` rounds both ends,
  reusing `Charts.Bar.bar_path/3`. Data points may carry `goals` (see
  `EexCharts.Goals`).

  ## Rows

  A `%{x: label}` point is drawn in the row (category slot) of its label, so
  several points sharing an `x` sit in one row, as in ApexCharts' timeline
  (`RangeBar.js` / `Data.handleRangeDataFormat`). Without `xaxis.categories`
  the rows are the distinct `x` labels in order of appearance. Points without
  an `x`, or with one that names no category, keep the slot of their index.

    * `plot_options.bar.range_bar_group_rows` (default `false`): every series
      draws into the full row instead of its own lane in it.
    * `plot_options.bar.range_bar_overlap` (default `true`): overlapping
      ranges in one row and series are drawn over each other; `false` splits
      the bar thickness between them.

  ## Timeline (datetime ranges)

  With `xaxis.type: :datetime` on a horizontal chart, `from` and `to` may be
  `Date`, `DateTime`, `NaiveDateTime`, ISO 8601 strings or unix
  milliseconds. The value axis becomes a time scale spanning the data
  (`xaxis.min` / `xaxis.max` bound it) and the rows stay down the left.

  ## Data labels

  `data_labels.enabled: true` labels each bar with the point's `label` when
  it has one, else `data_labels.formatter` (given `[from, to]`), else the
  range length `to - from` (ApexCharts' range bar default).
  `plot_options.bar.data_labels.position` places them:

    * `:center` (the range bar default), `:top` (inside the `to` end) and
      `:bottom` (inside the `from` end) draw on the bar in the on-mark label
      colour; labels wider than the bar are dropped unless
      `plot_options.bar.data_labels.hide_overflowing_labels` is `false`.
    * `:outside_end` draws past the bar's end (right of a bar, above a column)
      in `chart.fore_color`, since the label sits on the page. Horizontal
      layouts grow the right padding so the widest label stays inside the
      chart.
  """

  import EexCharts.SVG

  alias EexCharts.{Charts, Config, DataLabels, Goals, Layout, PointStyle, TimeScale}

  # Gap between a bar end and an `:outside_end` label, and between an inside
  # label and the bar edge it is anchored to.
  @label_gap 6

  @doc "Renders range bar series into the cartesian grid."
  def render(cfg, series, l, opts \\ [])

  def render(%{plot_options: %{bar: %{is_dumbbell: true}}} = cfg, series, %Layout{} = l, opts) do
    Charts.Dumbbell.render(cfg, series, l, opts)
  end

  def render(cfg, series, %Layout{} = l, opts) do
    on_click = opts[:on_click]
    {rects, defs} = cfg |> positions(series, l) |> PointStyle.link(opts[:id] || "eexcharts")

    rects
    |> Enum.group_by(& &1.series)
    |> Enum.sort_by(fn {i, _} -> i end)
    |> Enum.map(fn {_i, rects} ->
      el(
        "g",
        %{class: "eexcharts-series"},
        Enum.map(rects, fn r ->
          attrs = %{
            class: Enum.join(["eexcharts-bar" | List.wrap(r.style.class)], " "),
            data_j: r.row,
            d: Charts.Bar.bar_path(cfg, r, l.horizontal),
            fill: r.style.fill,
            fill_opacity: r.style.fill_opacity,
            stroke: r.style.stroke || stroke_color(cfg, r.series, r.color),
            stroke_width: r.style.stroke_width
          }

          attrs =
            if on_click do
              Map.merge(attrs, %{
                "phx-click" => on_click,
                "phx-value-index" => r.index,
                "phx-value-series" => r.series,
                cursor: "pointer"
              })
            else
              attrs
            end

          el("path", attrs)
        end)
      )
    end)
    |> then(&[defs, &1, Goals.render(cfg, series, rects, l)])
  end

  defp positions(cfg, series, %Layout{horizontal: true} = l) do
    rows = row_index(cfg)
    {n_series, lane_of} = series_lanes(cfg, series)
    slot = l.grid_h / l.n
    bar_h = slot / max(n_series, 1) * pct(cfg.plot_options.bar.bar_height) / 100

    series
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, pos_i} ->
      pos_i = lane_of.(pos_i)
      color = Config.color_at(cfg, s.index)
      group_y = fn j -> l.grid_y + slot * j + (slot - bar_h * n_series) / 2 end
      split = overlap_split(cfg, s, rows)

      s.data
      |> Enum.with_index()
      |> Enum.flat_map(fn {p, j} ->
        case range(p) do
          [from, to] ->
            x_from = Layout.x_for(l, clamp(l, from))
            x_to = Layout.x_for(l, clamp(l, to))
            row = row_of(rows, p, j)
            {lane, lanes} = Map.get(split, j, {0, 1})
            h = bar_h / lanes

            [
              %{
                series: s.index,
                index: j,
                row: row,
                point: p,
                x: min(x_from, x_to),
                y: group_y.(row) + bar_h * pos_i + h * lane,
                w: abs(x_to - x_from),
                h: h,
                color: color,
                positive: to >= from,
                last_in_stack: true,
                style: PointStyle.resolve(cfg, s, p, color)
              }
            ]

          nil ->
            []
        end
      end)
    end)
  end

  defp positions(cfg, series, l) do
    rows = row_index(cfg)
    {n_series, lane_of} = series_lanes(cfg, series)
    slot = l.grid_w / l.n
    bar_w = slot / max(n_series, 1) * pct(cfg.plot_options.bar.column_width) / 100

    series
    |> Enum.with_index()
    |> Enum.flat_map(fn {s, pos_i} ->
      pos_i = lane_of.(pos_i)
      color = Config.color_at(cfg, s.index)
      group_x = fn j -> l.grid_x + slot * j + (slot - bar_w * n_series) / 2 end
      split = overlap_split(cfg, s, rows)

      s.data
      |> Enum.with_index()
      |> Enum.flat_map(fn {p, j} ->
        case range(p) do
          [from, to] ->
            y_from = Layout.y_for(l, clamp(l, from))
            y_to = Layout.y_for(l, clamp(l, to))
            row = row_of(rows, p, j)
            {lane, lanes} = Map.get(split, j, {0, 1})
            w = bar_w / lanes

            [
              %{
                series: s.index,
                index: j,
                row: row,
                point: p,
                x: group_x.(row) + bar_w * pos_i + w * lane,
                y: min(y_from, y_to),
                w: w,
                h: abs(y_from - y_to),
                color: color,
                positive: to >= from,
                last_in_stack: true,
                style: PointStyle.resolve(cfg, s, p, color)
              }
            ]

          nil ->
            []
        end
      end)
    end)
  end

  # ── Rows ───────────────────────────────────────────────────────────────────

  @doc """
  Prepares range bar series before layout: on a timeline (horizontal,
  `xaxis.type: :datetime`) range ends become unix ms, and without
  `xaxis.categories` the distinct point `x` labels become the rows.
  Returns `{cfg, series}`.
  """
  def prepare(cfg, series) do
    series =
      if timeline?(cfg),
        do: Enum.map(series, fn s -> %{s | data: Enum.map(s.data, &ms_point/1)} end),
        else: series

    {put_row_categories(cfg, series), series}
  end

  @doc """
  Number of category slots: the category count when every point names its
  row with an `x`, otherwise `n` (the longest series).
  """
  def row_count(cfg, series, n) do
    rows = row_index(cfg)

    keyed? =
      rows != %{} and
        Enum.all?(series, fn s ->
          Enum.all?(s.data, &match?(%{x: x} when x != nil, &1)) and
            Enum.all?(s.data, &Map.has_key?(rows, to_string(&1.x)))
        end)

    if keyed?, do: length(cfg.xaxis.categories), else: n
  end

  defp timeline?(cfg), do: Layout.horizontal?(cfg) and cfg.xaxis.type == :datetime

  defp ms_point(%{y: [from, to | rest]} = p), do: %{p | y: [ms(from), ms(to) | rest]}
  defp ms_point([from, to | rest]), do: [ms(from), ms(to) | rest]
  defp ms_point(p), do: p

  defp ms(nil), do: nil
  defp ms(v), do: TimeScale.to_ms(v)

  defp put_row_categories(%{xaxis: %{categories: [_ | _]}} = cfg, _series), do: cfg

  defp put_row_categories(cfg, series) do
    labels =
      for s <- series, %{x: x} <- s.data, x != nil, uniq: true, do: x

    if labels == [], do: cfg, else: put_in(cfg, [:xaxis, :categories], labels)
  end

  # Category label -> slot, first occurrence wins.
  defp row_index(cfg) do
    cfg.xaxis.categories
    |> Enum.with_index()
    |> Enum.reverse()
    |> Map.new(fn {c, i} -> {to_string(c), i} end)
  end

  defp row_of(rows, %{x: x}, j) when x != nil, do: Map.get(rows, to_string(x), j)
  defp row_of(_rows, _p, j), do: j

  # Lanes per row and the lane of the series at position `pos_i`: one lane
  # per series, or a single shared one with `range_bar_group_rows`.
  defp series_lanes(cfg, series) do
    if Map.get(cfg.plot_options.bar, :range_bar_group_rows, false),
      do: {1, fn _pos_i -> 0 end},
      else: {length(series), & &1}
  end

  # `range_bar_overlap: false`: point index -> `{lane, lanes}` for the points
  # of one series whose ranges overlap another range in the same row. Like
  # `Data.handleRangeData`, every overlapping range of a row shares the split.
  defp overlap_split(cfg, s, rows) do
    if Map.get(cfg.plot_options.bar, :range_bar_overlap, true) do
      %{}
    else
      s.data
      |> Enum.with_index()
      |> Enum.flat_map(fn {p, j} ->
        case range(p) do
          [a, b] when is_number(a) and is_number(b) ->
            [{row_of(rows, p, j), j, min(a, b), max(a, b)}]

          _ ->
            []
        end
      end)
      |> Enum.group_by(&elem(&1, 0))
      |> Enum.flat_map(fn {_row, ranges} ->
        overlapping =
          Enum.filter(ranges, fn {_, j, a, b} ->
            Enum.any?(ranges, fn {_, k, c, d} -> k != j and a <= d and c <= b end)
          end)

        lanes = length(overlapping)

        overlapping
        |> Enum.with_index()
        |> Enum.map(fn {{_, j, _, _}, lane} -> {j, {lane, lanes}} end)
      end)
      |> Map.new()
    end
  end

  # ── Data labels ────────────────────────────────────────────────────────────

  @doc "Data labels for range bars; see the moduledoc for text and placement."
  def data_labels(cfg, series, l) do
    dl = cfg.data_labels
    bar_dl = cfg.plot_options.bar.data_labels
    position = bar_dl.position
    hide_overflow = Map.get(bar_dl, :hide_overflowing_labels, true)
    fs = dl.style.font_size
    metrics = Layout.metrics(cfg, dl.style)

    labels =
      cfg
      |> positions(series, l)
      |> Enum.flat_map(fn r ->
        text = label_text(cfg, r)
        tw = Layout.text_width(text, fs, metrics)
        {x, y, anchor} = label_place(position, r, l.horizontal, fs)

        if position != :outside_end and hide_overflow and tw > r.w do
          []
        else
          value = range(r.point)
          x = x + DataLabels.offset(dl.offset_x, value, r.series, r.index)
          y = y + DataLabels.offset(dl.offset_y, value, r.series, r.index)

          color =
            if position == :outside_end,
              do: cfg.chart.fore_color,
              else: PointStyle.label_color(cfg, r.style, on_mark_color(dl, r))

          node =
            el(
              "text",
              %{
                x: x,
                y: y,
                text_anchor: anchor,
                dominant_baseline: "central",
                fill: color,
                font_family: dl.style.font_family,
                font_size: fs,
                font_weight: dl.style.font_weight,
                class: "eexcharts-datalabel"
              },
              esc(text)
            )

          [{r.series, DataLabels.box(box_center(x, tw, anchor), y, text, fs, metrics), node}]
        end
      end)

    labels = if dl.hide_overlapping, do: DataLabels.hide_overlapping(labels), else: labels
    el("g", %{class: "eexcharts-datalabels"}, Enum.map(labels, &elem(&1, 2)))
  end

  @doc """
  Grows the right padding so `:outside_end` labels of a horizontal chart end
  inside the SVG. `build` re-runs the layout for a config; returns
  `{cfg, layout}`.
  """
  def fit_labels(cfg, series, %Layout{horizontal: true} = l, build) do
    if cfg.data_labels.enabled and cfg.plot_options.bar.data_labels.position == :outside_end and
         not cfg.plot_options.bar.is_dumbbell do
      grow = label_overflow(cfg, series, l)

      if grow > 0 do
        cfg = update_in(cfg, [:grid, :padding, :right], &(&1 + grow))
        {cfg, build.(cfg)}
      else
        {cfg, l}
      end
    else
      {cfg, l}
    end
  end

  def fit_labels(cfg, _series, l, _build), do: {cfg, l}

  # How much the plot must narrow for every outside label to fit. Narrowing
  # it by `d` moves a bar end at fraction `f` of the plot left by only `f * d`,
  # so a label overflowing by `o` needs `d = o / f`. Capped at half the plot.
  defp label_overflow(cfg, series, l) do
    dl = cfg.data_labels
    # The grid padding stays as the margin between label and SVG edge.
    limit = l.w - cfg.grid.padding.right

    cfg
    |> positions(series, l)
    |> Enum.map(fn r ->
      tw =
        Layout.text_width(label_text(cfg, r), dl.style.font_size, Layout.metrics(cfg, dl.style))

      off = DataLabels.offset(dl.offset_x, range(r.point), r.series, r.index)
      over = r.x + r.w + @label_gap + off + tw - limit
      f = (r.x + r.w - l.grid_x) / l.grid_w

      cond do
        over <= 0 -> 0
        f <= 0 -> l.grid_w / 2
        true -> min(over / f, l.grid_w / 2)
      end
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp label_text(_cfg, %{point: %{label: label}}) when label != nil, do: to_string(label)

  defp label_text(cfg, r) do
    [from, to] = range(r.point)

    case cfg.data_labels.formatter do
      f when is_function(f, 2) ->
        to_string(f.([from, to], %{series_index: r.series, data_point_index: r.index}))

      f when is_function(f, 1) ->
        to_string(f.([from, to]))

      _ ->
        fmt_value(to - from)
    end
  end

  # `{x, y, text_anchor}` of a label. "End" is the far edge along the value
  # axis: right of a bar, top of a column.
  defp label_place(:outside_end, r, true, _fs),
    do: {r.x + r.w + @label_gap, r.y + r.h / 2, "start"}

  defp label_place(:top, r, true, _fs), do: {r.x + r.w - @label_gap, r.y + r.h / 2, "end"}
  defp label_place(:bottom, r, true, _fs), do: {r.x + @label_gap, r.y + r.h / 2, "start"}
  defp label_place(_center, r, true, _fs), do: {r.x + r.w / 2, r.y + r.h / 2, "middle"}

  defp label_place(:outside_end, r, false, fs),
    do: {r.x + r.w / 2, max(r.y - @label_gap - fs / 2, fs / 2), "middle"}

  defp label_place(:top, r, false, fs), do: {r.x + r.w / 2, r.y + fs, "middle"}
  defp label_place(:bottom, r, false, _fs), do: {r.x + r.w / 2, r.y + r.h - 4, "middle"}
  defp label_place(_center, r, false, _fs), do: {r.x + r.w / 2, r.y + r.h / 2, "middle"}

  defp box_center(x, tw, "start"), do: x + tw / 2
  defp box_center(x, tw, "end"), do: x - tw / 2
  defp box_center(x, _tw, _middle), do: x

  defp on_mark_color(dl, r) do
    case dl.style.colors do
      [_ | _] = colors -> Enum.at(colors, rem(r.series, length(colors)))
      _ -> r.color
    end
  end

  # ── Range / tooltip helpers ────────────────────────────────────────────────

  @doc "Returns `{y_min, y_max}` across all ranges."
  def data_range(series) do
    values =
      series
      |> Enum.flat_map(& &1.data)
      |> Enum.flat_map(fn p -> range(p) || [] end)
      |> Enum.filter(&is_number/1)

    case values do
      [] -> {nil, nil}
      _ -> Enum.min_max(values)
    end
  end

  @doc "Formats one range data point for the tooltip."
  def tooltip_value(cfg, v) do
    case range(v) do
      [from, to] -> "#{fmt_num(cfg, from)} – #{fmt_num(cfg, to)}"
      nil -> ""
    end
  end

  @doc """
  Tooltip rows of series `s` for row `j`: one per point drawn in that row
  (several on a timeline).
  """
  def tooltip_rows(cfg, s, j) do
    rows = row_index(cfg)
    color = Config.color_at(cfg, s.index)

    s.data
    |> Enum.with_index()
    |> Enum.filter(fn {p, k} -> row_of(rows, p, k) == j end)
    |> Enum.map(fn {p, k} ->
      [
        EexCharts.Renderer.tooltip_row(color, s.name, tooltip_value(cfg, p)),
        EexCharts.Renderer.goal_rows(cfg, s, k)
      ]
    end)
  end

  @doc false
  # `[from, to]` of one data point, or nil.
  def range(%{y: [from, to | _]}), do: [from, to]
  def range([from, to | _]), do: [from, to]
  def range(_), do: nil

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)

  # Unset `stroke.colors` falls back to the series colors (`Theme.js`
  # `applyColorTypes`). Skipped at width 0, where it would draw nothing.
  defp stroke_color(cfg, i, fill) do
    case cfg.stroke.colors do
      nil -> if cfg.stroke.width > 0, do: fill
      colors when is_list(colors) -> Enum.at(colors, rem(i, length(colors)))
      color -> color
    end
  end

  defp fmt_num(cfg, n) do
    case cfg.tooltip.y_formatter do
      f when is_function(f, 1) ->
        to_string(f.(n))

      _ ->
        if timeline?(cfg), do: TimeScale.format_date(round(n), "dd MMM yyyy"), else: fmt_value(n)
    end
  end

  defp pct(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 70
    end
  end

  defp pct(value) when is_number(value), do: value
end
