defmodule EexCharts.PDF.Ops do
  @moduledoc """
  Walks an `EexCharts.SVG` element tree and emits PrawnEx content operations.

  This is the whole PDF backend. It reads the same tree the SVG serializer
  reads — structured attributes, path data as command tuples — so nothing is
  ever parsed back out of a rendered document.

  ## Coordinates

  SVG's origin is top-left with y growing downwards; PDF's is bottom-left with
  y growing upwards. Every coordinate is flipped individually
  (`y_pdf = y + scale * (chart_height - y_svg)`) rather than by installing a
  mirroring CTM, because a mirroring CTM would also mirror every glyph — and
  un-mirroring the text needs a counter-transform on every single label.

  ## Graphics state

  Colours, line width, dash, caps, joins, font and alpha are tracked as they
  are emitted, and an operation is only written when the value actually
  changes. A chart is thousands of shapes drawn in a handful of colours, so
  this is the difference between ~2k and ~15k operations per page.

  `save_state`/`restore_state` brackets appear in exactly two places — around
  a transformed element and around a group carrying `opacity` — and the
  tracked state is rolled back with them, since `Q` restores the real one.

  ## Known approximations

    * A `fill: "url(#…)"` degrades to the gradient's **first stop** (colour and
      stop-opacity). PDF shadings exist but PrawnEx has no operation for them.
    * PrawnEx's `set_opacity` is a single ExtGState alpha covering both fill
      and stroke, so a shape that is filled *and* stroked at two different
      opacities gets the fill's.
    * Colours that are not `#rgb`/`#rrggbb` fall back to
      `EexCharts.Color.parse/1`'s dark grey. Static rendering resolves
      `var(…)` and `color-mix()` away before we see them, so in practice every
      colour reaching here is hex.
  """

  alias EexCharts.Color
  alias EexCharts.PDF.{Arc, Text}

  # The circle/quarter-arc Bézier constant: 4/3·(√2−1). Rounded corners and
  # `<circle>` are built from four of these.
  @kappa 0.5523

  # SVG presentation attributes that inherit from a group to its children.
  # `transform` and `opacity` are deliberately absent: they are applied and
  # composed, not inherited.
  @inheritable ~w(fill stroke stroke-width stroke-dasharray stroke-linecap
                  stroke-linejoin fill-opacity stroke-opacity font-size
                  font-family font-weight text-anchor dominant-baseline)

  # Nothing here can be drawn: gradients are collected in a pre-pass, and the
  # rest is either metadata or the HTML legend's foreignObject subtree, which
  # a PDF has no way to lay out.
  @skip ~w(defs linearGradient radialGradient stop title desc metadata style
           script foreignObject div span clipPath filter mask marker pattern)

  @initial_gs %{
    fill: :unset,
    stroke: :unset,
    width: :unset,
    dash: :unset,
    cap: :unset,
    join: :unset,
    font: :unset,
    alpha: :unset
  }

  @doc """
  Emits the content operations for `tree`, placing the chart's bottom-left
  corner at `{x, y}` on the page and scaling it by `scale`.
  """
  def build(tree, x, y, scale) do
    {:el, "svg", attrs, children} = find_svg(tree)
    root = attrs_map(attrs)
    {_w, h} = viewport(root)

    geo = %{h: h, ox: x, oy: y, s: scale, gradients: gradients(tree)}
    ctx = %{inh: Map.take(root, @inheritable), alpha: 1.0}

    {ops, _gs} = walk(children, geo, ctx, @initial_gs)
    List.flatten(ops)
  end

  @doc "The chart's `{width, height}` in SVG user units."
  def size(tree) do
    {:el, "svg", attrs, _} = find_svg(tree)
    attrs |> attrs_map() |> viewport()
  end

  defp find_svg({:el, "svg", _, _} = node), do: node
  defp find_svg({:el, _, _, children}), do: find_svg(children)
  defp find_svg(nodes) when is_list(nodes), do: Enum.find_value(nodes, &find_svg/1)
  defp find_svg(_), do: nil

  defp viewport(root) do
    case root["viewBox"] do
      "" <> box ->
        case String.split(box, [" ", ","], trim: true) do
          [_, _, w, h] -> {parse_num(w), parse_num(h)}
          _ -> {num(root["width"], 600), num(root["height"], 350)}
        end

      _ ->
        {num(root["width"], 600), num(root["height"], 350)}
    end
  end

  # ── Tree walk ────────────────────────────────────────────────────────────

  defp walk(nodes, geo, ctx, gs) when is_list(nodes) do
    Enum.reduce(nodes, {[], gs}, fn node, {acc, gs} ->
      {ops, gs} = walk(node, geo, ctx, gs)
      {[acc, ops], gs}
    end)
  end

  defp walk({:el, tag, attrs, children}, geo, ctx, gs) do
    a = attrs_map(attrs)

    cond do
      tag in @skip ->
        {[], gs}

      transform = a["transform"] ->
        # The matrix is expressed in page space, so the children are still
        # laid out with the plain flip and the CTM does the rest. `Q` puts the
        # real graphics state back, so the tracked one goes back with it.
        {inner, _} = element(tag, Map.delete(a, "transform"), children, geo, ctx, gs)
        {[:save_state, matrix(transform, geo), inner, :restore_state], gs}

      true ->
        element(tag, a, children, geo, ctx, gs)
    end
  end

  defp walk(_leaf, _geo, _ctx, gs), do: {[], gs}

  defp element("rect", a, _children, geo, ctx, gs), do: rect(inherit(a, ctx), geo, ctx, gs)
  defp element("circle", a, _children, geo, ctx, gs), do: circle(inherit(a, ctx), geo, ctx, gs)
  defp element("line", a, _children, geo, ctx, gs), do: line(inherit(a, ctx), geo, ctx, gs)
  defp element("path", a, _children, geo, ctx, gs), do: path(inherit(a, ctx), geo, ctx, gs)
  defp element("polygon", a, _c, geo, ctx, gs), do: polygon(inherit(a, ctx), geo, ctx, gs, true)
  defp element("polyline", a, _c, geo, ctx, gs), do: polygon(inherit(a, ctx), geo, ctx, gs, false)

  defp element("text", a, children, geo, ctx, gs),
    do: text(inherit(a, ctx), children, geo, ctx, gs)

  # `g`, the root `svg`, and anything unrecognised: descend, so a wrapper
  # element added later cannot silently swallow a chart.
  defp element(_tag, a, children, geo, ctx, gs) do
    ctx = %{ctx | inh: Map.merge(ctx.inh, Map.take(a, @inheritable))}

    case a["opacity"] do
      nil ->
        walk(children, geo, ctx, gs)

      value ->
        alpha = ctx.alpha * opacity(value)
        {inner, _} = walk(children, geo, %{ctx | alpha: alpha}, %{gs | alpha: alpha})
        {[:save_state, {:set_opacity, alpha}, inner, :restore_state], gs}
    end
  end

  # A shape sees its own attributes over whatever the enclosing groups set.
  defp inherit(a, ctx), do: Map.merge(ctx.inh, a)

  # ── Transforms ───────────────────────────────────────────────────────────

  defp matrix({:translate, tx, ty}, geo) do
    {:concat_matrix, 1, 0, 0, 1, geo.s * tx, -geo.s * ty}
  end

  # SVG measures a positive angle clockwise (its y axis points down); PDF
  # measures it counter-clockwise. Under the flip, `rotate(a, px, py)` is
  # therefore a rotation by −a about the flipped pivot.
  defp matrix({:rotate, deg, px, py}, geo) do
    rad = deg * :math.pi() / 180
    c = snap(:math.cos(rad))
    s = snap(:math.sin(rad))
    {x, y} = pt(px, py, geo)

    {:concat_matrix, c, -s, s, c, x - c * x - s * y, y + s * x - c * y}
  end

  # cos(π/2) is 6.1e-17, not 0. Right-angle rotations are the only ones any
  # chart uses, so snap the noise away and keep the matrices readable.
  defp snap(v) when abs(v) < 1.0e-12, do: 0.0
  defp snap(v), do: v

  # ── Shapes ───────────────────────────────────────────────────────────────

  defp rect(e, geo, ctx, gs) do
    x = num(e["x"], 0)
    y = num(e["y"], 0)
    w = num(e["width"], 0)
    h = num(e["height"], 0)
    r = e["rx"] |> num(e["ry"] |> num(0)) |> min(w / 2) |> min(h / 2)

    path_ops =
      if r > 0 do
        rounded_rect(x, y, w, h, r, geo)
      else
        {px, py} = pt(x, y + h, geo)
        [{:rectangle, px, py, geo.s * w, geo.s * h}]
      end

    draw(path_ops, e, geo, ctx, gs)
  end

  defp rounded_rect(x, y, w, h, r, geo) do
    {l, t} = pt(x, y, geo)
    {rt, b} = pt(x + w, y + h, geo)
    k = geo.s * r
    o = k * @kappa

    [
      {:move_to, {l + k, b}},
      {:line_to, {rt - k, b}},
      {:curve_to, {rt - k + o, b}, {rt, b + k - o}, {rt, b + k}},
      {:line_to, {rt, t - k}},
      {:curve_to, {rt, t - k + o}, {rt - k + o, t}, {rt - k, t}},
      {:line_to, {l + k, t}},
      {:curve_to, {l + k - o, t}, {l, t - k + o}, {l, t - k}},
      {:line_to, {l, b + k}},
      {:curve_to, {l, b + k - o}, {l + k - o, b}, {l + k, b}},
      :close_path
    ]
  end

  defp circle(e, geo, ctx, gs) do
    {cx, cy} = pt(num(e["cx"], 0), num(e["cy"], 0), geo)
    r = geo.s * num(e["r"], 0)
    o = r * @kappa

    path_ops = [
      {:move_to, {cx + r, cy}},
      {:curve_to, {cx + r, cy + o}, {cx + o, cy + r}, {cx, cy + r}},
      {:curve_to, {cx - o, cy + r}, {cx - r, cy + o}, {cx - r, cy}},
      {:curve_to, {cx - r, cy - o}, {cx - o, cy - r}, {cx, cy - r}},
      {:curve_to, {cx + o, cy - r}, {cx + r, cy - o}, {cx + r, cy}},
      :close_path
    ]

    draw(path_ops, e, geo, ctx, gs)
  end

  defp line(e, geo, ctx, gs) do
    p1 = pt(num(e["x1"], 0), num(e["y1"], 0), geo)
    p2 = pt(num(e["x2"], 0), num(e["y2"], 0), geo)

    # A `<line>` has no interior; only its stroke can be drawn.
    draw([{:move_to, p1}, {:line_to, p2}], Map.put(e, "fill", "none"), geo, ctx, gs)
  end

  defp polygon(e, geo, ctx, gs, close?) do
    case points(e["points"]) do
      [] ->
        {[], gs}

      [first | rest] ->
        path_ops =
          [{:move_to, pt_pair(first, geo)}] ++
            Enum.map(rest, fn p -> {:line_to, pt_pair(p, geo)} end) ++
            if close?, do: [:close_path], else: []

        e = if close?, do: e, else: Map.put(e, "fill", "none")
        draw(path_ops, e, geo, ctx, gs)
    end
  end

  defp points({:points, pairs}), do: pairs
  defp points(_), do: []

  defp pt_pair({x, y}, geo), do: pt(x, y, geo)

  defp path(e, geo, ctx, gs) do
    case e["d"] do
      nil -> {[], gs}
      d -> draw(path_data(d, geo), e, geo, ctx, gs)
    end
  end

  # ── Path data ────────────────────────────────────────────────────────────

  @doc false
  def path_data(d, geo) do
    {ops, _cursor, _start} =
      d
      |> List.flatten()
      |> Enum.reduce({[], {0, 0}, {0, 0}}, fn cmd, acc -> command(cmd, acc, geo) end)

    List.flatten(ops)
  end

  defp command({:move, x, y}, {ops, _cur, _start}, geo) do
    {[ops, {:move_to, pt(x, y, geo)}], {x, y}, {x, y}}
  end

  defp command({:rmove, dx, dy}, {ops, {cx, cy}, _start}, geo) do
    p = {cx + dx, cy + dy}
    {[ops, {:move_to, pt_pair(p, geo)}], p, p}
  end

  defp command({:line, x, y}, {ops, _cur, start}, geo) do
    {[ops, {:line_to, pt(x, y, geo)}], {x, y}, start}
  end

  defp command({:hline, x}, {ops, {_cx, cy}, start}, geo) do
    {[ops, {:line_to, pt(x, cy, geo)}], {x, cy}, start}
  end

  defp command({:vline, y}, {ops, {cx, _cy}, start}, geo) do
    {[ops, {:line_to, pt(cx, y, geo)}], {cx, y}, start}
  end

  defp command({:curve, x1, y1, x2, y2, x, y}, {ops, _cur, start}, geo) do
    op = {:curve_to, pt(x1, y1, geo), pt(x2, y2, geo), pt(x, y, geo)}
    {[ops, op], {x, y}, start}
  end

  defp command({:arc, rx, ry, rot, large, sweep, x, y}, {ops, cur, start}, geo) do
    curves =
      cur
      |> Arc.to_curves(rx, ry, rot, large, sweep, {x, y})
      |> Enum.map(fn {c1, c2, p} ->
        {:curve_to, pt_pair(c1, geo), pt_pair(c2, geo), pt_pair(p, geo)}
      end)

    {[ops, curves], {x, y}, start}
  end

  defp command(:close, {ops, _cur, start}, _geo) do
    {[ops, :close_path], start, start}
  end

  # ── Text ─────────────────────────────────────────────────────────────────

  defp text(e, children, geo, ctx, gs) do
    size = num(e["font-size"], 12)

    with {rgb, alpha} <- fill_paint(e, geo, ctx),
         [_ | _] = runs <- runs(children, num(e["x"], 0), num(e["y"], 0), size) do
      font = {Text.font_name(e["font-weight"]), geo.s * size}
      dy = Text.baseline_dy(size, e["dominant-baseline"])
      anchor = e["text-anchor"]

      {ops, gs} =
        {[], gs}
        |> put(:alpha, alpha, &{:set_opacity, &1})
        |> put(:fill, rgb, &non_stroking/1)
        |> put(:font, font, fn {name, s} -> {:set_font, name, s} end)

      placed =
        Enum.map(runs, fn {x, y, string} ->
          {:text_at, pt(x + Text.anchor_dx(string, size, anchor), y + dy, geo), string}
        end)

      {[ops, placed], gs}
    else
      _ -> {[], gs}
    end
  end

  # `<tspan>`s are the multi-line label form: each carries its own `x` and a
  # `dy` that steps down from the line before it. Anything else is a single
  # run at the `<text>`'s own position.
  defp runs(children, x, y, size) do
    case tspans(children) do
      [] ->
        case content(children) do
          "" -> []
          string -> [{x, y, string}]
        end

      spans ->
        spans
        |> Enum.map_reduce(y, fn {a, ch}, cursor ->
          ty = num(a["y"], cursor + Text.resolve_dy(a["dy"], size))
          {{num(a["x"], x), ty, content(ch)}, ty}
        end)
        |> elem(0)
        |> Enum.reject(fn {_, _, string} -> string == "" end)
    end
  end

  defp tspans({:el, "tspan", attrs, children}), do: [{attrs_map(attrs), children}]
  defp tspans(nodes) when is_list(nodes), do: Enum.flat_map(nodes, &tspans/1)
  defp tspans(_), do: []

  defp content(node), do: node |> flatten() |> Text.unescape()

  defp flatten(nil), do: ""
  defp flatten(text) when is_binary(text), do: text
  defp flatten(byte) when is_integer(byte), do: <<byte>>
  defp flatten({:el, _tag, _attrs, children}), do: flatten(children)
  defp flatten(nodes) when is_list(nodes), do: Enum.map_join(nodes, &flatten/1)

  # ── Paint ────────────────────────────────────────────────────────────────

  defp draw(path_ops, e, geo, ctx, gs) do
    fill = fill_paint(e, geo, ctx)
    stroke = stroke_paint(e, geo, ctx)

    case {fill, stroke} do
      {:none, :none} ->
        {[], gs}

      _ ->
        {ops, gs} = paint_state(fill, stroke, e, geo, gs)
        {[ops, path_ops, paint_op(fill, stroke)], gs}
    end
  end

  defp paint_op(:none, _stroke), do: :stroke
  defp paint_op(_fill, :none), do: :fill
  defp paint_op(_fill, _stroke), do: :fill_stroke

  defp paint_state(fill, stroke, e, geo, gs) do
    {[], gs}
    |> put(:alpha, alpha_of(fill, stroke), &{:set_opacity, &1})
    |> maybe_fill(fill)
    |> maybe_stroke(stroke, e, geo)
  end

  # One ExtGState alpha covers fill and stroke alike, so a shape that is both
  # takes the fill's — the larger area, and the one an eye reads as the
  # shape's opacity.
  defp alpha_of(:none, {_rgb, alpha}), do: alpha
  defp alpha_of({_rgb, alpha}, _stroke), do: alpha

  defp maybe_fill(acc, :none), do: acc
  defp maybe_fill(acc, {rgb, _alpha}), do: put(acc, :fill, rgb, &non_stroking/1)

  defp maybe_stroke(acc, :none, _e, _geo), do: acc

  defp maybe_stroke(acc, {rgb, _alpha}, e, geo) do
    acc
    |> put(:stroke, rgb, &stroking/1)
    |> put(:width, geo.s * stroke_width(e), &{:set_line_width, &1})
    |> put(:dash, dash(e["stroke-dasharray"], geo.s), &{:set_dash, &1, 0})
    |> put(:cap, cap(e["stroke-linecap"]), &{:set_line_cap, &1})
    |> put(:join, join(e["stroke-linejoin"]), &{:set_line_join, &1})
  end

  defp non_stroking({r, g, b}), do: {:set_non_stroking_rgb, r, g, b}
  defp stroking({r, g, b}), do: {:set_stroking_rgb, r, g, b}

  # Emits an operation only when it would actually change the state.
  defp put({ops, gs}, key, value, op) do
    if Map.fetch!(gs, key) === value do
      {ops, gs}
    else
      {[ops, op.(value)], Map.put(gs, key, value)}
    end
  end

  defp fill_paint(e, geo, ctx) do
    # SVG's initial fill is black; a shape that names no fill is filled.
    case paint(Map.get(e, "fill", "#000000"), geo) do
      :none -> :none
      {rgb, stop_alpha} -> {rgb, ctx.alpha * opacity(e["fill-opacity"]) * stop_alpha}
    end
  end

  defp stroke_paint(e, geo, ctx) do
    # SVG's initial stroke is none, and a zero width draws nothing.
    if stroke_width(e) <= 0 do
      :none
    else
      case paint(e["stroke"], geo) do
        :none -> :none
        {rgb, stop_alpha} -> {rgb, ctx.alpha * opacity(e["stroke-opacity"]) * stop_alpha}
      end
    end
  end

  defp paint(nil, _geo), do: :none
  defp paint("none", _geo), do: :none
  defp paint("transparent", _geo), do: :none

  defp paint("url(#" <> rest, geo) do
    id = String.trim_trailing(rest, ")")

    case geo.gradients[id] do
      nil -> :none
      {color, stop_alpha} -> {rgb(color), stop_alpha}
    end
  end

  defp paint(color, _geo) when is_binary(color), do: {rgb(color), 1}
  defp paint(color, geo), do: paint(to_string(color), geo)

  defp rgb(color) do
    {r, g, b} = Color.parse(color)
    {r / 255, g / 255, b / 255}
  end

  # Always a float, so that an alpha reached two different ways (a group's
  # `opacity`, a shape's `fill-opacity`) compares equal and does not emit a
  # redundant ExtGState switch — or, worse, a second ExtGState object.
  defp opacity(nil), do: 1.0
  defp opacity(value), do: num(value, 1) * 1.0

  defp stroke_width(e), do: num(e["stroke-width"], 1)

  defp dash(nil, _s), do: []

  defp dash(value, s) do
    value
    |> dash_list()
    |> Enum.map(&(s * &1))
    |> then(fn list -> if Enum.all?(list, &(&1 == 0)), do: [], else: list end)
  end

  defp dash_list(value) when is_number(value), do: [value]
  defp dash_list(value) when is_list(value), do: value

  defp dash_list(value) when is_binary(value) do
    value
    |> String.split([",", " "], trim: true)
    |> Enum.flat_map(fn part ->
      case Float.parse(part) do
        {n, _} -> [n]
        :error -> []
      end
    end)
  end

  defp dash_list(_), do: []

  defp cap(value) do
    case to_string(value || "butt") do
      "round" -> 1
      "square" -> 2
      _ -> 0
    end
  end

  defp join(value) do
    case to_string(value || "miter") do
      "round" -> 1
      "bevel" -> 2
      _ -> 0
    end
  end

  # ── Gradients ────────────────────────────────────────────────────────────

  # One pre-pass, so a `fill: "url(#…)"` resolves whether or not its `<defs>`
  # happens to come first in the tree.
  defp gradients(node), do: gradients(node, %{})

  defp gradients({:el, tag, attrs, children}, acc)
       when tag in ["linearGradient", "radialGradient"] do
    a = attrs_map(attrs)

    case {a["id"], first_stop(children)} do
      {nil, _} -> acc
      {_id, nil} -> acc
      {id, stop} -> Map.put(acc, id, stop)
    end
  end

  defp gradients({:el, _tag, _attrs, children}, acc), do: gradients(children, acc)
  defp gradients(nodes, acc) when is_list(nodes), do: Enum.reduce(nodes, acc, &gradients/2)
  defp gradients(_leaf, acc), do: acc

  defp first_stop({:el, "stop", attrs, _}) do
    a = attrs_map(attrs)

    case a["stop-color"] do
      nil -> nil
      color -> {color, opacity(a["stop-opacity"])}
    end
  end

  defp first_stop(nodes) when is_list(nodes), do: Enum.find_value(nodes, &first_stop/1)
  defp first_stop(_), do: nil

  # ── Attributes ───────────────────────────────────────────────────────────

  defp attrs_map(attrs) do
    Enum.reduce(attrs, %{}, fn {k, v}, acc ->
      if v == nil or v == false, do: acc, else: Map.put(acc, attr_name(k), v)
    end)
  end

  defp attr_name(k) when is_atom(k), do: k |> Atom.to_string() |> String.replace("_", "-")
  defp attr_name(k) when is_binary(k), do: k

  defp pt(x, y, %{ox: ox, oy: oy, s: s, h: h}), do: {ox + s * x, oy + s * (h - y)}

  defp num(nil, default), do: default
  defp num(value, _default) when is_number(value), do: value
  defp num(value, default) when is_binary(value), do: parse_num(value) || default
  defp num(_value, default), do: default

  defp parse_num(value) do
    case Float.parse(value) do
      {n, _rest} -> if n == trunc(n), do: trunc(n), else: n
      :error -> nil
    end
  end
end
