defmodule EexCharts.Annotations do
  @moduledoc """
  Chart annotations (y-axis lines/bands, x-axis lines/bands, labeled points),
  modeled on ApexCharts' `annotations` option (v4.7.0).

  Rendered into the cartesian grid, between the data labels and the axes.

  ## Config shape

      annotations: %{
        yaxis: [%{y: 40, border_color: "#00E396", label: %{text: "target"}}],
        xaxis: [%{x: "Mar", x2: "May", fill_color: "#B3F7CA", label: %{text: "spring"}}],
        points: [%{x: "Apr", y: 55, marker: %{size: 6}, label: %{text: "peak"}}]
      }

  Each annotation is deep-merged over a defaults map (ported from
  `Options.js`), so partial maps — including partial `label`/`style`/`marker`
  sub-maps — inherit every unspecified option.

  ### y-axis annotations

  `%{y:, y2:, border_color:, border_width:, stroke_dash_array:, fill_color:,
  opacity:, offset_x:, offset_y:, label:}`. `y` alone draws a horizontal dashed
  line at `Layout.y_for(l, y)`. `y` + `y2` draws a translucent band between the
  two values. The label is a pill (rect + text) placed at the line/band per
  `label.position` (`:left` / `:center` / `:right`).

  ### Stroke patterns

  Lines and band borders of x and y annotations take

    * `stroke_dash_array`: a number (equal dashes and gaps, the default `1`
      draws a fine dotted line; `0` is solid) or a full pattern, as a list
      (`[6, 3, 1, 3]`) or a string (`"6 3 1 3"`). The pattern is emitted
      verbatim as `stroke-dasharray`; invalid patterns draw solid.
    * `stroke_linecap`: `:butt`, `:round` or `:square`. Unset (the default)
      leaves the SVG default, butt. Caps apply to every dash, so `:round`
      with a `[0, 6]` pattern draws a row of dots.

  ### x-axis annotations

  `%{x:, x2:, ...same styling..., label:}`. `x` alone draws a vertical line,
  `x` + `x2` a translucent band.

  On a value x-axis (numeric or datetime, see `Layout.value_x?/1`, e.g. a
  scatter chart) x-values are data values, as in ApexCharts: a number is
  placed on the x scale, and a datetime axis also accepts `DateTime`,
  `NaiveDateTime`, `Date` and ISO 8601 strings. Values outside the axis range
  are skipped.

  On a category axis, x-values are resolved to a category slot:

    * when the chart has categories (`cfg.xaxis.categories`), the value is
      matched (as a string) against the category list and its index is used;
      an integer that matches no category is treated as a 0-based index;
    * when there are no categories, a bare number is used directly as a
      0-based category index.

  Values resolving outside `0..n-1` are skipped. x-axis labels default to
  `orientation: :vertical` (rotated -90 like ApexCharts); `:horizontal` is
  supported.

  ### point annotations

  `%{x:, y:, marker: %{size:, fill_color:, stroke_color:, stroke_width:,
  shape:}, label:}`. Draws a marker (circle or square) at the data position
  with a label pill above it. `x` resolves like an x-axis annotation's.

  `tooltip: "text"` adds a hover tooltip to the point. It reuses the chart's
  tooltip box and the stock hook: an invisible hover target over the marker
  carries `data-j="anno-<k>"` and the tooltip HTML holds a matching tip, so
  no extra JavaScript is involved. Works with `tooltip.enabled: false` too;
  `push_hover` events are not sent for annotation tips. Static SVG output
  (`EexCharts.to_svg/4`) drops it.

  ## Horizontal bar charts (`layout.horizontal`)

  The value axis is horizontal and the category axis vertical, so annotations
  are mirrored:

    * y-axis (value) annotations become **vertical** lines/bands positioned via
      `Layout.x_for`; `label.position` maps to vertical placement
      (`:right` -> top, `:center` -> middle, `:left` -> bottom).
    * x-axis (category) annotations become **horizontal** lines/bands
      positioned via `Layout.category_pos`; the label is not rotated and
      `label.position` maps to horizontal placement (`:top` -> left,
      `:center` -> center, `:bottom` -> right).

  ## Escaping

  All user-provided label text is escaped through `EexCharts.SVG.esc/1`.
  """

  import EexCharts.SVG, only: [el: 2, el: 3, esc: 1]

  alias EexCharts.{Config, Layout}

  @doc "Renders all configured annotations into the cartesian grid."
  def render(cfg, %Layout{} = l) do
    anns = cfg[:annotations] || %{}
    yaxis = Map.get(anns, :yaxis, []) || []
    xaxis = Map.get(anns, :xaxis, []) || []
    points = Map.get(anns, :points, []) || []

    if yaxis == [] and xaxis == [] and points == [] do
      []
    else
      children =
        group("eexcharts-yaxis-annotations", yaxis, &yaxis_annotation(cfg, l, &1)) ++
          group("eexcharts-xaxis-annotations", xaxis, &xaxis_annotation(cfg, l, &1)) ++
          group("eexcharts-point-annotations", points, &point_annotation(cfg, l, &1))

      el("g", %{class: "eexcharts-annotations"}, children)
    end
  end

  defp group(_class, [], _fun), do: []

  defp group(class, list, fun) do
    [el("g", %{class: class}, Enum.map(list, fun))]
  end

  # ── y-axis annotations ────────────────────────────────────────────────────

  defp yaxis_annotation(cfg, l, anno0) do
    anno = Config.deep_merge(yaxis_defaults(), anno0)

    if l.horizontal do
      yaxis_horizontal(cfg, l, anno)
    else
      yaxis_vertical(cfg, l, anno)
    end
  end

  # Vertical chart: value axis is y -> horizontal line / band.
  defp yaxis_vertical(cfg, l, anno) do
    cond do
      not is_number(anno.y) ->
        []

      is_nil(anno.y2) ->
        if in_range?(l, anno.y) do
          py = Layout.y_for(l, anno.y) + anno.offset_y
          x1 = l.grid_x + anno.offset_x
          x2 = l.grid_x + l.grid_w + anno.offset_x
          [line(anno, x1, py, x2, py), yaxis_label(cfg, l, anno, py)]
        else
          []
        end

      band_visible?(l, anno.y, anno.y2) ->
        p1 = Layout.y_for(l, clamp(l, anno.y)) + anno.offset_y
        p2 = Layout.y_for(l, clamp(l, anno.y2)) + anno.offset_y
        top = min(p1, p2)
        x = l.grid_x + anno.offset_x
        [band(anno, x, top, l.grid_w, abs(p1 - p2)), yaxis_label(cfg, l, anno, top)]

      true ->
        []
    end
  end

  # Horizontal bar chart: value axis is x -> vertical line / band.
  defp yaxis_horizontal(cfg, l, anno) do
    cond do
      not is_number(anno.y) ->
        []

      is_nil(anno.y2) ->
        if in_range?(l, anno.y) do
          px = Layout.x_for(l, anno.y) + anno.offset_x
          y1 = l.grid_y + anno.offset_y
          y2 = l.grid_y + l.grid_h + anno.offset_y
          [line(anno, px, y1, px, y2), yaxis_label_h(cfg, l, anno, px)]
        else
          []
        end

      band_visible?(l, anno.y, anno.y2) ->
        p1 = Layout.x_for(l, clamp(l, anno.y)) + anno.offset_x
        p2 = Layout.x_for(l, clamp(l, anno.y2)) + anno.offset_x
        left = min(p1, p2)
        y = l.grid_y + anno.offset_y
        [band(anno, left, y, abs(p1 - p2), l.grid_h), yaxis_label_h(cfg, l, anno, left)]

      true ->
        []
    end
  end

  # Label for a horizontal value line (vertical chart). position picks the
  # horizontal anchor along the line.
  defp yaxis_label(cfg, l, anno, py) do
    label = anno.label
    fs = label.style.font_size

    x =
      case label.position do
        :right -> l.grid_x + l.grid_w
        :center -> l.grid_x + l.grid_w / 2
        _ -> l.grid_x
      end

    label_pill(cfg, x + label.offset_x, py + label.offset_y - 3 - fs / 2, label)
  end

  # Label for a vertical value line (horizontal chart). position picks the
  # vertical placement along the line.
  defp yaxis_label_h(cfg, l, anno, px) do
    label = anno.label
    fs = label.style.font_size

    y =
      case label.position do
        :right -> l.grid_y + fs
        :center -> l.grid_y + l.grid_h / 2
        _ -> l.grid_y + l.grid_h - fs
      end

    label_pill(cfg, px + label.offset_x, y + label.offset_y, label)
  end

  # ── x-axis annotations ────────────────────────────────────────────────────

  defp xaxis_annotation(cfg, l, anno0) do
    anno = Config.deep_merge(xaxis_defaults(), anno0)

    if l.horizontal do
      xaxis_horizontal(cfg, l, anno)
    else
      xaxis_vertical(cfg, l, anno)
    end
  end

  # Vertical chart: category axis is x -> vertical line / band.
  defp xaxis_vertical(cfg, l, anno) do
    with {:ok, x1} <- x_pos(cfg, l, anno.x) do
      case maybe_x2(cfg, l, anno) do
        nil ->
          px = x1 + anno.offset_x
          y1 = l.grid_y + anno.offset_y
          y2 = l.grid_y + l.grid_h + anno.offset_y
          [line(anno, px, y1, px, y2), xaxis_label(cfg, l, anno, px)]

        x2 ->
          left = min(x1, x2) + anno.offset_x
          y = l.grid_y + anno.offset_y
          [band(anno, left, y, abs(x2 - x1), l.grid_h), xaxis_label(cfg, l, anno, left)]
      end
    else
      _ -> []
    end
  end

  # Horizontal bar chart: category axis is y -> horizontal line / band.
  defp xaxis_horizontal(cfg, l, anno) do
    with {:ok, y1} <- x_pos(cfg, l, anno.x) do
      case maybe_x2(cfg, l, anno) do
        nil ->
          py = y1 + anno.offset_y
          x1 = l.grid_x + anno.offset_x
          x2 = l.grid_x + l.grid_w + anno.offset_x
          [line(anno, x1, py, x2, py), xaxis_label_h(cfg, l, anno, py)]

        y2 ->
          top = min(y1, y2) + anno.offset_y
          x = l.grid_x + anno.offset_x
          [band(anno, x, top, l.grid_w, abs(y2 - y1)), xaxis_label_h(cfg, l, anno, top)]
      end
    else
      _ -> []
    end
  end

  defp maybe_x2(cfg, l, anno) do
    if is_nil(anno.x2) do
      nil
    else
      case x_pos(cfg, l, anno.x2) do
        {:ok, p} -> p
        :skip -> nil
      end
    end
  end

  # Label for a vertical category line (vertical chart).
  defp xaxis_label(cfg, l, anno, px) do
    label = anno.label
    fs = label.style.font_size
    vertical = vertical?(label)

    # A vertical pill is rotated -90 about its center, so its along-text
    # length becomes its height. Like ApexCharts, which shifts the label down
    # by its width before rotating, hang it from the plot edge by half that
    # length; centering it `fs` below the edge pushed long labels past the top.
    reach = if vertical, do: pill_half_length(label), else: fs

    y =
      case label.position do
        :bottom -> l.grid_y + l.grid_h - reach
        :center -> l.grid_y + l.grid_h / 2
        _ -> l.grid_y + reach
      end

    io = label_pill(cfg, px + label.offset_x, y + label.offset_y, label)

    if vertical do
      rotate(io, px + label.offset_x, y + label.offset_y)
    else
      io
    end
  end

  # Label for a horizontal category line (horizontal chart); not rotated.
  defp xaxis_label_h(cfg, l, anno, py) do
    label = anno.label

    x =
      case label.position do
        :bottom -> l.grid_x + l.grid_w
        :center -> l.grid_x + l.grid_w / 2
        _ -> l.grid_x
      end

    label_pill(cfg, x + label.offset_x, py + label.offset_y, label)
  end

  # ── point annotations ─────────────────────────────────────────────────────

  defp point_annotation(cfg, l, anno0) do
    anno = Config.deep_merge(point_defaults(), anno0)

    with {:ok, {cx, cy}} <- point_place(cfg, l, anno) do
      m = anno.marker
      label = anno.label
      fs = label.style.font_size
      above = cy + label.offset_y - m.size - fs / 1.6
      below = cy + label.offset_y + m.size + fs / 1.6
      {lx, ly} = fit_point_label(l, label, cx + label.offset_x, above, below)

      [marker(m, cx, cy), label_pill(cfg, lx, ly, label)]
    else
      _ -> []
    end
  end

  # Marker centre of a (defaults-merged) point annotation, or `:skip`.
  defp point_place(cfg, l, anno) do
    with {:ok, px0} <- x_pos(cfg, l, anno.x),
         true <- is_number(anno.y) and in_range?(l, anno.y) do
      {:ok, point_coords(l, px0, anno.y, anno.marker)}
    else
      _ -> :skip
    end
  end

  # ── point annotation tooltips ─────────────────────────────────────────────

  @doc """
  Transparent hover targets over every point annotation that has a
  `tooltip`. Rendered last (above the category hover zones) so the pointer
  reaches them; each carries `data-j="anno-<k>"` (k = position in
  `annotations.points`), which the stock hook resolves to the tip of the same
  `data-j` from `tooltips/1`.
  """
  def hover_targets(cfg, %Layout{} = l) do
    targets =
      for {anno, k} <- tooltip_points(cfg),
          {:ok, {cx, cy}} <- [point_place(cfg, l, anno)] do
        el("circle", %{
          class: "eexcharts-annotation-hover",
          cx: cx,
          cy: cy,
          r: max(anno.marker.size + 4, 8),
          fill: "transparent",
          data_j: "anno-#{k}"
        })
      end

    if targets == [], do: [], else: el("g", %{class: "eexcharts-annotation-hovers"}, targets)
  end

  @doc "Server-rendered tooltip bodies for the point annotations' `tooltip` text."
  def tooltips(cfg) do
    for {anno, k} <- tooltip_points(cfg) do
      el("div", %{class: "eexcharts-tip", data_j: "anno-#{k}", hidden: true}, [
        el("div", %{class: "eexcharts-tip-row"}, esc(to_string(anno.tooltip)))
      ])
    end
  end

  defp tooltip_points(cfg) do
    anns = cfg[:annotations] || %{}

    (Map.get(anns, :points, []) || [])
    |> Enum.with_index()
    |> Enum.map(fn {a, k} -> {Config.deep_merge(point_defaults(), a), k} end)
    |> Enum.reject(fn {a, _k} -> blank?(a.tooltip) end)
  end

  # Keeps a point label's pill inside the plot. The default spot (centered
  # above the marker) is kept whenever it fits; a pill that would cross the
  # top edge flips below the marker, and one that would cross the left or
  # right edge slides inward. `x` is the text anchor, `above`/`below` are the
  # candidate text centers.
  defp fit_point_label(l, label, x, above, below) do
    if blank?(label.text) do
      {x, above}
    else
      {left, right, up, down} = pill_extent(label, x)
      top_edge = l.grid_y
      bottom_edge = l.grid_y + l.grid_h

      y =
        cond do
          above - up >= top_edge -> above
          below + down <= bottom_edge -> below
          true -> above
        end

      dx =
        cond do
          right - left > l.grid_w -> 0
          left < l.grid_x -> l.grid_x - left
          right > l.grid_x + l.grid_w -> l.grid_x + l.grid_w - right
          true -> 0
        end

      {x + dx, y}
    end
  end

  # Horizontal span and the reach above and below the text center of a label pill anchored at `x`, with the
  # stroke included. Mirrors the rect geometry in `label_pill/4`.
  defp pill_extent(label, x) do
    style = label.style
    pad = style.padding
    tw = Layout.text_width(label.text, style.font_size)
    s = label.border_width / 2

    left =
      case anchor_str(label.text_anchor) do
        "end" -> x - tw - pad.left
        "middle" -> x - tw / 2 - pad.left
        _ -> x - pad.left
      end

    right = left + tw + pad.left + pad.right
    {left - s, right + s, style.font_size / 2 + pad.top + s, style.font_size / 2 + pad.bottom + s}
  end

  defp point_coords(l, px0, y, m) do
    if l.horizontal do
      # value axis horizontal, category axis vertical
      {Layout.x_for(l, y) + m.offset_x, px0 + m.offset_y}
    else
      {px0 + m.offset_x, Layout.y_for(l, y) + m.offset_y}
    end
  end

  defp marker(m, cx, cy) do
    size = m.size

    attrs = %{
      fill: m.fill_color,
      stroke: m.stroke_color,
      stroke_width: m.stroke_width,
      class: "eexcharts-annotation-marker"
    }

    case marker_shape(m.shape) do
      :square ->
        el(
          "rect",
          Map.merge(attrs, %{x: cx - size, y: cy - size, width: size * 2, height: size * 2})
        )

      _ ->
        el("circle", Map.merge(attrs, %{cx: cx, cy: cy, r: size}))
    end
  end

  defp marker_shape(s) when s in [:square, :rect, "square", "rect"], do: :square
  defp marker_shape(_), do: :circle

  # ── shared drawing helpers ───────────────────────────────────────────────

  defp line(anno, x1, y1, x2, y2) do
    el("line", %{
      x1: x1,
      y1: y1,
      x2: x2,
      y2: y2,
      stroke: anno.border_color,
      stroke_width: anno.border_width,
      stroke_dasharray: dash(anno.stroke_dash_array),
      stroke_linecap: linecap(anno.stroke_linecap),
      class: "eexcharts-annotation-line"
    })
  end

  defp band(anno, x, y, w, h) do
    el("rect", %{
      x: x,
      y: y,
      width: w,
      height: h,
      fill: anno.fill_color,
      fill_opacity: anno.opacity,
      stroke: anno.border_color,
      stroke_width: anno.border_width,
      stroke_dasharray: dash(anno.stroke_dash_array),
      stroke_linecap: linecap(anno.stroke_linecap),
      class: "eexcharts-annotation-rect"
    })
  end

  # `stroke_dash_array`: a number (dash = gap), or a full pattern as a list
  # (`[6, 3, 1, 3]`) or a string (`"6 3 1 3"`, commas allowed). 0, nil and
  # an empty pattern draw a solid stroke.
  defp dash(v) when is_number(v) and v <= 0, do: nil
  defp dash(v) when is_number(v), do: v
  defp dash(v) when is_binary(v), do: v |> String.split([" ", ","], trim: true) |> dash()

  defp dash(v) when is_list(v) do
    nums = Enum.map(v, &dash_number/1)

    if nums == [] or Enum.any?(nums, &is_nil/1) or Enum.all?(nums, &(&1 == 0)),
      do: nil,
      else: Enum.map_join(nums, " ", &EexCharts.SVG.fmt/1)
  end

  defp dash(_v), do: nil

  defp dash_number(n) when is_number(n) and n >= 0, do: n

  defp dash_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, ""} when n >= 0 -> n
      _ -> nil
    end
  end

  defp dash_number(_), do: nil

  # `stroke_linecap`: :butt / :round / :square (atoms or strings). Unset or
  # unknown leaves the attribute off, so the SVG default (butt) applies.
  defp linecap(c) when c in [:butt, :round, :square], do: Atom.to_string(c)
  defp linecap(c) when c in ["butt", "round", "square"], do: c
  defp linecap(_c), do: nil

  # Label pill: rect background + centered text. `y` is the vertical center of
  # the text. Returns [] when there is no label text.
  defp label_pill(cfg, x, y, label) do
    text = label.text

    if blank?(text) do
      []
    else
      style = label.style
      fs = style.font_size
      pad = style.padding
      anchor = anchor_str(label.text_anchor)
      tw = Layout.text_width(text, fs)

      rect_x =
        case anchor do
          "end" -> x - tw - pad.left
          "middle" -> x - tw / 2 - pad.left
          _ -> x - pad.left
        end

      rect =
        el("rect", %{
          x: rect_x,
          y: y - fs / 2 - pad.top,
          width: tw + pad.left + pad.right,
          height: fs + pad.top + pad.bottom,
          rx: label.border_radius,
          fill: style.background,
          stroke: label.border_color,
          stroke_width: label.border_width,
          class: "eexcharts-annotation-label-rect"
        })

      txt =
        el(
          "text",
          %{
            x: x,
            y: y,
            text_anchor: anchor,
            dominant_baseline: "central",
            fill: style.color || cfg.chart.fore_color,
            font_size: fs,
            font_weight: style.font_weight,
            class: "eexcharts-annotation-label"
          },
          esc(text)
        )

      [rect, txt]
    end
  end

  # Half the pill's extent along the text, stroke included.
  defp pill_half_length(label) do
    pad = label.style.padding
    tw = if blank?(label.text), do: 0, else: Layout.text_width(label.text, label.style.font_size)
    (tw + pad.left + pad.right + label.border_width) / 2
  end

  defp rotate([], _x, _y), do: []

  defp rotate(io, x, y) do
    el("g", %{transform: EexCharts.SVG.rotate(-90, x, y)}, io)
  end

  defp vertical?(label) do
    to_string(Map.get(label, :orientation, :vertical)) == "vertical"
  end

  defp anchor_str(a) when a in [:start, "start", :left], do: "start"
  defp anchor_str(a) when a in [:end, "end", :right], do: "end"
  defp anchor_str(_), do: "middle"

  defp blank?(nil), do: true
  defp blank?(t) when is_binary(t), do: String.trim(t) == ""
  defp blank?(_), do: false

  # ── value / category resolution ───────────────────────────────────────────

  defp in_range?(l, v) when is_number(v) do
    {mn, mx} = scale_range(l)
    v >= mn and v <= mx
  end

  defp clamp(l, v) do
    {mn, mx} = scale_range(l)
    v |> max(mn) |> min(mx)
  end

  # Band visible unless both bounds fall off the same side of the scale.
  defp band_visible?(l, a, b) when is_number(a) and is_number(b) do
    {mn, mx} = scale_range(l)
    not ((a < mn and b < mn) or (a > mx and b > mx))
  end

  defp band_visible?(_l, _a, _b), do: false

  defp scale_range(l), do: {l.scale.nice_min, l.scale.nice_max}

  # Resolves an x annotation value to a pixel position on the x-axis, or
  # `:skip` when it can't be placed. See moduledoc for the resolution rule.
  defp x_pos(cfg, %Layout{x_scale: xs} = l, x) when is_map(xs) do
    case axis_value(Layout.x_type(cfg), x) do
      v when is_number(v) and v >= xs.nice_min and v <= xs.nice_max ->
        {:ok, Layout.x_value_pos(l, v)}

      _ ->
        :skip
    end
  end

  defp x_pos(cfg, l, x) do
    case resolve_index(cfg, x) do
      nil ->
        :skip

      idx when is_number(idx) ->
        if idx < 0 or idx > l.n - 1 do
          :skip
        else
          {:ok, Layout.category_pos(l, idx)}
        end
    end
  end

  # A value x-axis takes data values: numbers, and on a datetime axis anything
  # `Layout.to_x/2` turns into unix ms. Strings that parse as no date stay
  # unplaced rather than landing on the epoch.
  defp axis_value(_type, x) when is_number(x), do: x
  defp axis_value(:datetime, %{__struct__: _} = x), do: Layout.to_x(x, :datetime)

  defp axis_value(:datetime, x) when is_binary(x) do
    if valid_date?(x), do: Layout.to_x(x, :datetime)
  end

  defp axis_value(_type, _x), do: nil

  defp valid_date?(s) do
    match?({:ok, _, _}, DateTime.from_iso8601(s)) or
      match?({:ok, _}, NaiveDateTime.from_iso8601(s)) or
      match?({:ok, _}, Date.from_iso8601(s))
  end

  defp resolve_index(cfg, x) do
    cats = cfg.xaxis.categories

    cond do
      cats in [nil, []] ->
        if is_number(x), do: x, else: nil

      true ->
        s = to_string(x)

        case Enum.find_index(cats, fn c -> to_string(c) == s end) do
          nil -> if is_integer(x), do: x, else: nil
          i -> i
        end
    end
  end

  # ── defaults (ported from Options.js, snake_case, numeric font sizes) ──────

  defp yaxis_defaults do
    %{
      y: nil,
      y2: nil,
      stroke_dash_array: 1,
      stroke_linecap: nil,
      fill_color: "#c2c2c2",
      border_color: "#c2c2c2",
      border_width: 1,
      opacity: 0.3,
      offset_x: 0,
      offset_y: 0,
      label: label_defaults(text_anchor: :end, position: :right, offset_y: -3)
    }
  end

  defp xaxis_defaults do
    %{
      x: nil,
      x2: nil,
      stroke_dash_array: 1,
      stroke_linecap: nil,
      fill_color: "#c2c2c2",
      border_color: "#c2c2c2",
      border_width: 1,
      opacity: 0.3,
      offset_x: 0,
      offset_y: 0,
      label:
        label_defaults(text_anchor: :middle, position: :top, orientation: :vertical, offset_y: 0)
    }
  end

  defp point_defaults do
    %{
      x: nil,
      y: nil,
      tooltip: nil,
      marker: %{
        size: 4,
        fill_color: "#fff",
        stroke_color: "#333",
        stroke_width: 2,
        shape: :circle,
        offset_x: 0,
        offset_y: 0
      },
      label: label_defaults(text_anchor: :middle, position: :top, offset_y: 0)
    }
  end

  defp label_defaults(opts) do
    base = %{
      text: nil,
      text_anchor: Keyword.get(opts, :text_anchor, :middle),
      position: Keyword.get(opts, :position, :top),
      offset_x: 0,
      offset_y: Keyword.get(opts, :offset_y, 0),
      border_color: "#c2c2c2",
      border_width: 1,
      border_radius: 2,
      style: %{
        background: "#fff",
        color: nil,
        font_size: 11,
        font_weight: 400,
        padding: %{left: 5, right: 5, top: 2, bottom: 2}
      }
    }

    case Keyword.fetch(opts, :orientation) do
      {:ok, o} -> Map.put(base, :orientation, o)
      :error -> base
    end
  end
end
