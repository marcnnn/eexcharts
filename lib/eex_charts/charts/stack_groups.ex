defmodule EexCharts.Charts.StackGroups do
  @moduledoc """
  Grouped stacks for stacked bar charts, and `chart.stack_type: "100%"`.

  Give series a `group:` and those sharing a group stack together, while
  different groups stand side by side within the category slot:

      series: [
        %{name: "Q1 budget", group: "budget", data: [44, 55]},
        %{name: "Q2 budget", group: "budget", data: [13, 23]},
        %{name: "Q1 actual", group: "actual", data: [48, 50]},
        %{name: "Q2 actual", group: "actual", data: [10, 30]}
      ],
      options: %{chart: %{stacked: true}}

  Groups appear in order of their first series; series without a `group`
  form one group of their own. Each group's stack is
  `slot / groups * column_width%` wide (`bar_height%` when horizontal), so a
  chart without groups lays out exactly like an ordinary stacked bar chart.
  Positive and negative values stack away from zero separately, per group.

  With `chart.stack_type: "100%"` each group is scaled independently so that
  at every category its values sum (by magnitude) to 100: every group's stack
  reaches the full height. Data labels and tooltips keep showing the raw
  values; the value axis runs 0-100.

  Only charts that are stacked and use groups or `"100%"` take this path.
  """

  alias EexCharts.{Charts, Config, Layout}

  @doc "Whether the grouped-stack layout applies to this bar chart."
  def applies?(cfg, series) do
    cfg.chart.type == :bar and cfg.chart.stacked == true and
      (percent?(cfg) or Enum.any?(series, &(&1[:group] != nil)))
  end

  @doc "Whether `chart.stack_type` asks for 100% stacks."
  def percent?(cfg), do: cfg.chart[:stack_type] in ["100%", :"100%"]

  @doc "`[{group_key, [series]}]` in order of first appearance."
  def groups(series) do
    keys = series |> Enum.map(& &1[:group]) |> Enum.uniq()
    Enum.map(keys, fn k -> {k, Enum.filter(series, &(&1[:group] == k))} end)
  end

  @doc """
  Value axis range: the extreme per-group positive and negative sums, or nil
  when the grouped-stack layout does not apply.
  """
  def data_range(cfg, series) do
    if applies?(cfg, series) do
      n = series |> Enum.map(&length(&1.data)) |> Enum.max(fn -> 0 end)

      sums =
        for {_k, members} <- groups(series), j <- 0..max(n - 1, 0)//1 do
          vals = Enum.map(members, &scaled(cfg, members, &1, j))

          {vals |> Enum.filter(&(&1 > 0)) |> Enum.sum(),
           vals |> Enum.filter(&(&1 < 0)) |> Enum.sum()}
        end

      {pos, neg} = Enum.unzip(sums)
      {min(Enum.min(neg, fn -> 0 end), 0), max(Enum.max(pos, fn -> 0 end), 0)}
    end
  end

  # Value of series `s` at `j`, as a share of the group's total magnitude
  # under 100% stacking.
  defp scaled(cfg, members, s, j) do
    v = value(s, j)

    if percent?(cfg) do
      total = members |> Enum.map(&abs(value(&1, j))) |> Enum.sum()
      if total == 0, do: 0, else: v / total * 100
    else
      v
    end
  end

  defp value(s, j) do
    case Enum.at(s.data, j) do
      v when is_number(v) -> v
      _ -> 0
    end
  end

  @doc "Bar rectangles in the shape `EexCharts.Charts.Bar.positions/3` returns."
  def positions(cfg, series, %Layout{} = l) do
    bar_cfg = cfg.plot_options.bar
    groups = groups(series)
    n_groups = max(length(groups), 1)

    {slot, size} =
      if l.horizontal,
        do: {l.grid_h / l.n, Charts.Bar.pct(bar_cfg.bar_height)},
        else: {l.grid_w / l.n, Charts.Bar.pct(bar_cfg.column_width)}

    thick = slot / n_groups * size / 100

    groups
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_k, members}, g} ->
      members
      |> Enum.with_index()
      |> Enum.flat_map(fn {s, pos_i} ->
        color = Config.color_at(cfg, s.index)

        Enum.map(0..(length(s.data) - 1)//1, fn j ->
          raw = value(s, j)
          v = scaled(cfg, members, s, j)
          {pos, neg} = base(cfg, members, pos_i, j)
          b = if v >= 0, do: pos, else: neg
          across = slot * j + (slot - thick * n_groups) / 2 + thick * g

          rect =
            if l.horizontal do
              x_from = Layout.x_for(l, clamp(l, b))
              x_to = Layout.x_for(l, clamp(l, b + v))
              %{x: min(x_from, x_to), y: l.grid_y + across, w: abs(x_to - x_from), h: thick}
            else
              y_from = Layout.y_for(l, clamp(l, b))
              y_to = Layout.y_for(l, clamp(l, b + v))
              %{x: l.grid_x + across, y: min(y_from, y_to), w: thick, h: abs(y_from - y_to)}
            end

          Map.merge(rect, %{
            series: s.index,
            index: j,
            group: g,
            value: raw,
            color: if(bar_cfg.distributed, do: Config.color_at(cfg, j), else: color),
            positive: v >= 0,
            last_in_stack: last_nonzero?(members, pos_i, j, v)
          })
        end)
      end)
    end)
  end

  defp base(cfg, members, i, j) do
    members
    |> Enum.take(i)
    |> Enum.map(&scaled(cfg, members, &1, j))
    |> Enum.reduce({0, 0}, fn v, {pos, neg} ->
      if v >= 0, do: {pos + v, neg}, else: {pos, neg + v}
    end)
  end

  defp last_nonzero?(members, i, j, v) do
    v != 0 and
      members
      |> Enum.drop(i + 1)
      |> Enum.all?(fn s ->
        val = value(s, j)
        val == 0 or val >= 0 != v >= 0
      end)
  end

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)
end
