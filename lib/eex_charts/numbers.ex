defmodule EexCharts.Numbers do
  @moduledoc """
  Keeps chart data inside the range the layout arithmetic can handle.

  The BEAM raises on float overflow instead of producing infinity, so a value
  near the float limit (`1.0e308`) made the scale's `max - min` raise and took
  the calling LiveView down. `sanitize/1` runs over the series and categories
  before anything else sees them:

    * magnitudes above `1.0e100` are clamped to `±1.0e100`;
    * non-zero magnitudes below `1.0e-100` become `0.0`.

  No chart can show the difference: both limits are far outside what a scale
  can label. The headroom means sums, ranges and products of in-range values
  stay finite.
  """

  @max 1.0e100
  @min_abs 1.0e-100

  @doc "The largest magnitude a data value keeps."
  def max, do: @max

  @doc "Clamps one number; anything else is returned unchanged."
  def clamp(v) when is_number(v) and v > @max, do: @max
  def clamp(v) when is_number(v) and v < -@max, do: -@max
  def clamp(v) when is_float(v) and v != 0.0 and abs(v) < @min_abs, do: 0.0
  def clamp(v), do: v

  @doc """
  Clamps every number inside lists, tuples and plain maps. Structs (dates,
  decimals) and other terms are left as they are.
  """
  def sanitize(v) when is_number(v), do: clamp(v)
  def sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)
  def sanitize(%_{} = struct), do: struct
  def sanitize(%{} = map), do: Map.new(map, fn {k, v} -> {k, sanitize(v)} end)

  def sanitize(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> sanitize() |> List.to_tuple()

  def sanitize(other), do: other
end
