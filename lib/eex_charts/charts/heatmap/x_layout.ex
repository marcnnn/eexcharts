defmodule EexCharts.Charts.Heatmap.XLayout do
  @moduledoc """
  Continuous x-axis geometry for heatmaps (`xaxis.type: :numeric | :datetime`).

  On a category axis every column is one equal slot. On a value axis a cell is
  centred on its x value on a linear scale instead, and its width follows the
  spacing of the data:

    1. Collect the distinct x values of every series (hidden ones included,
       so toggling a row never moves the columns) and sort them.
    2. The **step** is the median spacing between consecutive distinct values.
       A single x value falls back to a step of 1 (numeric) or one day
       (datetime).
    3. Between two neighbours that are at most `1.5 x step` apart the cell
       boundary is their **midpoint**, so regular data (and data with some
       jitter, such as calendar months) tiles without seams.
    4. A wider spacing is treated as **missing data**: each neighbour extends
       only `step / 2` towards the other and the rest of the interval stays
       empty, so gaps in the data show as gaps.
    5. The outermost cells extend `step / 2` outwards; the axis domain is
       exactly `[first cell's left edge, last cell's right edge]` unless
       `xaxis.min` / `xaxis.max` override it (cells are then clipped to the
       domain and cells entirely outside it are dropped).

  Tick labels: a numeric axis gets ticks at multiples of a 1/2/5/10 "nice"
  step (about one per 80px, or `xaxis.step_size` when set); a datetime axis
  reuses `EexCharts.TimeScale.ticks/3`. Only ticks inside the domain are kept.
  """

  alias EexCharts.{Layout, TimeScale}

  @gap_factor 1.5
  @ms_per_day 86_400_000

  @doc "True when the heatmap places cells by x value."
  def value_axis?(cfg), do: cfg.xaxis.type in [:numeric, :datetime]

  @doc """
  Resolves a series into `[{x, y}]` for a value x-axis: numeric `x` (unix ms
  on a datetime axis) and a numeric `y`. Points without either are dropped.
  """
  def points(cfg, data) do
    for {_j, x, y, _z} <- Layout.series_points(cfg, data), is_number(x), is_number(y), do: {x, y}
  end

  @doc "Median spacing between consecutive distinct sorted values."
  def step([_, _ | _] = xs, _type) do
    gaps = xs |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)
    median(gaps)
  end

  def step(_xs, :datetime), do: @ms_per_day
  def step(_xs, _type), do: 1

  defp median(list) do
    sorted = Enum.sort(list)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end

  @doc """
  Returns `%{x => {left, right}}` cell extents (in x units) for sorted
  distinct `xs`, following the rule in the moduledoc.
  """
  def extents([], _step), do: %{}

  def extents(xs, step) do
    half = step / 2
    padded = [nil] ++ xs ++ [nil]

    padded
    |> Enum.chunk_every(3, 1, :discard)
    |> Map.new(fn [prev, x, next] ->
      {x, {x - side(x, prev, half, step), x + side(x, next, half, step)}}
    end)
  end

  defp side(_x, nil, half, _step), do: half

  defp side(x, other, half, step) do
    d = abs(x - other)
    if d <= @gap_factor * step, do: d / 2, else: half
  end

  @doc "The axis domain `{min, max}` covering every cell, honouring `xaxis.min/max`."
  def domain(cfg, extents) do
    {lo, hi} =
      case Map.values(extents) do
        [] ->
          {0, 1}

        es ->
          {es |> Enum.map(&elem(&1, 0)) |> Enum.min(), es |> Enum.map(&elem(&1, 1)) |> Enum.max()}
      end

    lo = if cfg.xaxis.min != nil, do: Layout.to_x(cfg.xaxis.min, cfg.xaxis.type), else: lo
    hi = if cfg.xaxis.max != nil, do: Layout.to_x(cfg.xaxis.max, cfg.xaxis.type), else: hi
    if hi > lo, do: {lo, hi}, else: {lo, lo + 1}
  end

  @doc """
  Builds the `Layout.x_scale` map (`type`, `ticks`, `nice_min`, `nice_max`)
  for the domain, so the shared value-axis label renderer and
  `Layout.x_value_pos/2` work unchanged.
  """
  def x_scale(cfg, {lo, hi}, grid_w) do
    type = cfg.xaxis.type

    ticks =
      case type do
        :datetime ->
          lo
          |> TimeScale.ticks(hi, grid_w)
          |> Enum.map(&%{value: &1.value, label: &1.label})

        _ ->
          lo
          |> numeric_ticks(hi, tick_step(cfg, hi - lo, grid_w))
          |> Enum.map(&%{value: &1, label: EexCharts.SVG.fmt_value(&1)})
      end

    ticks = Enum.filter(ticks, &(&1.value >= lo and &1.value <= hi))
    %{type: type, ticks: ticks, nice_min: lo, nice_max: hi}
  end

  defp tick_step(cfg, span, grid_w) do
    cond do
      is_number(cfg.xaxis.step_size) and cfg.xaxis.step_size > 0 ->
        cfg.xaxis.step_size

      is_number(cfg.xaxis.tick_amount) and cfg.xaxis.tick_amount > 0 ->
        nice_step(span / cfg.xaxis.tick_amount)

      true ->
        nice_step(span / max(grid_w / 80, 1))
    end
  end

  # Smallest 1/2/5/10 x 10^k step that is at least `raw`.
  defp nice_step(raw) when raw <= 0, do: 1

  defp nice_step(raw) do
    mag = :math.pow(10, :math.floor(:math.log10(raw)))
    m = Enum.find([1, 2, 5, 10], 10, &(&1 * mag >= raw * (1 - 1.0e-9)))
    step = m * mag
    if step >= 1, do: round(step), else: step
  end

  defp numeric_ticks(lo, hi, step) do
    first = Float.ceil(lo / step - 1.0e-9) * step
    n = trunc(Float.floor((hi - first) / step + 1.0e-9))

    for i <- 0..max(n, 0), v = first + i * step, v <= hi + 1.0e-9 do
      v |> EexCharts.Scale.strip_number() |> integral()
    end
  end

  defp integral(v) when is_float(v) and v == trunc(v), do: trunc(v)
  defp integral(v), do: v

  @doc "Tooltip title for a cell's x value."
  def title(x, :datetime, step) do
    fmt = if step < @ms_per_day, do: "dd MMM HH:mm", else: "dd MMM yyyy"
    TimeScale.format_date(round(x), fmt)
  end

  def title(x, _type, _step), do: EexCharts.SVG.fmt_value(x)
end
