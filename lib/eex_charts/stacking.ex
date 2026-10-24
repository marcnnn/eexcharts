defmodule EexCharts.Stacking do
  @moduledoc """
  Stacked line / area charts and streamgraphs.

  ## Stacked line and area

  `chart: %{stacked: true}` on a `:line` or `:area` chart piles each series on
  top of the ones before it, the way ApexCharts v4.7.0 does: series `i` at
  category `j` is drawn at `sum(values of series 0..i at j)`, and `nil` values
  count as zero (ApexCharts' `setNullSeriesToZeroValues`). Areas are filled as
  bands between the series' own baseline (the top of the series below) and its
  top, so semi-transparent fills do not double up. Every `stroke.curve` works;
  the band's lower edge follows the same curve as the line it sits on.

  `chart: %{stack_type: "100%"}` (ApexCharts `chart.stackType`, default
  `"normal"`) normalises each category to percentages of its total. The y-axis
  is fixed to `0..100` in five steps (unless `tick_amount` is set) with a `%`
  label formatter (unless the axis already has one), and tooltips show the percentage followed by the raw value,
  e.g. `42.5% (130)`. Values are expected to be non-negative in this mode.

  ## Streamgraph (`type: :streamgraph`)

  Smooth stacked areas around a moving baseline. Options live under
  `plot_options: %{streamgraph: ...}`:

    * `offset` - `:wiggle` (default) or `:silhouette`, or `:zero` for an
      ordinary stacked area baseline.
      * `:silhouette` centres every category on zero: `g0 = -total / 2`.
      * `:wiggle` is Byron & Wattenberg's weighted wiggle ("Stacked Graphs -
        Geometry & Aesthetics", 2008), which minimises the slopes of all layer
        edges, weighted by layer thickness. With layers `f_1..f_n` bottom to
        top and `f'` the change from the previous category,

            g0' = -(1 / sum_i f_i) * sum_i (f_i' / 2 + sum_{k<i} f_k') * f_i

        integrated from `g0 = 0` (categories are one unit apart; a category
        whose total is zero keeps the previous baseline). The integrated
        baseline is then shifted by one constant so the stream's mean midline
        sits at zero, which keeps it centred in the plot without changing any
        slope.
    * `order` - `:none` (default, input order bottom to top) or
      `:inside_out`: layers are sorted by the category of their peak and
      placed alternately above and below, each on the side with the smaller
      running sum, so early-peaking layers sit in the middle and late ones on
      the outside. Colours and the legend always follow input order.

  The y-axis is hidden by default (a moving baseline makes absolute values
  meaningless), as are horizontal grid lines. Negative and `nil` values count
  as zero. `stack_type: "100%"` also applies.
  """

  alias EexCharts.{Layout, SVG}

  @doc "True when the chart stacks line/area series (or is a streamgraph)."
  def enabled?(%{chart: %{type: :streamgraph}}), do: true
  def enabled?(%{chart: %{type: t} = chart}) when t in [:line, :area], do: chart[:stacked] == true
  def enabled?(_cfg), do: false

  @doc "True for `chart.stack_type: \"100%\"`."
  def percent?(cfg), do: cfg.chart[:stack_type] in ["100%", :"100%", :percent]

  @doc """
  Adjusts the config for stacking: a hidden y-axis for streamgraphs and a
  fixed `0..100` percentage axis for `stack_type: "100%"`.
  """
  def prepare(cfg) do
    cond do
      not enabled?(cfg) -> cfg
      cfg.chart.type == :streamgraph -> update_yaxes(cfg, &hide_labels/1)
      percent?(cfg) -> update_yaxes(cfg, &percent_axis/1)
      true -> cfg
    end
  end

  defp update_yaxes(cfg, fun) do
    case cfg.yaxis do
      list when is_list(list) -> %{cfg | yaxis: Enum.map(list, fun)}
      %{} = axis -> %{cfg | yaxis: fun.(axis)}
    end
  end

  # `yaxis.show: false` alone still reserves the label gutter, so a hidden
  # axis drops its labels too.
  defp hide_labels(%{show: false} = axis),
    do: Map.update(axis, :labels, %{show: false}, &Map.put(&1, :show, false))

  defp hide_labels(axis), do: axis

  defp percent_axis(axis) do
    axis
    |> Map.put(:min, 0)
    |> Map.put(:max, 100)
    |> Map.update(:tick_amount, 5, &(&1 || 5))
    |> Map.put_new(:formatter, nil)
    |> Map.update!(:formatter, fn
      nil -> fn v -> SVG.fmt_value(v) <> "%" end
      f -> f
    end)
  end

  @doc """
  Attaches stacking geometry to every (visible) series as `:stack`:
  `%{lo: [..], hi: [..], pct: [..] | nil, pos: p}`, one entry per category
  `0..n-1`, in data units. `pos` is the series' position in the stack (0 is
  the bottom layer). Series pass through untouched when stacking is off.
  """
  def annotate(cfg, series, n) do
    if enabled?(cfg) and series != [] and n > 0 do
      stream? = cfg.chart.type == :streamgraph

      values =
        Enum.map(series, fn s ->
          Enum.map(0..(n - 1), fn j -> value(Enum.at(s.data, j), stream?) end)
        end)

      pct = if percent?(cfg), do: percentages(values)
      plotted = pct || values

      sg = stream_options(cfg)

      order =
        if stream?, do: order(sg.order, plotted), else: Enum.to_list(0..(length(series) - 1))

      ordered = Enum.map(order, &Enum.at(plotted, &1))
      base = if stream?, do: baseline(sg.offset, ordered), else: List.duplicate(0, n)

      # Running sums of the raw values in stack order. Under "100%" each sum
      # is scaled by the category total summed in the same order, so the top
      # edge lands on exactly 100 instead of a float sum of percentages.
      raw_ordered = Enum.map(order, &Enum.at(values, &1))
      cums = raw_ordered |> Enum.scan(&Enum.zip_with(&1, &2, fn a, b -> a + b end))
      totals = List.last(cums)
      scale = if pct, do: &percent_of/2, else: fn c, _t -> c end

      edges =
        Enum.map([List.duplicate(0, n) | cums], fn cum ->
          [cum, totals, base] |> Enum.zip_with(fn [c, t, b] -> b + scale.(c, t) end)
        end)

      bands = Enum.zip(edges, tl(edges))

      by_series =
        order
        |> Enum.zip(bands)
        |> Enum.with_index(fn {si, {lo, hi}}, pos -> {si, %{lo: lo, hi: hi, pos: pos}} end)
        |> Map.new()

      series
      |> Enum.with_index()
      |> Enum.map(fn {s, si} ->
        stack = Map.put(by_series[si], :pct, pct && Enum.at(pct, si))
        Map.put(s, :stack, stack)
      end)
    else
      series
    end
  end

  defp percent_of(_c, t) when t == 0, do: 0.0
  defp percent_of(c, c), do: 100.0
  defp percent_of(c, t), do: 100 * c / t

  defp value(v, stream?) when is_number(v), do: if(stream? and v < 0, do: 0, else: v)
  defp value(_v, _stream?), do: 0

  defp stream_options(cfg) do
    sg = get_in(cfg, [:plot_options, :streamgraph]) || %{}
    %{offset: Map.get(sg, :offset, :wiggle), order: Map.get(sg, :order, :none)}
  end

  @doc "Data range covering every band edge of annotated series."
  def data_range(series) do
    values = Enum.flat_map(series, fn s -> s.stack.lo ++ s.stack.hi end)

    case values do
      [] -> {nil, nil}
      _ -> Enum.min_max(values)
    end
  end

  @doc """
  Converts rows of values (one row per series) to per-category percentages of
  the category total. A category totalling zero yields zeros.
  """
  def percentages(rows) do
    totals = rows |> Enum.zip_with(&Enum.sum/1)

    Enum.map(rows, fn row ->
      Enum.zip_with(row, totals, fn
        _v, t when t == 0 -> 0.0
        v, t -> 100 * v / t
      end)
    end)
  end

  @doc """
  Baseline `g0` per category for layers given bottom to top (each a list of
  non-negative values). See the moduledoc for the formulas.
  """
  def baseline(_offset, []), do: []

  def baseline(:zero, [row | _]), do: Enum.map(row, fn _ -> 0 end)

  def baseline(:silhouette, layers), do: Enum.map(totals(layers), &(-&1 / 2))

  def baseline(:wiggle, layers) do
    columns = Enum.zip_with(layers, & &1)

    slopes =
      columns
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [prev, cur] -> wiggle_slope(prev, cur) end)

    g = Enum.scan([0.0 | slopes], &(&1 + &2))

    # Centre the stream: shift so the mean midline is zero.
    mids = Enum.zip_with(g, totals(layers), fn g0, t -> g0 + t / 2 end)
    shift = Enum.sum(mids) / length(mids)
    Enum.map(g, &(&1 - shift))
  end

  def baseline(other, _layers),
    do: raise(ArgumentError, "unknown streamgraph offset #{inspect(other)}")

  defp totals(layers), do: Enum.zip_with(layers, &Enum.sum/1)

  defp wiggle_slope(prev, cur) do
    total = Enum.sum(cur)

    if total == 0 do
      0.0
    else
      {weighted, _below} =
        prev
        |> Enum.zip(cur)
        |> Enum.reduce({0.0, 0.0}, fn {p, c}, {acc, below} ->
          d = c - p
          {acc + (d / 2 + below) * c, below + d}
        end)

      -weighted / total
    end
  end

  @doc """
  Stacking order (series positions, bottom to top) for a list of rows.
  `:none` keeps input order; `:inside_out` is described in the moduledoc.
  """
  def order(:none, rows), do: Enum.to_list(0..(length(rows) - 1)//1)

  def order(:inside_out, rows) do
    {bottoms, tops, _, _} =
      rows
      |> Enum.with_index()
      |> Enum.sort_by(fn {row, i} -> {peak_index(row), i} end)
      |> Enum.reduce({[], [], 0, 0}, fn {row, i}, {bottoms, tops, bsum, tsum} ->
        sum = Enum.sum(row)

        if tsum < bsum,
          do: {bottoms, [i | tops], bsum, tsum + sum},
          else: {[i | bottoms], tops, bsum + sum, tsum}
      end)

    # `bottoms` is already outermost-first; `tops` must be reversed to grow up.
    bottoms ++ Enum.reverse(tops)
  end

  def order(other, _rows), do: raise(ArgumentError, "unknown streamgraph order #{inspect(other)}")

  defp peak_index(row) do
    row |> Enum.with_index() |> Enum.max_by(&elem(&1, 0), fn -> {0, 0} end) |> elem(1)
  end

  @doc "Data-label anchor y for an annotated series (top of its band)."
  def label_y(%{stack: %{hi: hi}}, l, j, v, dl) when is_number(v),
    do: Layout.y_for(l, Enum.at(hi, j)) - 10 + dl.offset_y

  @doc """
  Tooltip value for one series at category `j`: under `stack_type: "100%"`
  the percentage followed by the raw value, otherwise `raw` as formatted.
  """
  def tooltip_value(%{stack: %{pct: pct}}, j, formatted) when is_list(pct) do
    p = Enum.at(pct, j) * 1.0
    "#{:erlang.float_to_binary(Float.round(p, 1), decimals: 1)}% (#{formatted})"
  end

  def tooltip_value(_series, _j, formatted), do: formatted
end
