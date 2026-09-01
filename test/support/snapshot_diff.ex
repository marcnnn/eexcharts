defmodule EexCharts.SnapshotDiff do
  @moduledoc """
  Compares two SVG snapshots: strictly on structure, numerically on values.

  The goldens in `test/snapshots/` are byte-identical across runs on one
  machine, but not across machines. `EexCharts.SVG.fmt/1` deliberately emits
  the shortest string that round-trips back to the same float — rounding
  coordinates moves rasterised text by a whole pixel, so it can't — which means
  every coordinate derived from `:math.cos/1` and friends carries the full
  double, last bit included. libm is free to compute that last bit differently
  on macOS and on Linux, and for the radar grid it does:

      Linux (where the goldens were seeded):  91.07573479407125,52.58260000000001
      macOS:                                  91.07573479407125,52.582599999999985

  A byte-for-byte gate turns that into a failing `mix test` on a clean checkout
  for every contributor not on the platform that seeded the goldens. So numbers
  here compare numerically, with a tolerance far below anything that could move
  a pixel, while tag names, attribute names and their order, colors, and text
  still have to match exactly.
  """

  # Relative tolerance. Cross-platform disagreement in the last bits of a
  # double is ~1e-16 relative; any real geometry change is orders of magnitude
  # larger. 1e-9 of an SVG user unit is about a billionth of a pixel.
  @tolerance 1.0e-9

  # Tokens of context shown either side of the first difference.
  @context 6

  @number ~r/-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/

  @doc """
  Returns `:ok` when the snapshots match, or `{:error, message}` pointing at
  the first difference in context.
  """
  @spec compare(binary, binary) :: :ok | {:error, binary}
  def compare(actual, expected)

  def compare(same, same), do: :ok

  def compare(actual, expected) do
    actual_tokens = tokenize(actual)
    expected_tokens = tokenize(expected)

    case first_mismatch(actual_tokens, expected_tokens, 0) do
      nil -> :ok
      index -> {:error, message(actual_tokens, expected_tokens, index)}
    end
  end

  defp tokenize(svg), do: Regex.split(@number, svg, include_captures: true)

  defp first_mismatch([], [], _index), do: nil

  defp first_mismatch([actual | rest_actual], [expected | rest_expected], index) do
    if token_match?(actual, expected),
      do: first_mismatch(rest_actual, rest_expected, index + 1),
      else: index
  end

  # One side ran out: the snapshots diverge in length here.
  defp first_mismatch(_actual, _expected, index), do: index

  defp token_match?(token, token), do: true

  defp token_match?(actual, expected) do
    with {actual_number, ""} <- Float.parse(actual),
         {expected_number, ""} <- Float.parse(expected) do
      close?(actual_number, expected_number)
    else
      _ -> false
    end
  end

  defp close?(actual, expected) do
    abs(actual - expected) <= @tolerance * max(1.0, max(abs(actual), abs(expected)))
  end

  defp message(actual, expected, index) do
    """
    first difference at token #{index} (marked >>>like this<<<):

      expected: #{context(expected, index)}
      actual:   #{context(actual, index)}
    """
  end

  defp context(tokens, index) do
    from = max(index - @context, 0)

    tokens
    |> Enum.slice(from..(index + @context)//1)
    |> Enum.with_index(from)
    |> Enum.map_join(fn
      {token, ^index} -> ">>>" <> token <> "<<<"
      {token, _index} -> token
    end)
  end
end
