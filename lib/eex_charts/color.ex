defmodule EexCharts.Color do
  @moduledoc """
  Color helpers for gradient shading (port of ApexCharts' shadeColor).

  Hex colors are shaded server-side by blending their channels. Colors we
  cannot inspect — `var(--color-primary)` and friends under the `:daisy`
  theme — are shaded by handing the browser a `color-mix()` expression
  instead, which is the same blend evaluated at paint time.
  """

  @doc """
  Shades a color. Positive `percent` (0..1) blends toward white, negative
  toward black.

  A `#rgb`/`#rrggbb` input is blended here and returned as hex. Any other CSS
  color (including `var(…)`) returns a `color-mix()` expression, so the blend
  survives a color whose value only the browser knows.
  """
  def shade("#" <> _ = hex, percent) do
    {r, g, b} = parse(hex)
    target = if percent < 0, do: 0, else: 255
    p = abs(percent)

    [r, g, b]
    |> Enum.map(fn c -> round((target - c) * p) + c end)
    |> then(fn [r, g, b] ->
      "#" <> to_hex(r) <> to_hex(g) <> to_hex(b)
    end)
  end

  def shade(color, percent) when is_binary(color) do
    # oklab keeps the mix perceptually even, which matters for the OKLCH
    # colors daisyUI themes are authored in. The hex path clamps out-of-range
    # channels; color-mix() needs the percentage clamped for the same reason
    # (treemap shade intensities can exceed 1).
    toward = if percent < 0, do: "#000", else: "#fff"
    pct = percent |> abs() |> Kernel.*(100) |> round() |> min(100)

    "color-mix(in oklab, #{toward} #{pct}%, #{color})"
  end

  @doc """
  Resolves every `var(--name, fallback)` in a CSS value to its fallback
  literal, innermost first, so nested fallbacks collapse fully. A `var()`
  without a fallback has no server-side value and is left untouched.

  Static rasterizers (resvg, and therefore Typst) have no CSS custom
  properties and render `var(…)` as black — ignoring the fallback — so
  static output must resolve these before the rasterizer sees them.
  """
  def resolve_vars(value) when is_binary(value) do
    resolved = Regex.replace(~r/var\(\s*--[\w-]+\s*,\s*([^()]*[^()\s])\s*\)/, value, "\\1")
    if resolved == value, do: value, else: resolve_vars(resolved)
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
