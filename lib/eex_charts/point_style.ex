defmodule EexCharts.PointStyle do
  @moduledoc """
  Paint for one data point: the single place that turns a series and a data
  point into fill, stroke and class for the mark that draws it.

  ## Precedence

  From strongest to weakest:

    1. the data point: `fill_color`, `stroke_color` and `fill` (a fill map)
       on a map point, as ApexCharts' per-point `fillColor` / `strokeColor`;
    2. the series: `fill`, a map like the global one;
    3. the global `fill` option;
    4. the mark's base colour (series, distributed or kind colour).

  A fill map is `%{type: :solid | :none | :pattern, opacity: number,
  pattern: %{style:, width:, height:, stroke_width:}}`; the maps are
  deep-merged in the order above.

  ## Fill types

    * `:solid` (default) - the colour, at `opacity`.
    * `:none` - outline only: no fill, a stroke in the mark's colour (or the
      point's `stroke_color`), at least 2px wide so the outline shows
      under every theme.
    * `:pattern` - ApexCharts v4.7.0 pattern fills. `pattern.style` is one of
      `:vertical_lines`, `:horizontal_lines`, `:slanted_lines`, `:squares`,
      `:circles` (or a list indexed by series; a series without an entry is
      solid, as in v4.7.0). Defaults: `:squares`, 6 x 6, stroke width 2. The
      lines take the mark's colour and the tile background stays
      transparent, so the page shows through on light, dark and daisyUI
      surfaces.

  A point carrying its own paint, and every outline or pattern mark, gets the
  `eexcharts-point-styled` class so CSS can re-tint it per theme.

  ## Patterns and `<defs>`

  `resolve/4` returns a pattern fill as `{:pattern, spec}`. A chart resolves
  the style of every mark, then calls `link/2` once: it swaps each pattern
  for `url(#<chart id>-pattern-<n>)`, one `<pattern>` per distinct (style,
  colour, size), and returns the `<defs>` to emit next to the marks, the same
  way area gradients are emitted.
  """

  import EexCharts.SVG

  alias EexCharts.Config

  @outline_width 2

  @pattern_defaults %{style: :squares, width: 6, height: 6, stroke_width: 2}

  @styled_class "eexcharts-point-styled"

  @doc """
  Resolves the paint of one mark.

  `point` is the raw data point (a number, list or map); only maps carry
  overrides. Returns `%{fill:, fill_opacity:, stroke:, stroke_width:, class:}`
  where `fill` is a colour, `"none"` or `{:pattern, spec}` (see `link/2`),
  `stroke` is `nil` when the chart's own stroke applies, and `class` is
  `"eexcharts-point-styled"` or `nil`.
  """
  def resolve(cfg, series, point, base_color) do
    overrides = point_overrides(point)
    fill = fill_spec(cfg, series, overrides)
    color = overrides[:fill_color] || base_color
    stroke = overrides[:stroke_color]
    base_width = Config.color_for(cfg.stroke.width, series_index(series))

    case paint(fill, color, series) do
      :none ->
        %{
          fill: "none",
          fill_opacity: fill.opacity,
          stroke: stroke || color,
          stroke_width: max(num(base_width), @outline_width),
          class: @styled_class
        }

      paint ->
        %{
          fill: paint,
          fill_opacity: fill.opacity,
          stroke: stroke,
          stroke_width: stroke_width(stroke, base_width),
          class: if(styled?(overrides, paint), do: @styled_class)
        }
    end
  end

  @doc """
  The point's own colour for a line drawn for it (a dumbbell connector):
  `stroke_color`, else `fill_color`, else `nil`.
  """
  def line_color(point) do
    overrides = point_overrides(point)
    overrides[:stroke_color] || overrides[:fill_color]
  end

  @doc "Whether `style` leaves the page visible under the mark (outline or pattern)."
  def see_through?(%{fill: "none"}), do: true
  def see_through?(%{fill: {:pattern, _}}), do: true
  def see_through?(%{fill: "url(" <> _}), do: true
  def see_through?(_style), do: false

  @doc """
  Colour for a data label drawn on the mark. `on_mark` is the label colour for
  a filled mark (white, or a daisyUI `*-content`); an outline mark's label sits
  on the page instead, so it takes the outline colour, and a pattern mark's
  takes `chart.fore_color`.
  """
  def label_color(cfg, style, on_mark) do
    case style do
      %{fill: "none", stroke: stroke} -> stroke
      _ -> if see_through?(style), do: cfg.chart.fore_color, else: on_mark
    end
  end

  @doc """
  Replaces every pattern fill in `items` (maps with a `:style` from
  `resolve/4`) by a `url(#…)` reference, and returns
  `{items, defs}` with one `<pattern>` per distinct pattern, ids
  `"<chart_id>-pattern-<n>"`. `defs` is `[]` when nothing is patterned.
  """
  def link(items, chart_id) do
    specs =
      items
      |> Enum.flat_map(fn
        %{style: %{fill: {:pattern, spec}}} -> [spec]
        _ -> []
      end)
      |> Enum.uniq()

    ids =
      specs |> Enum.with_index(fn spec, n -> {spec, "#{chart_id}-pattern-#{n}"} end) |> Map.new()

    items =
      Enum.map(items, fn
        %{style: %{fill: {:pattern, spec}} = style} = item ->
          %{item | style: %{style | fill: "url(##{ids[spec]})"}}

        item ->
          item
      end)

    defs =
      case specs do
        [] -> []
        _ -> el("defs", %{}, Enum.map(specs, &pattern_el(&1, ids[&1])))
      end

    {items, defs}
  end

  # ── Resolution ───────────────────────────────────────────────────────────

  defp point_overrides(%{} = point) when not is_struct(point),
    do: Map.take(point, [:fill_color, :stroke_color, :fill])

  defp point_overrides(_point), do: %{}

  defp fill_spec(cfg, series, overrides) do
    [series_fill(series), overrides[:fill]]
    |> Enum.filter(&is_map/1)
    |> Enum.reduce(cfg.fill, &Config.deep_merge(&2, &1))
    |> Map.put_new(:opacity, 1)
  end

  defp series_fill(%{} = series), do: Map.get(series, :fill)
  defp series_fill(_series), do: nil

  defp series_index(%{index: i}), do: i
  defp series_index(_series), do: 0

  defp paint(%{type: :none}, _color, _series), do: :none

  defp paint(%{type: :pattern} = fill, color, series) do
    p = Map.merge(@pattern_defaults, fill[:pattern] || %{})
    i = series_index(series)

    case Config.color_for(p.style, i) do
      nil ->
        color

      style ->
        {:pattern,
         %{
           style: style,
           color: color,
           width: p.width,
           height: p.height,
           stroke_width: Config.color_for(p.stroke_width, i)
         }}
    end
  end

  defp paint(_fill, color, _series), do: color

  defp styled?(overrides, paint), do: map_size(overrides) > 0 or match?({:pattern, _}, paint)

  # A point's `stroke_color` on a mark without a stroke (bars default to
  # width 0) would be invisible; give it the outline width instead.
  defp stroke_width(nil, base), do: base
  defp stroke_width(_stroke, base), do: if(num(base) > 0, do: base, else: @outline_width)

  defp num(n) when is_number(n), do: n
  defp num(_), do: 0

  # ── Pattern tiles (ApexCharts v4.7.0 `Graphics.drawPattern`) ─────────────
  #
  # v4.7.0 draws each tile in user space: lines along the tile's top or left
  # edge (so half of their stroke is clipped, and the line styles get one
  # extra pixel of width to compensate), a diagonal corner to corner, or an
  # unfilled square / circle the size of the tile.

  defp pattern_el(spec, id) do
    %{width: w, height: h, color: color, stroke_width: sw} = spec

    el(
      "pattern",
      %{id: id, x: 0, y: 0, width: w, height: h, patternUnits: "userSpaceOnUse"},
      tile(spec.style, w, h, color, sw)
    )
  end

  defp tile(:horizontal_lines, _w, h, color, sw),
    do: el("line", %{x1: 0, y1: 0, x2: h, y2: 0, stroke: color, stroke_width: sw + 1})

  defp tile(:vertical_lines, w, _h, color, sw),
    do: el("line", %{x1: 0, y1: 0, x2: 0, y2: w, stroke: color, stroke_width: sw + 1})

  defp tile(:slanted_lines, w, h, color, sw),
    do: el("line", %{x1: 0, y1: 0, x2: w, y2: h, stroke: color, stroke_width: sw})

  defp tile(:squares, w, h, color, sw),
    do:
      el("rect", %{
        x: 0,
        y: 0,
        width: w,
        height: h,
        fill: "none",
        stroke: color,
        stroke_width: sw
      })

  defp tile(:circles, w, _h, color, sw),
    do:
      el("circle", %{
        cx: w / 2,
        cy: w / 2,
        r: w / 2,
        fill: "none",
        stroke: color,
        stroke_width: sw
      })
end
