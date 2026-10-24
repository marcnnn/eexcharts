defmodule EexCharts.SvgInvariants do
  @moduledoc """
  Generic, chart-type-agnostic sanity checks for rendered SVG (layer 0 of
  `docs/VALIDATION.md`).

  The goldens in `test/snapshots/` only say "the output did not change"; they
  say nothing about whether it was right when it was seeded. These checks hold
  for every chart we can ever render, so they run against every example in
  `Dev.ChartExamples.all/0`, including the ones added later:

    * `:xml` - the markup is well-formed XML (parsed with OTP's `:xmerl`).
    * `:bad_token` - no attribute value or text contains `NaN`, `Infinity`,
      `nil` or `undefined`.
    * `:numeric` - geometry/paint attributes (`x`, `r`, `width`, `opacity`,
      ...) are plain finite numbers (an optional `px`/`em`/`%` unit allowed),
      never empty; `d`, `points`, `transform` and `viewBox` parse completely.
    * `:negative_size` - no negative `width`, `height`, `r`, `rx` or `ry`.
    * `:bounds` - every drawn element lies inside the viewBox (within
      `@geometry_tolerance`): rect corners, circle/ellipse extents, line ends,
      polygon points, path points with exact Bezier extrema and sampled
      arc points, and the estimated box of
      every text line (within `@text_tolerance`, estimates are rough).
    * `:duplicate_id` - every `id` occurs once in the document.
    * `:dangling_ref` - every `url(#id)` and `href="#id"` resolves.
    * `:contrast` - a text drawn on its own background box (a `<rect>` right
      before it that contains its anchor: data-label and annotation-label
      backgrounds) is readable: WCAG contrast ratio of at least
      `@min_label_contrast` between the two solid fills.
    * `:text_overlap` - text boxes estimated with `EexCharts.FontMetrics` do
      not overlap other texts of the same label group (the text's own class,
      else its nearest classed ancestor: axis labels, data labels, legend...).
      Boxes are oriented rectangles (rotated labels are compared rotated) and
      must interpenetrate by more than `@overlap_tolerance` px.

  Elements that are not drawn (inside `<defs>`, gradients, clip paths; or
  `display="none"`, `visibility="hidden"`, `opacity="0"`, the HTML `hidden`
  attribute) are exempt from the geometric checks but still have to be clean
  numbers.

  `check/2` returns a list of violation maps (`%{check:, element:, detail:}`);
  the caller decides what is allowlisted.
  """

  require Record

  @hrl "xmerl/include/xmerl.hrl"
  Record.defrecordp(:xml_element, :xmlElement, Record.extract(:xmlElement, from_lib: @hrl))
  Record.defrecordp(:xml_attribute, :xmlAttribute, Record.extract(:xmlAttribute, from_lib: @hrl))
  Record.defrecordp(:xml_text, :xmlText, Record.extract(:xmlText, from_lib: @hrl))

  @geometry_tolerance 1.0
  @text_tolerance 2.0
  @overlap_tolerance 1.0
  # WCAG contrast ratio below which a label on its own background box counts
  # as invisible. Deliberately low: white on a light series colour (e.g. the
  # ApexCharts yellow, ~1.8) is the upstream look, white on white (1.0) is not.
  @min_label_contrast 1.5
  # The metric tables are for regular weight; semibold/bold Helvetica runs ~7%
  # wider (measured against Chrome's getBBox on the example catalog).
  @bold_factor 1.07

  @numeric_attrs ~w(x y x1 y1 x2 y2 cx cy r rx ry width height dx dy font-size
                    stroke-width opacity fill-opacity stroke-opacity offset)
  @non_negative ~w(width height r rx ry)
  @not_drawn ~w(defs clipPath mask pattern linearGradient radialGradient symbol marker
                filter title desc metadata style script)

  @number ~r/^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?(?:px|em|%)?$/
  @bad_token ~r/\b(?:NaN|Infinity|nil|undefined)\b/

  # ---------------------------------------------------------------------------
  # Parsing

  @doc """
  Parses markup into `%{name:, attrs:, children:}` maps (text nodes are
  binaries). Returns `{:error, reason}` for anything that is not well-formed.
  """
  def parse(markup) when is_binary(markup) do
    # UTF-8 bytes: xmerl decodes them itself (a codepoint list trips it up).
    chars = :binary.bin_to_list(markup)

    try do
      {doc, rest} = :xmerl_scan.string(chars, quiet: true)

      if String.trim(List.to_string(rest)) == "" do
        {:ok, convert(doc)}
      else
        {:error, "trailing content after the root element"}
      end
    catch
      :exit, reason -> {:error, "not well-formed XML: #{inspect(reason, limit: 8)}"}
    end
  end

  defp convert(xml_element(name: name, attributes: attrs, content: content)) do
    %{
      name: to_string(name),
      attrs: Map.new(attrs, fn xml_attribute(name: k, value: v) -> {to_string(k), to_s(v)} end),
      children: Enum.flat_map(content, &convert_child/1)
    }
  end

  defp convert_child(xml_element() = el), do: [convert(el)]
  defp convert_child(xml_text(value: v)), do: [to_s(v)]
  defp convert_child(_comment_or_pi), do: []

  defp to_s(v) when is_list(v), do: List.to_string(v)
  defp to_s(v), do: to_string(v)

  @doc "The first `<svg>` element in the tree (the root itself, or nested in a wrapper)."
  def find_svg(%{name: "svg"} = node), do: node

  def find_svg(%{children: children}) do
    Enum.find_value(children, fn
      %{} = child -> find_svg(child)
      _text -> nil
    end)
  end

  @doc "Every element of the tree, depth first."
  def all_elements(%{children: children} = node),
    do: [node | Enum.flat_map(children, &all_elements/1)]

  def all_elements(_text), do: []

  @doc "Elements whose `class` contains `class`."
  def with_class(tree, class) do
    tree |> all_elements() |> Enum.filter(&(class in classes(&1)))
  end

  defp classes(%{attrs: attrs}), do: String.split(attrs["class"] || "")

  # ---------------------------------------------------------------------------
  # Entry point

  @doc """
  Runs every check on `markup` (a standalone `<svg>` or a wrapper containing
  one). Options: `:metrics` - the chart's `font_metrics` (default `:arial`).
  """
  def check(markup, opts \\ []) do
    case parse(markup) do
      {:error, reason} ->
        [%{check: :xml, element: "document", detail: reason}]

      {:ok, tree} ->
        case find_svg(tree) do
          nil ->
            [%{check: :xml, element: "document", detail: "no <svg> element"}]

          svg ->
            metrics = Keyword.get(opts, :metrics, :arial)
            items = flatten(svg, metrics)

            numeric_violations(tree) ++
              id_violations(tree) ++
              geometry_violations(svg, items) ++
              overlap_violations(items) ++
              contrast_violations(items)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Numbers, tokens, ids

  defp numeric_violations(tree) do
    tree
    |> all_elements()
    |> Enum.flat_map(fn node ->
      attr_violations =
        Enum.flat_map(node.attrs, fn {k, v} ->
          cond do
            Regex.match?(@bad_token, v) ->
              [violation(:bad_token, node, "#{k}=#{inspect(v)}")]

            k in @numeric_attrs and not Regex.match?(@number, String.trim(v)) ->
              [violation(:numeric, node, "#{k}=#{inspect(v)} is not a number")]

            k in @non_negative and Regex.match?(@number, String.trim(v)) and
                to_f(v) < 0 ->
              [violation(:negative_size, node, "#{k}=#{v}")]

            true ->
              []
          end
        end)

      text_violations =
        for text <- node.children,
            is_binary(text),
            Regex.match?(@bad_token, text),
            do: violation(:bad_token, node, "text #{inspect(text)}")

      parse_violations =
        [
          {"d", &path_points/1},
          {"points", &points/1},
          {"transform", &transform/1},
          {"viewBox", &view_box/1}
        ]
        |> Enum.flat_map(fn {attr, parser} ->
          case node.attrs[attr] do
            nil ->
              []

            v ->
              case parser.(v) do
                {:ok, _} -> []
                {:error, why} -> [violation(:numeric, node, "#{attr}: #{why}")]
              end
          end
        end)

      attr_violations ++ text_violations ++ parse_violations
    end)
  end

  defp id_violations(tree) do
    elements = all_elements(tree)
    ids = elements |> Enum.map(& &1.attrs["id"]) |> Enum.reject(&is_nil/1)

    dupes =
      ids
      |> Enum.frequencies()
      |> Enum.filter(fn {_, n} -> n > 1 end)
      |> Enum.map(fn {id, n} ->
        %{check: :duplicate_id, element: "##{id}", detail: "id used #{n} times"}
      end)

    known = MapSet.new(ids)

    dangling =
      for node <- elements,
          {k, v} <- node.attrs,
          ref <- refs(k, v),
          not MapSet.member?(known, ref),
          do: violation(:dangling_ref, node, "#{k} points at missing ##{ref}")

    dupes ++ dangling
  end

  defp refs(k, v) do
    urls = for [_, id] <- Regex.scan(~r/url\(\s*['"]?#([^)'"\s]+)['"]?\s*\)/, v), do: id

    hrefs =
      if k in ["href", "xlink:href"] and String.starts_with?(v, "#"),
        do: [String.trim_leading(v, "#")],
        else: []

    urls ++ hrefs
  end

  # ---------------------------------------------------------------------------
  # Flattening: every element with its accumulated transform and context

  @doc false
  def flatten(svg, metrics) do
    ctx = %{
      m: identity(),
      font_size: 16.0,
      baseline: nil,
      anchor: "start",
      bold: false,
      hidden: false,
      group: nil,
      metrics: metrics
    }

    walk(svg, ctx)
  end

  defp walk(%{} = node, ctx) do
    own =
      case transform(node.attrs["transform"] || "") do
        {:ok, m} -> m
        _ -> identity()
      end

    attrs = node.attrs
    class = attrs["class"]

    ctx = %{
      ctx
      | m: mul(ctx.m, own),
        font_size: font_size(attrs["font-size"], ctx.font_size),
        bold: bold?(attrs["font-weight"], ctx.bold),
        baseline: attrs["dominant-baseline"] || attrs["alignment-baseline"] || ctx.baseline,
        anchor: attrs["text-anchor"] || ctx.anchor,
        hidden: ctx.hidden or hidden?(node),
        group: if(class, do: class, else: ctx.group)
    }

    item = %{node: node, ctx: ctx}

    children =
      if node.name == "text",
        do: [],
        else: node.children |> Enum.filter(&is_map/1) |> Enum.flat_map(&walk(&1, ctx))

    [item | children]
  end

  defp hidden?(%{name: name, attrs: attrs}) do
    style = String.replace(attrs["style"] || "", " ", "")

    name in @not_drawn or attrs["display"] == "none" or attrs["visibility"] == "hidden" or
      Map.has_key?(attrs, "hidden") or num(attrs["opacity"]) == 0.0 or
      String.contains?(style, "display:none")
  end

  defp bold?(nil, inherited), do: inherited
  defp bold?(w, _inherited), do: w in ["bold", "bolder"] or (num(w) || 400.0) >= 600

  defp font_size(nil, inherited), do: inherited

  defp font_size(v, inherited) do
    v = String.trim(v)

    cond do
      String.ends_with?(v, "em") -> to_f(String.trim_trailing(v, "em")) * inherited
      Regex.match?(@number, v) -> to_f(String.trim_trailing(v, "px"))
      true -> inherited
    end
  end

  # ---------------------------------------------------------------------------
  # Geometry

  defp geometry_violations(svg, items) do
    case view_box(svg.attrs["viewBox"] || "") do
      {:ok, {vx, vy, vw, vh}} ->
        box = {vx, vy, vx + vw, vy + vh}

        Enum.flat_map(items, fn %{node: node, ctx: ctx} = item ->
          if ctx.hidden do
            []
          else
            shape =
              node
              |> local_points()
              |> Enum.map(&apply_m(ctx.m, &1))
              |> outside(box, @geometry_tolerance)
              |> Enum.map(&violation(:bounds, node, &1))

            text =
              if node.name == "text" do
                item
                |> text_boxes()
                |> Enum.flat_map(fn {_label, quad} -> quad end)
                |> outside(box, @text_tolerance)
                |> Enum.map(&violation(:bounds, node, "text box #{&1}"))
              else
                []
              end

            Enum.take(shape, 1) ++ Enum.take(text, 1)
          end
        end)

      _ ->
        [%{check: :numeric, element: "svg", detail: "missing or invalid viewBox"}]
    end
  end

  defp outside([], _box, _tol), do: []

  defp outside(points, {x0, y0, x1, y1}, tol) do
    {min_x, max_x} = points |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {min_y, max_y} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    excess = [
      {"left", x0 - min_x},
      {"top", y0 - min_y},
      {"right", max_x - x1},
      {"bottom", max_y - y1}
    ]

    case Enum.filter(excess, fn {_, d} -> d > tol end) do
      [] ->
        []

      sides ->
        [
          "extends past the viewBox by " <>
            Enum.map_join(sides, ", ", fn {side, d} -> "#{fmt(d)}px #{side}" end) <>
            " (bbox #{fmt(min_x)},#{fmt(min_y)} - #{fmt(max_x)},#{fmt(max_y)})"
        ]
    end
  end

  defp local_points(%{name: name, attrs: a}) do
    n = fn key -> num(a[key]) end

    case name do
      "rect" ->
        {x, y, w, h} = {n.("x") || 0.0, n.("y") || 0.0, n.("width"), n.("height")}
        if w && h, do: [{x, y}, {x + w, y}, {x, y + h}, {x + w, y + h}], else: []

      "circle" ->
        ellipse(n.("cx") || 0.0, n.("cy") || 0.0, n.("r"), n.("r"))

      "ellipse" ->
        ellipse(n.("cx") || 0.0, n.("cy") || 0.0, n.("rx"), n.("ry"))

      "line" ->
        [{n.("x1") || 0.0, n.("y1") || 0.0}, {n.("x2") || 0.0, n.("y2") || 0.0}]

      poly when poly in ["polygon", "polyline"] ->
        ok_or_empty(points(a["points"] || ""))

      "path" ->
        ok_or_empty(path_points(a["d"] || ""))

      "text" ->
        if n.("x") && n.("y"), do: [{n.("x"), n.("y")}], else: []

      _ ->
        []
    end
  end

  defp ellipse(_cx, _cy, nil, _), do: []
  defp ellipse(_cx, _cy, _, nil), do: []

  defp ellipse(cx, cy, rx, ry),
    do: [{cx - rx, cy - ry}, {cx + rx, cy - ry}, {cx - rx, cy + ry}, {cx + rx, cy + ry}]

  defp ok_or_empty({:ok, pts}), do: pts
  defp ok_or_empty(_), do: []

  # ---------------------------------------------------------------------------
  # Text boxes

  @doc false
  # One oriented box (4 transformed corners) per text chunk. A chunk starts at
  # the `<text>` itself and at every `<tspan>` carrying an absolute `x` or `y`
  # (that is what starts a new anchored chunk in SVG); other tspans are styled
  # segments of the current chunk.
  def text_boxes(%{node: node, ctx: ctx}) do
    x = num(node.attrs["x"]) || 0.0
    y = (num(node.attrs["y"]) || 0.0) + length_px(node.attrs["dy"], ctx.font_size)
    start = %{x: x, y: y, segs: []}

    {chunks, last} = collect(node.children, {ctx.font_size, ctx.bold}, start, [])

    [last | chunks]
    |> Enum.reverse()
    |> Enum.map(fn chunk -> {chunk_text(chunk), chunk} end)
    |> Enum.reject(fn {text, _} -> text == "" end)
    |> Enum.map(fn {text, chunk} -> {text, chunk_quad(chunk, ctx)} end)
  end

  defp collect([], _style, cur, done), do: {done, cur}

  defp collect([text | rest], {fs, bold}, cur, done) when is_binary(text) do
    collect(rest, {fs, bold}, %{cur | segs: cur.segs ++ [{text, fs, bold}]}, done)
  end

  defp collect([%{name: "tspan", attrs: a} = tspan | rest], {fs, bold} = style, cur, done) do
    tfs = font_size(a["font-size"], fs)
    tbold = bold?(a["font-weight"], bold)
    dy = length_px(a["dy"], tfs)

    {cur, done} =
      if a["x"] || a["y"] do
        next = %{
          x: num(a["x"]) || cur.x,
          y: (num(a["y"]) || cur.y) + dy,
          segs: []
        }

        {next, if(cur.segs == [], do: done, else: [cur | done])}
      else
        {%{cur | y: cur.y + dy}, done}
      end

    {inner_done, inner_cur} = collect(tspan.children, {tfs, tbold}, cur, [])
    collect(rest, style, inner_cur, inner_done ++ done)
  end

  defp collect([_other | rest], style, cur, done), do: collect(rest, style, cur, done)

  defp chunk_text(%{segs: segs}),
    do: segs |> Enum.map_join(fn {t, _, _} -> t end) |> String.trim()

  defp chunk_quad(%{x: x, y: y, segs: segs}, ctx) do
    width =
      segs
      |> Enum.map(fn {t, fs, bold} ->
        EexCharts.Layout.text_width(t, fs, ctx.metrics) * if(bold, do: @bold_factor, else: 1.0)
      end)
      |> Enum.sum()

    # Leading/trailing whitespace inside the chunk does not render as ink.
    trimmed =
      segs
      |> Enum.map_join(fn {t, _, _} -> t end)
      |> then(fn all -> String.length(all) - String.length(String.trim(all)) end)

    width = max(width - trimmed * 0.28 * ctx.font_size, 0.0)
    fs = segs |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> ctx.font_size end)

    x0 =
      case ctx.anchor do
        "middle" -> x - width / 2
        "end" -> x - width
        _ -> x
      end

    {top, bottom} =
      case ctx.baseline do
        b when b in ["central", "middle"] -> {y - 0.5 * fs, y + 0.5 * fs}
        b when b in ["hanging", "text-before-edge"] -> {y, y + fs}
        b when b in ["text-after-edge", "ideographic"] -> {y - fs, y}
        _alphabetic -> {y - 0.75 * fs, y + 0.25 * fs}
      end

    Enum.map([{x0, top}, {x0 + width, top}, {x0 + width, bottom}, {x0, bottom}], fn p ->
      apply_m(ctx.m, p)
    end)
  end

  defp length_px(nil, _fs), do: 0.0

  defp length_px(v, fs) do
    v = String.trim(v)

    if String.ends_with?(v, "em"),
      do: to_f(String.trim_trailing(v, "em")) * fs,
      else: num(String.trim_trailing(v, "px")) || 0.0
  end

  # ---------------------------------------------------------------------------
  # Text overlap

  # ---------------------------------------------------------------------------
  # Label contrast

  defp contrast_violations(items) do
    items
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.flat_map(fn
      [%{node: %{name: "rect"} = rect, ctx: rc}, %{node: %{name: "text"} = text, ctx: tc}]
      when not tc.hidden ->
        with fg when fg != nil <- color(text.attrs["fill"]),
             bg when bg != nil <- color(rect.attrs["fill"]),
             true <- (num(rect.attrs["fill-opacity"]) || 1.0) >= 0.5,
             [anchor] <- local_points(text),
             {ax, ay} = apply_m(tc.m, anchor),
             [_ | _] = corners <- rect |> local_points() |> Enum.map(&apply_m(rc.m, &1)),
             {x0, x1} = corners |> Enum.map(&elem(&1, 0)) |> Enum.min_max(),
             {y0, y1} = corners |> Enum.map(&elem(&1, 1)) |> Enum.min_max(),
             true <- ax >= x0 - 1 and ax <= x1 + 1 and ay >= y0 - 1 and ay <= y1 + 1,
             ratio when ratio < @min_label_contrast <- contrast(fg, bg) do
          [
            violation(
              :contrast,
              text,
              "fill #{text.attrs["fill"]} on #{rect.attrs["fill"]} box, contrast #{fmt(ratio)}:1"
            )
          ]
        else
          _ -> []
        end

      _ ->
        []
    end)
  end

  defp color(nil), do: nil
  defp color("white"), do: {255, 255, 255}
  defp color("black"), do: {0, 0, 0}

  defp color("#" <> hex) when byte_size(hex) == 3 do
    hex |> String.graphemes() |> Enum.map_join(&(&1 <> &1)) |> then(&color("#" <> &1))
  end

  defp color("#" <> hex) when byte_size(hex) == 6 do
    case Base.decode16(hex, case: :mixed) do
      {:ok, <<r, g, b>>} -> {r, g, b}
      :error -> nil
    end
  end

  defp color(_other), do: nil

  defp contrast(a, b) do
    {la, lb} = {luminance(a), luminance(b)}
    (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  end

  defp luminance({r, g, b}) do
    [r, g, b]
    |> Enum.map(fn c ->
      c = c / 255
      if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
    end)
    |> then(fn [r, g, b] -> 0.2126 * r + 0.7152 * g + 0.0722 * b end)
  end

  defp overlap_violations(items) do
    items
    |> Enum.filter(&(&1.node.name == "text" and not &1.ctx.hidden))
    |> Enum.group_by(& &1.ctx.group)
    |> Enum.flat_map(fn {group, texts} ->
      boxes =
        texts
        |> Enum.with_index()
        |> Enum.flat_map(fn {item, i} ->
          item |> text_boxes() |> Enum.map(fn {label, quad} -> {i, label, quad} end)
        end)

      for {{i, a, qa}, k} <- Enum.with_index(boxes),
          {j, b, qb} <- Enum.drop(boxes, k + 1),
          i != j,
          depth = penetration(qa, qb),
          depth > @overlap_tolerance do
        %{
          check: :text_overlap,
          element: "text.#{group}",
          detail: "#{inspect(a)} overlaps #{inspect(b)} by #{fmt(depth)}px"
        }
      end
    end)
  end

  # Separating-axis test for two convex quads: the smallest overlap of their
  # projections over all edge normals (0 when separated).
  defp penetration(qa, qb) do
    (axes(qa) ++ axes(qb))
    |> Enum.map(fn axis ->
      {a0, a1} = project(qa, axis)
      {b0, b1} = project(qb, axis)
      min(a1, b1) - max(a0, b0)
    end)
    |> Enum.min()
    |> max(0.0)
  end

  defp axes(quad) do
    quad
    |> Enum.zip(tl(quad) ++ [hd(quad)])
    |> Enum.take(2)
    |> Enum.flat_map(fn {{x1, y1}, {x2, y2}} ->
      {dx, dy} = {x2 - x1, y2 - y1}
      len = :math.sqrt(dx * dx + dy * dy)
      if len == 0, do: [], else: [{-dy / len, dx / len}]
    end)
    |> case do
      [] -> [{1.0, 0.0}, {0.0, 1.0}]
      axes -> axes
    end
  end

  defp project(quad, {ax, ay}),
    do: quad |> Enum.map(fn {x, y} -> x * ax + y * ay end) |> Enum.min_max()

  # ---------------------------------------------------------------------------
  # Attribute parsers

  @doc "Parses a `viewBox`."
  def view_box(v) do
    case numbers(v) do
      {:ok, [x, y, w, h]} when w >= 0 and h >= 0 -> {:ok, {x, y, w, h}}
      {:ok, _} -> {:error, "viewBox needs four numbers with non-negative size"}
      error -> error
    end
  end

  @doc "Parses a `points` list."
  def points(v) do
    case numbers(v) do
      {:ok, nums} when rem(length(nums), 2) == 0 ->
        {:ok, nums |> Enum.chunk_every(2) |> Enum.map(fn [x, y] -> {x, y} end)}

      {:ok, _} ->
        {:error, "odd number of coordinates"}

      error ->
        error
    end
  end

  @num_re ~r/[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/

  defp numbers(v) do
    leftover = v |> String.replace(@num_re, " ") |> String.replace(~r/[\s,]/, "")

    if leftover == "",
      do: {:ok, @num_re |> Regex.scan(v) |> Enum.map(fn [n] -> to_f(n) end)},
      else: {:error, "unparsable #{inspect(leftover)} in #{inspect(v)}"}
  end

  @doc "Parses a `transform` list into an affine matrix `{a, b, c, d, e, f}`."
  def transform(v) do
    v = String.trim(v)
    calls = Regex.scan(~r/([a-zA-Z]+)\s*\(([^)]*)\)/, v)

    leftover =
      v |> String.replace(~r/([a-zA-Z]+)\s*\(([^)]*)\)/, "") |> String.replace(~r/[\s,]/, "")

    if leftover != "" do
      {:error, "unparsable transform #{inspect(v)}"}
    else
      Enum.reduce_while(calls, {:ok, identity()}, fn [_, fun, args], {:ok, m} ->
        with {:ok, nums} <- numbers(args),
             {:ok, t} <- transform_fun(fun, nums) do
          {:cont, {:ok, mul(m, t)}}
        else
          _ -> {:halt, {:error, "bad #{fun}(#{args})"}}
        end
      end)
    end
  end

  defp transform_fun("translate", [tx]), do: {:ok, {1.0, 0.0, 0.0, 1.0, tx, 0.0}}
  defp transform_fun("translate", [tx, ty]), do: {:ok, {1.0, 0.0, 0.0, 1.0, tx, ty}}
  defp transform_fun("scale", [s]), do: {:ok, {s, 0.0, 0.0, s, 0.0, 0.0}}
  defp transform_fun("scale", [sx, sy]), do: {:ok, {sx, 0.0, 0.0, sy, 0.0, 0.0}}
  defp transform_fun("matrix", [a, b, c, d, e, f]), do: {:ok, {a, b, c, d, e, f}}

  defp transform_fun("rotate", [deg]) do
    r = deg * :math.pi() / 180
    {:ok, {:math.cos(r), :math.sin(r), -:math.sin(r), :math.cos(r), 0.0, 0.0}}
  end

  defp transform_fun("rotate", [deg, cx, cy]) do
    {:ok, rot} = transform_fun("rotate", [deg])
    {:ok, mul(mul({1.0, 0.0, 0.0, 1.0, cx, cy}, rot), {1.0, 0.0, 0.0, 1.0, -cx, -cy})}
  end

  defp transform_fun("skewX", [deg]),
    do: {:ok, {1.0, 0.0, :math.tan(deg * :math.pi() / 180), 1.0, 0.0, 0.0}}

  defp transform_fun("skewY", [deg]),
    do: {:ok, {1.0, :math.tan(deg * :math.pi() / 180), 0.0, 1.0, 0.0, 0.0}}

  defp transform_fun(_, _), do: :error

  defp identity, do: {1.0, 0.0, 0.0, 1.0, 0.0, 0.0}

  defp mul({a1, b1, c1, d1, e1, f1}, {a2, b2, c2, d2, e2, f2}) do
    {a1 * a2 + c1 * b2, b1 * a2 + d1 * b2, a1 * c2 + c1 * d2, b1 * c2 + d1 * d2,
     a1 * e2 + c1 * f2 + e1, b1 * e2 + d1 * f2 + f1}
  end

  defp apply_m({a, b, c, d, e, f}, {x, y}), do: {a * x + c * y + e, b * x + d * y + f}

  # ---------------------------------------------------------------------------
  # Path data

  @path_token ~r/[MmLlHhVvCcSsQqTtAaZz]|[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?/
  @arity %{
    "M" => 2,
    "L" => 2,
    "T" => 2,
    "H" => 1,
    "V" => 1,
    "C" => 6,
    "S" => 4,
    "Q" => 4,
    "A" => 7
  }

  @doc """
  The points that bound a path: on-curve end points,
  the axis extrema of every Bezier segment (its exact bounding box) and
  arc points sampled every 1/48 of the sweep. Supports M L H V C S Q T A Z,
  absolute and relative. Arc flags must be separated by whitespace or commas.
  """
  def path_points(d) do
    leftover = d |> String.replace(@path_token, " ") |> String.replace(~r/[\s,]/, "")

    if leftover != "" do
      {:error, "unparsable #{inspect(leftover)} in path"}
    else
      tokens =
        @path_token
        |> Regex.scan(d)
        |> Enum.map(fn [t] -> if t =~ ~r/^[A-Za-z]$/, do: t, else: to_f(t) end)

      state = %{cur: {0.0, 0.0}, start: {0.0, 0.0}, ctrl: nil, cmd: nil, acc: []}
      run(tokens, state)
    end
  end

  defp run([], s), do: {:ok, Enum.reverse(s.acc)}

  defp run([c | rest], s) when c in ["Z", "z"],
    do: run(rest, %{s | cur: s.start, ctrl: nil, cmd: nil})

  defp run([c | rest], s) when is_binary(c), do: step(c, rest, s)

  defp run([_n | _] = tokens, %{cmd: nil}),
    do: {:error, "number #{inspect(hd(tokens))} without a command"}

  defp run(tokens, s), do: step(s.cmd, tokens, s)

  defp step(cmd, tokens, s) do
    n = @arity[String.upcase(cmd)]
    {args, rest} = Enum.split(tokens, n)

    if length(args) == n and Enum.all?(args, &is_float/1) do
      rel? = cmd == String.downcase(cmd)
      {pts, s} = segment(String.upcase(cmd), rel?, args, s)
      # After a moveto, extra coordinate pairs are implicit linetos.
      next = %{"M" => "L", "m" => "l"}[cmd] || cmd
      run(rest, %{s | acc: Enum.reverse(pts) ++ s.acc, cmd: next})
    else
      {:error, "#{cmd} needs #{n} numbers, got #{inspect(Enum.take(tokens, n))}"}
    end
  end

  defp segment(cmd, rel?, args, %{cur: {cx, cy}} = s) do
    abs = fn {x, y} -> if rel?, do: {cx + x, cy + y}, else: {x, y} end

    case {cmd, args} do
      {"M", [x, y]} ->
        p = abs.({x, y})
        {[p], %{s | cur: p, start: p, ctrl: nil}}

      {"L", [x, y]} ->
        p = abs.({x, y})
        {[p], %{s | cur: p, ctrl: nil}}

      {"H", [x]} ->
        p = {if(rel?, do: cx + x, else: x), cy}
        {[p], %{s | cur: p, ctrl: nil}}

      {"V", [y]} ->
        p = {cx, if(rel?, do: cy + y, else: y)}
        {[p], %{s | cur: p, ctrl: nil}}

      {"C", [x1, y1, x2, y2, x, y]} ->
        [c1, c2, p] = Enum.map([{x1, y1}, {x2, y2}, {x, y}], abs)
        {cubic_extrema(s.cur, c1, c2, p), %{s | cur: p, ctrl: {:cubic, c2}}}

      {"S", [x2, y2, x, y]} ->
        c1 = reflect(s.ctrl, :cubic, s.cur)
        [c2, p] = Enum.map([{x2, y2}, {x, y}], abs)
        {cubic_extrema(s.cur, c1, c2, p), %{s | cur: p, ctrl: {:cubic, c2}}}

      {"Q", [x1, y1, x, y]} ->
        [c, p] = Enum.map([{x1, y1}, {x, y}], abs)
        {quad_extrema(s.cur, c, p), %{s | cur: p, ctrl: {:quad, c}}}

      {"T", [x, y]} ->
        c = reflect(s.ctrl, :quad, s.cur)
        p = abs.({x, y})
        {quad_extrema(s.cur, c, p), %{s | cur: p, ctrl: {:quad, c}}}

      {"A", [rx, ry, phi, large, sweep, x, y]} ->
        p = abs.({x, y})
        {arc_points(s.cur, p, rx, ry, phi, large != 0.0, sweep != 0.0), %{s | cur: p, ctrl: nil}}
    end
  end

  # The end point plus the curve's axis extrema: the exact bounding box (the
  # control points themselves would over-report smooth curves near an edge).
  defp cubic_extrema({x0, y0} = p0, {x1, y1} = c1, {x2, y2} = c2, {x3, y3} = p3) do
    ts = cubic_roots(x0, x1, x2, x3) ++ cubic_roots(y0, y1, y2, y3)

    Enum.map(ts, fn t -> cubic_at(p0, c1, c2, p3, t) end) ++ [p3]
  end

  defp cubic_at({x0, y0}, {x1, y1}, {x2, y2}, {x3, y3}, t) do
    u = 1 - t
    f = fn a, b, c, d -> u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d end
    {f.(x0, x1, x2, x3), f.(y0, y1, y2, y3)}
  end

  # Roots in (0, 1) of the derivative of a cubic Bezier coordinate.
  defp cubic_roots(p0, p1, p2, p3) do
    a = 3 * (-p0 + 3 * p1 - 3 * p2 + p3)
    b = 6 * (p0 - 2 * p1 + p2)
    c = 3 * (p1 - p0)

    roots =
      cond do
        abs(a) < 1.0e-12 and abs(b) < 1.0e-12 ->
          []

        abs(a) < 1.0e-12 ->
          [-c / b]

        b * b - 4 * a * c < 0 ->
          []

        true ->
          disc = :math.sqrt(b * b - 4 * a * c)
          [(-b + disc) / (2 * a), (-b - disc) / (2 * a)]
      end

    Enum.filter(roots, &(&1 > 0 and &1 < 1))
  end

  defp quad_extrema({x0, y0}, {x1, y1}, {x2, y2} = p2) do
    t_of = fn a, b, c -> if a - 2 * b + c == 0, do: nil, else: (a - b) / (a - 2 * b + c) end

    [t_of.(x0, x1, x2), t_of.(y0, y1, y2)]
    |> Enum.filter(&(&1 && &1 > 0 && &1 < 1))
    |> Enum.map(fn t ->
      u = 1 - t
      {u * u * x0 + 2 * u * t * x1 + t * t * x2, u * u * y0 + 2 * u * t * y1 + t * t * y2}
    end)
    |> Kernel.++([p2])
  end

  defp reflect({kind, {px, py}}, kind, {cx, cy}), do: {2 * cx - px, 2 * cy - py}
  defp reflect(_other, _kind, cur), do: cur

  # Endpoint-to-centre conversion from the SVG spec (implementation notes,
  # "Conversion from endpoint to center parameterization"), then sampling.
  defp arc_points({x1, y1}, {x2, y2} = p2, rx, ry, phi_deg, large?, sweep?) do
    rx = abs(rx)
    ry = abs(ry)

    if rx == 0 or ry == 0 or (x1 == x2 and y1 == y2) do
      [p2]
    else
      phi = phi_deg * :math.pi() / 180
      {cos, sin} = {:math.cos(phi), :math.sin(phi)}
      {dx2, dy2} = {(x1 - x2) / 2, (y1 - y2) / 2}
      x1p = cos * dx2 + sin * dy2
      y1p = -sin * dx2 + cos * dy2

      lambda = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry)

      {rx, ry} =
        if lambda > 1, do: {rx * :math.sqrt(lambda), ry * :math.sqrt(lambda)}, else: {rx, ry}

      num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
      den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
      sign = if large? == sweep?, do: -1, else: 1
      coef = sign * :math.sqrt(max(0.0, num / den))
      cxp = coef * rx * y1p / ry
      cyp = -coef * ry * x1p / rx
      cx = cos * cxp - sin * cyp + (x1 + x2) / 2
      cy = sin * cxp + cos * cyp + (y1 + y2) / 2

      theta1 = angle({1.0, 0.0}, {(x1p - cxp) / rx, (y1p - cyp) / ry})
      dtheta = angle({(x1p - cxp) / rx, (y1p - cyp) / ry}, {(-x1p - cxp) / rx, (-y1p - cyp) / ry})

      dtheta =
        cond do
          not sweep? and dtheta > 0 -> dtheta - 2 * :math.pi()
          sweep? and dtheta < 0 -> dtheta + 2 * :math.pi()
          true -> dtheta
        end

      for k <- 1..48 do
        t = theta1 + dtheta * k / 48

        {cx + rx * :math.cos(t) * cos - ry * :math.sin(t) * sin,
         cy + rx * :math.cos(t) * sin + ry * :math.sin(t) * cos}
      end
    end
  end

  defp angle({ux, uy}, {vx, vy}), do: :math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)

  # ---------------------------------------------------------------------------
  # Helpers

  defp num(nil), do: nil

  defp num(v) do
    v = String.trim(v)
    if Regex.match?(~r/^[+-]?(?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?$/, v), do: to_f(v), else: nil
  end

  defp to_f(s) do
    s =
      s
      |> String.trim()
      |> String.replace(~r/(px|em|%)$/, "")
      |> String.replace(~r/^([+-]?)\./, "\\g{1}0.")
      |> String.replace(~r/\.([eE]|$)/, ".0\\g{1}")
      |> String.replace(~r/^([+-]?\d+)([eE])/, "\\g{1}.0\\g{2}")

    {f, ""} = Float.parse(s)
    f
  end

  defp fmt(f), do: :erlang.float_to_binary(f * 1.0, decimals: 1)

  defp violation(check, node, detail),
    do: %{check: check, element: describe(node), detail: detail}

  defp describe(%{name: name, attrs: attrs}) do
    class = attrs["class"]
    tag = if class, do: "#{name}.#{class |> String.split() |> Enum.join(".")}", else: name

    keys =
      ~w(id data-series data-j x y cx cy x1 y1)
      |> Enum.filter(&attrs[&1])
      |> Enum.map_join(" ", &"#{&1}=#{attrs[&1]}")

    if keys == "", do: tag, else: "#{tag}[#{keys}]"
  end
end
