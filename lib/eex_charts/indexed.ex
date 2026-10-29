defmodule EexCharts.Indexed do
  @moduledoc false

  # Constant-time access by position. Chart code often loops over data
  # indexes and reads several lists at that index; `Enum.at/2` walks the list
  # each time, which makes the loop quadratic in the number of points. Convert
  # once with `new/1`, then read with `at/3`.

  @doc false
  def new(list) when is_list(list), do: List.to_tuple(list)
  def new(_), do: {}

  @doc false
  def at(tuple, i, default \\ nil)

  def at(tuple, i, _default) when is_integer(i) and i >= 0 and i < tuple_size(tuple),
    do: elem(tuple, i)

  def at(_tuple, _i, default), do: default
end
