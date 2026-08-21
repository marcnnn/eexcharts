defmodule EexCharts.SVG do
  @moduledoc """
  Tiny SVG/HTML iodata builder with escaping. All chart output is assembled
  through this module, so user-provided strings are always escaped.
  """

  @doc "Builds an element as iodata. `children` may be iodata or `nil` (void)."
  def el(tag, attrs, children \\ nil)

  def el(tag, attrs, nil) do
    ["<", tag, attrs_io(attrs), "/>"]
  end

  def el(tag, attrs, children) do
    ["<", tag, attrs_io(attrs), ">", children, "</", tag, ">"]
  end

  # Maps have no defined iteration order (and Erlang's varies across VM runs),
  # so sort map attributes by name for deterministic, stable output. Keyword
  # lists keep their given order.
  defp attrs_io(attrs) when is_map(attrs) do
    attrs |> Enum.sort_by(fn {k, _v} -> attr_name(k) end) |> attrs_io()
  end

  defp attrs_io(attrs) do
    for {k, v} <- attrs, v != nil and v != false do
      [" ", attr_name(k), "=\"", attr_value(v), "\""]
    end
  end

  defp attr_name(k) when is_atom(k), do: k |> Atom.to_string() |> String.replace("_", "-")
  defp attr_name(k) when is_binary(k), do: k

  defp attr_value(true), do: ""
  defp attr_value(v) when is_binary(v), do: esc(v)
  defp attr_value(v) when is_atom(v), do: Atom.to_string(v)
  defp attr_value(v) when is_number(v), do: fmt(v)
  defp attr_value(v) when is_list(v), do: v

  @doc "Escapes text for use in SVG/HTML content and attribute values."
  def esc(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  def esc(other), do: other |> to_string() |> esc()

  @doc """
  Formats a number for SVG coordinates.

  Emits the shortest string that round-trips back to the same float — what
  `Number.prototype.toString` does in a browser — rather than rounding to a
  fixed number of decimals.

  Rounding here is not the harmless tidy-up it looks like. Text sits on a
  knife edge: an end-anchored 13px label at x=263.4949645996094 and the same
  label at x=263.4949951171875 rasterise a **whole pixel** apart in Chromium,
  and 0.00003px is exactly the error four decimals introduce.
  """
  def fmt(v) when is_integer(v), do: Integer.to_string(v)

  def fmt(v) when is_float(v) do
    if v == trunc(v) and abs(v) < 1.0e15 do
      Integer.to_string(trunc(v))
    else
      :erlang.float_to_binary(v, [:short])
    end
  end

  @doc "Formats a data value for labels/tooltips (trims float noise)."
  def fmt_value(v) when is_integer(v), do: Integer.to_string(v)

  def fmt_value(v) when is_float(v) do
    decimals = value_decimals(v)
    rounded = EexCharts.Scale.strip_number(Float.round(v, decimals))

    if is_integer(rounded) do
      Integer.to_string(rounded)
    else
      :erlang.float_to_binary(rounded * 1.0, [{:decimals, decimals}, :compact])
    end
  end

  def fmt_value(v), do: to_string(v)

  # Four decimals covers ordinary data, but anything below a thousandth
  # rounds away: at 1e-5 every axis label collapses to "0". Keep four
  # significant digits down there; :compact trims what the value doesn't use.
  defp value_decimals(v) when v == 0.0, do: 4
  defp value_decimals(v) when abs(v) >= 0.001, do: 4
  defp value_decimals(v), do: min(3 - floor(:math.log10(abs(v))), 15)

  @doc "SVG path move command."
  def move(x, y), do: ["M ", fmt(x), " ", fmt(y)]

  @doc "SVG path line command."
  def line(x, y), do: [" L ", fmt(x), " ", fmt(y)]

  @doc "SVG cubic bezier command."
  def curve(x1, y1, x2, y2, x, y) do
    [" C ", fmt(x1), " ", fmt(y1), " ", fmt(x2), " ", fmt(y2), " ", fmt(x), " ", fmt(y)]
  end

  @doc "SVG arc command."
  def arc(rx, ry, rotation, large_arc, sweep, x, y) do
    [
      " A ",
      fmt(rx),
      " ",
      fmt(ry),
      " ",
      fmt(rotation),
      " ",
      Integer.to_string(large_arc),
      " ",
      Integer.to_string(sweep),
      " ",
      fmt(x),
      " ",
      fmt(y)
    ]
  end
end
