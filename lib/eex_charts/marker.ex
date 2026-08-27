defmodule EexCharts.Marker do
  @moduledoc """
  Marker shape paths, ported from ApexCharts `Graphics.getMarkerPath`.

  `size` is the marker radius. Each shape applies the same grow/shrink factor
  ApexCharts does so a triangle and a circle of the same configured size look
  equally heavy.
  """

  import EexCharts.SVG

  @cross_shrink 1.1
  @plus_shrink 1.12
  @star_grow 1.15
  @sparkle_shrink 1.1
  @square_shrink 1.125
  @diamond_grow 1.05
  @line_shrink 1.1

  @doc """
  Renders one marker as an SVG element, choosing `<circle>` for the (common)
  circular case and `<path>` for every other shape.

  `attrs` are merged onto the element (class, data attributes, fill, stroke…).
  """
  def render(shape, x, y, size, attrs) do
    case normalize(shape) do
      :circle -> el("circle", Map.merge(attrs, %{cx: x, cy: y, r: size}))
      s -> el("path", Map.merge(attrs, %{d: path(s, x, y, size)}))
    end
  end

  @doc "The SVG path data for a marker shape centered on `{x, y}`."
  def path(shape, x, y, size) do
    case normalize(shape) do
      :cross ->
        s = size / @cross_shrink

        [
          move(x - s, y - s),
          line(x + s, y + s),
          " ",
          move(x - s, y + s),
          line(x + s, y - s)
        ]

      :plus ->
        s = size / @plus_shrink
        [move(x - s, y), line(x + s, y), " ", move(x, y - s), line(x, y + s)]

      :star ->
        star_path(x, y, size * @star_grow, 5)

      :sparkle ->
        star_path(x, y, size * @star_grow / @sparkle_shrink, 4)

      :triangle ->
        [move(x, y - size), line(x + size, y + size), line(x - size, y + size), " Z"]

      :square ->
        s = size / @square_shrink

        [
          move(x - s, y - s),
          line(x + s, y - s),
          line(x + s, y + s),
          line(x - s, y + s),
          " Z"
        ]

      :diamond ->
        s = size * @diamond_grow
        [move(x, y - s), line(x + s, y), line(x, y + s), line(x - s, y), " Z"]

      :line ->
        s = size / @line_shrink
        [move(x - s, y), line(x + s, y)]

      _circle ->
        [
          move(x, y),
          " m ",
          fmt(-size),
          " 0",
          arc(size, size, 0, 1, 0, size * 2, 0),
          arc(size, size, 0, 1, 0, -size * 2, 0)
        ]
    end
  end

  defp star_path(x, y, size, points) do
    step = :math.pi() / points

    0..(2 * points)
    |> Enum.map(fn i ->
      angle = i * step
      radius = if rem(i, 2) == 0, do: size, else: size / 2
      px = x + radius * :math.sin(angle)
      py = y - radius * :math.cos(angle)
      if i == 0, do: move(px, py), else: line(px, py)
    end)
    |> Kernel.++([" Z"])
  end

  @doc """
  Resolves the shape for series `i` — `markers.shape` may be a single shape or
  a per-series list (ApexCharts' array form).
  """
  def shape_for(shape, i) when is_list(shape) do
    case shape do
      [] -> :circle
      list -> Enum.at(list, rem(i, length(list)))
    end
  end

  def shape_for(shape, _i), do: shape

  defp normalize(s) when is_binary(s), do: normalize(String.to_atom(s))
  defp normalize(:rect), do: :square
  defp normalize(s) when is_atom(s), do: s
  defp normalize(_), do: :circle
end
