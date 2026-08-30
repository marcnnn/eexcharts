defmodule EexCharts.SVG do
  @moduledoc """
  The element tree every chart is built from, plus its SVG/HTML serializer.

  `el/3` builds a node — `{:el, tag, attrs, children}` — and keeps attribute
  values exactly as the chart code passed them: numbers stay numbers, path
  data stays a list of command tuples. Nothing is formatted until
  `to_iodata/1` walks the tree, which is what lets a second backend (a PDF
  writer, say) pattern-match the structure and emit its own drawing operators
  instead of parsing strings back out of an SVG document.

  Text content is the one exception: callers escape it themselves with
  `esc/1` and hand it over as iodata.
  """

  @typedoc "A path command. `to_iodata/1` renders these into a `d` attribute."
  @type command ::
          {:move, number, number}
          | {:rmove, number, number}
          | {:line, number, number}
          | {:hline, number}
          | {:vline, number}
          | {:curve, number, number, number, number, number, number}
          | {:arc, number, number, number, integer, integer, number, number}
          | :close

  @typedoc "A node of the element tree."
  @type node_t :: {:el, binary, map | keyword, term} | iodata | nil | [node_t]

  @doc """
  Builds an element node. `children` may be another node, iodata, a (nested)
  list of either, or `nil` for a void element.
  """
  def el(tag, attrs, children \\ nil), do: {:el, tag, attrs, children}

  @doc """
  Serializes an element tree (or a list of them) to SVG/HTML iodata.
  """
  def to_iodata({:el, tag, attrs, nil}) do
    ["<", tag, attrs_io(attrs), "/>"]
  end

  def to_iodata({:el, tag, attrs, children}) do
    ["<", tag, attrs_io(attrs), ">", to_iodata(children), "</", tag, ">"]
  end

  def to_iodata(nodes) when is_list(nodes), do: Enum.map(nodes, &to_iodata/1)
  def to_iodata(nil), do: []
  def to_iodata(leaf), do: leaf

  @doc """
  Removes `attrs` (by attribute name) from every element in the tree.

  `EexCharts.to_svg/4` uses it to drop the hover-lookup attributes the chart
  modules emit unconditionally, which only the JS hook reads.
  """
  def drop_attrs({:el, tag, attrs, children}, names) do
    {:el, tag, reject_attrs(attrs, names), drop_attrs(children, names)}
  end

  def drop_attrs(nodes, names) when is_list(nodes) do
    Enum.map(nodes, &drop_attrs(&1, names))
  end

  def drop_attrs(leaf, _names), do: leaf

  defp reject_attrs(attrs, names) when is_map(attrs) do
    Map.reject(attrs, fn {k, _v} -> attr_name(k) in names end)
  end

  defp reject_attrs(attrs, names) do
    Enum.reject(attrs, fn {k, _v} -> attr_name(k) in names end)
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
  defp attr_value(:close), do: path_io([:close])
  defp attr_value(v) when is_atom(v), do: Atom.to_string(v)
  defp attr_value(v) when is_number(v), do: fmt(v)

  defp attr_value({:points, pts}) do
    Enum.map_join(pts, " ", fn {x, y} -> [fmt(x), ",", fmt(y)] end)
  end

  defp attr_value(cmd) when is_tuple(cmd), do: path_io([cmd])

  defp attr_value(v) when is_list(v) do
    if path?(v), do: path_io(v), else: v
  end

  # Path data is a (possibly nested) list of command tuples; anything else in
  # an attribute is plain iodata.
  defp path?(list) when is_list(list), do: Enum.any?(list, &path?/1)
  defp path?(:close), do: true
  defp path?(cmd) when is_tuple(cmd), do: true
  defp path?(_), do: false

  @doc """
  Renders a list of path commands into the `d` attribute's iodata.

  Commands are separated by a single space; empty entries (an `if` that chose
  not to emit a corner arc, say) drop out, and nesting is flattened.
  """
  def path_io(commands) do
    commands
    |> List.flatten()
    |> Enum.map(&command_io/1)
    |> Enum.intersperse(" ")
  end

  defp command_io({:move, x, y}), do: ["M ", fmt(x), " ", fmt(y)]
  defp command_io({:rmove, dx, dy}), do: ["m ", fmt(dx), " ", fmt(dy)]
  defp command_io({:line, x, y}), do: ["L ", fmt(x), " ", fmt(y)]
  defp command_io({:hline, x}), do: ["H ", fmt(x)]
  defp command_io({:vline, y}), do: ["V ", fmt(y)]

  defp command_io({:curve, x1, y1, x2, y2, x, y}) do
    ["C ", fmt(x1), " ", fmt(y1), " ", fmt(x2), " ", fmt(y2), " ", fmt(x), " ", fmt(y)]
  end

  defp command_io({:arc, rx, ry, rotation, large_arc, sweep, x, y}) do
    [
      "A ",
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

  defp command_io(:close), do: "Z"

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
  def move(x, y), do: {:move, x, y}

  @doc "SVG path relative move command."
  def rmove(dx, dy), do: {:rmove, dx, dy}

  @doc "SVG path line command."
  def line(x, y), do: {:line, x, y}

  @doc "SVG path horizontal line command."
  def hline(x), do: {:hline, x}

  @doc "SVG path vertical line command."
  def vline(y), do: {:vline, y}

  @doc "SVG cubic bezier command."
  def curve(x1, y1, x2, y2, x, y), do: {:curve, x1, y1, x2, y2, x, y}

  @doc "SVG arc command."
  def arc(rx, ry, rotation, large_arc, sweep, x, y) do
    {:arc, rx, ry, rotation, large_arc, sweep, x, y}
  end

  @doc "SVG path close command."
  def close, do: :close

  @doc "A `<polygon>`/`<polyline>` `points` attribute, from `{x, y}` pairs."
  def points(pairs), do: {:points, pairs}
end
