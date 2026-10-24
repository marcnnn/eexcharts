defmodule EexCharts.DataLabels do
  @moduledoc """
  Helpers shared by the cartesian data-label renderers: per-point offsets and
  overlap hiding.

  ## Per-point offsets

  `data_labels.offset_x` / `offset_y` take a number (applied to every label)
  or a function. An arity-2 function receives the label's value and
  `%{series_index: i, data_point_index: j}`, the same shape the arity-2
  `data_labels.formatter` gets; an arity-1 function receives just the value.
  Either must return a number of pixels. Anything else counts as 0.

      data_labels: %{offset_y: fn v, _ -> if v < 0, do: 14, else: -4 end}

  ## Overlap hiding

  `data_labels: %{hide_overlapping: true}` (default `false`) drops labels whose
  boxes would collide. Boxes are estimated from `EexCharts.FontMetrics` (text
  width, `Layout.text_height/1`) plus the background padding when the label
  has a pill, so the result does not depend on a browser.

  Plain "first wins" thinning favours series 0: walking the labels in series
  order, every collision is decided against the later series. Instead the
  labels are offered in a balanced order: at each step the next label (in
  data order) comes from whichever series currently has the fewest visible
  labels, ties going to the lower series index. A label is kept when its box
  does not intersect any label already kept. Two series whose labels collide
  everywhere therefore alternate rather than one of them vanishing.
  """

  alias EexCharts.Layout

  @typedoc "Axis-aligned label box `{x0, y0, x1, y1}` in SVG pixels."
  @type box :: {number, number, number, number}

  @doc """
  Resolves an `offset_x` / `offset_y` option for one label.
  """
  @spec offset(term, term, integer, integer) :: number
  def offset(off, _value, _i, _j) when is_number(off), do: off

  def offset(f, value, i, j) when is_function(f, 2),
    do: number(f.(value, %{series_index: i, data_point_index: j}))

  def offset(f, value, _i, _j) when is_function(f, 1), do: number(f.(value))
  def offset(_off, _value, _i, _j), do: 0

  defp number(n) when is_number(n), do: n
  defp number(_), do: 0

  @doc """
  Estimated box of a label centred on `{x, y}` (text-anchor middle, central
  baseline). `pad_x` / `pad_y` grow it on each side.
  """
  @spec box(number, number, binary, number, term, number, number) :: box
  def box(x, y, text, font_size, metrics, pad_x \\ 0, pad_y \\ 0) do
    w = Layout.text_width(text, font_size, metrics) + 2 * pad_x
    h = Layout.text_height(font_size) + 2 * pad_y
    {x - w / 2, y - h / 2, x + w / 2, y + h / 2}
  end

  @doc "Whether two boxes overlap (touching edges do not count)."
  @spec overlap?(box, box) :: boolean
  def overlap?({ax0, ay0, ax1, ay1}, {bx0, by0, bx1, by1}) do
    ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1
  end

  @doc """
  Balanced overlap hiding. Takes `{series_index, box, payload}` triples in
  any order and returns the triples that stay visible, in their input order.
  See the moduledoc for the ordering rule.
  """
  @spec hide_overlapping([{integer, box, term}]) :: [{integer, box, term}]
  def hide_overlapping(labels) do
    indexed = Enum.with_index(labels)

    queues =
      indexed
      |> Enum.group_by(fn {{s, _box, _p}, _k} -> s end)
      |> Map.new(fn {s, items} -> {s, {items, 0}} end)

    queues
    |> pick([])
    |> Enum.sort_by(fn {_label, k} -> k end)
    |> Enum.map(fn {label, _k} -> label end)
  end

  defp pick(queues, kept) when map_size(queues) == 0, do: kept

  defp pick(queues, kept) do
    {s, {[{{_s, box, _p}, _k} = item | rest], count}} =
      Enum.min_by(queues, fn {s, {_items, count}} -> {count, s} end)

    free? = not Enum.any?(kept, fn {{_s, b, _p}, _k} -> overlap?(box, b) end)
    {kept, count} = if free?, do: {[item | kept], count + 1}, else: {kept, count}

    queues =
      case rest do
        [] -> Map.delete(queues, s)
        _ -> Map.put(queues, s, {rest, count})
      end

    pick(queues, kept)
  end
end
