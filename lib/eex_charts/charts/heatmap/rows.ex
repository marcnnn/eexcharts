defmodule EexCharts.Charts.Heatmap.Rows do
  @moduledoc """
  Vertical geometry of a heatmap: where each row sits, how rows are grouped
  and where summary rows go.

  Rows are laid out top to bottom in **draw order**: the series reversed (as
  in ApexCharts, series 0 at the bottom), or as given with
  `plot_options.heatmap.reverse_rows: true`.

    * `row_groups: [%{name:, rows: n}]` takes the next `n` rows of the draw
      order for each group, top first. Rows past the last group belong to
      none. Groups are counted over all series, so hiding one shortens its
      group instead of shifting the rest; a group whose rows are all hidden
      disappears. Consecutive rows of different groups are `group_gap` px
      apart.
    * `summary_rows: [%{name:, data:}]` follow the last row, `summary_gap`
      px below it, with a rule in the middle of that gap.

  Every row, summary rows included, gets the same height: what is left of
  the plot height after the gaps, split evenly.
  """

  @doc """
  Lays out the rows of `visible` (a subset of `all_series`) and the summary
  rows inside `grid_y .. grid_y + grid_h`.

  Returns a map with

    * `rows` - `[%{series:, group:, y:, h:}]`, series rows in series order
      (the order the marks are emitted in), then the summary rows; a
      summary row's `series` is its option map plus `index: 0` (it borrows
      series 0's colour), `key: "s<k>"` and `summary: k`;
    * `groups` - `[%{name:, y:}]`, `y` being the centre of the group's first
      visible row;
    * `rule_y` - the y of the rule above the summary rows, or `nil`.
  """
  def layout(cfg, all_series, visible, grid_y, grid_h) do
    opts = cfg.plot_options.heatmap
    shown = MapSet.new(visible, & &1.index)

    ordered =
      if opts.reverse_rows, do: all_series, else: Enum.reverse(all_series)

    series_rows =
      ordered
      |> Enum.zip(group_ids(opts.row_groups, length(ordered)))
      |> Enum.filter(fn {s, _g} -> MapSet.member?(shown, s.index) end)

    summary = summary_series(opts.summary_rows)

    # Gaps above each series row: one more at every change of group.
    {gaps_before, _} =
      Enum.map_reduce(series_rows, {:start, 0}, fn {_s, g}, {prev, n} ->
        n = if prev != :start and prev != g, do: n + 1, else: n
        {n, {g, n}}
      end)

    n_gaps = List.last(gaps_before, 0)
    summary_gap = if summary != [] and series_rows != [], do: opts.summary_gap, else: 0
    n_rows = length(series_rows) + length(summary)
    free = grid_h - n_gaps * opts.group_gap - summary_gap
    row_h = if n_rows > 0, do: max(free, 0) / n_rows, else: 0

    rows =
      series_rows
      |> Enum.zip(gaps_before)
      |> Enum.with_index()
      |> Enum.map(fn {{{s, g}, gaps}, i} ->
        %{series: s, group: g, y: grid_y + i * row_h + gaps * opts.group_gap, h: row_h}
      end)

    summary_top = grid_y + length(series_rows) * row_h + n_gaps * opts.group_gap + summary_gap

    summary_rows =
      summary
      |> Enum.with_index()
      |> Enum.map(fn {s, k} -> %{series: s, group: nil, y: summary_top + k * row_h, h: row_h} end)

    %{
      rows: Enum.sort_by(rows, & &1.series.index) ++ summary_rows,
      groups: group_labels(opts.row_groups, rows),
      rule_y: if(summary_gap > 0, do: summary_top - summary_gap / 2)
    }
  end

  @doc "Whether the chart has a group label column."
  def groups?(cfg), do: cfg.plot_options.heatmap.row_groups != []

  @doc "The summary rows as pseudo-series (see `layout/5`)."
  def summary_series(summary_rows) do
    summary_rows
    |> Enum.with_index()
    |> Enum.map(fn {r, k} ->
      Map.merge(r, %{
        name: to_string(Map.get(r, :name, "")),
        data: Map.get(r, :data, []),
        index: 0,
        key: "s#{k}",
        summary: k
      })
    end)
  end

  # Group id of each row in draw order; `nil` past the last group.
  defp group_ids(groups, n) do
    ids =
      groups
      |> Enum.with_index()
      |> Enum.flat_map(fn {g, k} -> List.duplicate(k, Map.get(g, :rows, 0)) end)

    Enum.take(ids ++ List.duplicate(nil, n), n)
  end

  defp group_labels(groups, rows) do
    groups
    |> Enum.with_index()
    |> Enum.flat_map(fn {g, k} ->
      case Enum.find(rows, &(&1.group == k)) do
        nil -> []
        row -> [%{name: to_string(Map.get(g, :name, "")), y: row.y + row.h / 2}]
      end
    end)
  end
end
