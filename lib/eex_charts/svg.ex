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

  @doc "Formats a number for SVG coordinates: 2 decimals, trailing zeros trimmed."
  def fmt(v) when is_integer(v), do: Integer.to_string(v)

  def fmt(v) when is_float(v) do
    rounded = Float.round(v, 2)

    if rounded == trunc(rounded) do
      Integer.to_string(trunc(rounded))
    else
      :erlang.float_to_binary(rounded, [{:decimals, 2}, :compact])
    end
  end

  @doc "Formats a data value for labels/tooltips (trims float noise)."
  def fmt_value(v) when is_integer(v), do: Integer.to_string(v)

  def fmt_value(v) when is_float(v) do
    rounded = EexCharts.Scale.strip_number(Float.round(v, 4))

    if is_integer(rounded) do
      Integer.to_string(rounded)
    else
      :erlang.float_to_binary(rounded * 1.0, [{:decimals, 4}, :compact])
    end
  end

  def fmt_value(v), do: to_string(v)

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
