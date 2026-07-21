defmodule EexCharts.Color do
  @moduledoc """
  Hex color helpers for gradient shading (port of ApexCharts' shadeColor).
  """

  @doc """
  Shades a `#rrggbb` color. Positive `percent` (0..1) blends toward white,
  negative toward black.
  """
  def shade(hex, percent) do
    {r, g, b} = parse(hex)
    target = if percent < 0, do: 0, else: 255
    p = abs(percent)

    [r, g, b]
    |> Enum.map(fn c -> round((target - c) * p) + c end)
    |> then(fn [r, g, b] ->
      "#" <> to_hex(r) <> to_hex(g) <> to_hex(b)
    end)
  end

  @doc "Parses `#rgb` or `#rrggbb` into `{r, g, b}`."
  def parse("#" <> hex) when byte_size(hex) == 3 do
    <<r::binary-1, g::binary-1, b::binary-1>> = hex
    {String.to_integer(r <> r, 16), String.to_integer(g <> g, 16), String.to_integer(b <> b, 16)}
  end

  def parse("#" <> hex) when byte_size(hex) == 6 do
    <<r::binary-2, g::binary-2, b::binary-2>> = hex
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16)}
  end

  def parse(_), do: {55, 61, 63}

  defp to_hex(c) do
    c |> max(0) |> min(255) |> Integer.to_string(16) |> String.pad_leading(2, "0")
  end
end
