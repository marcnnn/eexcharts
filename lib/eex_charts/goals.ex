defmodule EexCharts.Goals do
  @moduledoc """
  Goal markers on bar and range bar data points, ported from ApexCharts
  v4.7.0 (`Helpers.getGoalValues` / `drawGoalLine` in
  `src/charts/common/bar/Helpers.js`).

  A map data point may carry a `goals` list:

      %{x: "Item 01", y: 54, goals: [
        %{name: "Target", value: 60, stroke_width: 8, stroke_color: "#775DD0"}
      ]}

  Each goal is drawn across its bar's slot at `value` on the value axis, on
  top of every bar (stacked bars do not cover it). Goal keys:

    * `value` - position on the value axis. Goal values also extend the
      axis range, as in v4.7.0.
    * `name` - label for the tooltip row.
    * `stroke_color` - defaults to `plot_options.bar.goals.stroke_color`
      (`"#a8a8a8"`, the v4.7.0 `drawLine` default).
    * `stroke_width`, `stroke_height` - as in v4.7.0, these are named for a
      column chart: on columns `stroke_width` is half the line's length
      (default: half the bar width, so the line spans the bar) and
      `stroke_height` its thickness (default 2); on horizontal bars
      `stroke_height` is the half length and `stroke_width` the thickness.
    * `stroke_dash_array` (default `0`), `stroke_line_cap` (default `:butt`).
    * `shape` - `:line` (default) or `:circle`, an extension beyond v4.7.0:
      a dot of radius `size` (default 5) at the value, filled with
      `stroke_color` and ringed with the marker stroke colour
      (`markers.stroke_colors`, the page surface) so it stays legible over
      a bar.

  Goals outside the plot area (more than 1px past the grid, possible with a
  fixed axis `min` / `max`) are skipped, as in v4.7.0.

  ## Themes

  The default colour is a mid grey that reads on light and dark pages; under
  `theme.mode: :daisy` it becomes `var(--color-base-content, #a8a8a8)`. A
  goal's own `stroke_color` always wins.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Indexed, Layout}

  @default_color "#a8a8a8"
  @default_radius 5

  @doc """
  The goal markers of all bars: one group per series that has goals, `[]`
  when none has. `rects` are the bar rectangles (`%{series, index, x, y, w,
  h}`, top-left corner).

  v4.7.0 draws a series' goals inside that series' group, so in a stacked
  chart the next series' bars cover them; here they are drawn after every
  bar instead.
  """
  def render(cfg, series, rects, %Layout{} = l) do
    by_index = Map.new(series, &{&1.index, indexed(&1)})

    rects
    |> Enum.group_by(& &1.series)
    |> Enum.sort_by(fn {i, _} -> i end)
    |> Enum.flat_map(fn {i, rects} ->
      case Enum.flat_map(rects, &marks(cfg, of(by_index[i], &1.index), &1, l)) do
        [] -> []
        marks -> [el("g", %{class: "eexcharts-goals", pointer_events: "none"}, marks)]
      end
    end)
  end

  @doc """
  The data points of `series` that may carry goals, indexed for `of/2`. Build
  it once per series: reading points by position from the list would make a
  loop over the points quadratic.
  """
  def indexed(series), do: Indexed.new(series[:source_data] || series.data)

  @doc "The goals of data point `j` of `indexed/1` (`[]` when it has none)."
  def of(points, j), do: of_point(Indexed.at(points, j))

  @doc "The goals of one data point (`[]` when it has none)."
  def of_point(%{goals: goals}) when is_list(goals),
    do: Enum.filter(goals, &is_number(&1[:value]))

  def of_point(_point), do: []

  @doc "The colour a goal is drawn in."
  def color(cfg, goal) do
    goal[:stroke_color] || get_in(cfg.plot_options.bar, [:goals, :stroke_color]) ||
      @default_color
  end

  @doc """
  Widens a `{min, max}` value range (either may be nil) to include every
  goal value of `series`, as v4.7.0's `Range.getMinYMaxY` does.
  """
  def extend_range({mn, mx} = range, series) do
    values =
      for s <- series,
          point <- s[:source_data] || s.data,
          g <- of_point(point),
          do: g.value

    case values do
      [] -> range
      _ -> {min(mn || Enum.min(values), Enum.min(values)), max(mx, Enum.max(values))}
    end
  end

  defp marks(cfg, goals, r, %Layout{horizontal: true} = l) do
    cy = r.y + r.h / 2

    for g <- goals,
        x = Layout.x_for(l, g.value),
        x >= l.grid_x - 1,
        x <= l.grid_x + l.grid_w + 1 do
      half = Map.get(g, :stroke_height, r.h / 2)
      mark(cfg, g, {x, cy - half}, {x, cy + half}, thickness(g[:stroke_width]))
    end
  end

  defp marks(cfg, goals, r, l) do
    cx = r.x + r.w / 2

    for g <- goals,
        y = Layout.y_for(l, g.value),
        y >= l.grid_y - 1,
        y <= l.grid_y + l.grid_h + 1 do
      half = Map.get(g, :stroke_width, r.w / 2)
      mark(cfg, g, {cx - half, y}, {cx + half, y}, thickness(g[:stroke_height]))
    end
  end

  # v4.7.0 falls back to 2 for a missing or zero thickness.
  defp thickness(w) when is_number(w) and w > 0, do: w
  defp thickness(_w), do: 2

  defp mark(cfg, %{shape: :circle} = g, {x1, y1}, {x2, y2}, _thickness) do
    el("circle", %{
      class: "eexcharts-goal",
      cx: (x1 + x2) / 2,
      cy: (y1 + y2) / 2,
      r: g[:size] || @default_radius,
      fill: color(cfg, g),
      stroke: Config.color_for(cfg.markers.stroke_colors, 0),
      stroke_width: 1
    })
  end

  defp mark(cfg, g, {x1, y1}, {x2, y2}, thickness) do
    el("line", %{
      class: "eexcharts-goal",
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      stroke: color(cfg, g),
      stroke_width: thickness,
      stroke_dasharray: dash(g[:stroke_dash_array]),
      stroke_linecap: g[:stroke_line_cap]
    })
  end

  defp dash(d) when is_number(d) and d > 0, do: d
  defp dash(d) when is_binary(d), do: d
  defp dash(_d), do: nil
end
