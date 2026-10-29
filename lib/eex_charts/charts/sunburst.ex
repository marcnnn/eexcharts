defmodule EexCharts.Charts.Sunburst do
  @moduledoc """
  Sunburst chart: hierarchical data as concentric rings, one ring per depth.

  This is an eexcharts design (a partition layout in polar coordinates), not
  a port: ApexCharts v4.7.0 has no sunburst.

  ## Data

  Same point shape as the treemap, with nested `children`
  (see `EexCharts.Hierarchy`):

      series: [
        %{name: "Sales", data: [
          %{x: "Europe", children: [%{x: "France", y: 68}, %{x: "Spain", y: 48}]},
          %{x: "Asia", y: 120}
        ]}
      ]

  With a single series, its data points are the top-level branches (the
  innermost ring). With several series, each series becomes a top-level
  branch named after the series, with its data as children. Leaves carry the
  values (negative values count as 0); a parent is worth the sum of its
  children, and a `y` on a parent is ignored.

  ## Layout

  Each node's angular extent is its share of its parent's extent, so the
  arcs of one ring exactly tile the arc of their parent. The chart fits a
  `min(width, height)` square like the pie (outer radius
  `size / 2.05 - stroke.width`); rings are equally thick between the hole
  (`hole_size`, a percentage of the outer radius) and the outer radius.

  ## Colours

  Top-level branch `i` takes palette colour `i`. Descendants are lighter
  shades of their branch colour: deeper rings are lighter, and siblings step
  through the shade band of their ring so neighbours stay distinguishable.
  `shade_intensity` is the lightening of the outermost ring.

  ## Labels

  A label is drawn when it fits inside its arc, otherwise it is hidden.
  `labels.orientation` is `:tangential` (along the ring), `:radial` (along
  the spoke) or `:auto` (tangential, falling back to radial). Text is flipped
  so it never reads upside down. With `data_labels.style.colors: nil` the
  text colour is picked per arc for contrast (white or dark grey).

  ## Options (`plot_options.sunburst`)

    * `start_angle` / `end_angle` (`0` / `360`): angular span, 0 = 12 o'clock.
    * `offset_x` / `offset_y` (`0`).
    * `hole_size` (`"25%"`): radius of the empty centre.
    * `shade_intensity` (`0.5`).
    * `labels.orientation` (`:auto`), `labels.padding` (`4` px).
    * `total.show` (`true`), `total.label` (`"Total"`), `total.formatter`:
      the total shown in the hole (when the hole is big enough).

  The legend lists the top-level branches; legend toggling (`hidden_series`)
  removes a branch. Tooltips show the node path, value and share of parent.
  `on_click` sends `phx-click` with `path` (sibling indexes joined by `-`),
  `name`, `depth`, `index` (position among siblings) and `series` (the
  top-level branch index).
  """

  import EexCharts.SVG

  alias EexCharts.{Color, Config, Hierarchy, Layout, Legend, Renderer}

  @full_turn_eps 1.0e-9

  @doc "Renders the complete sunburst container."
  def render_chart(cfg, params, id) do
    roots = roots(params)
    hidden = Renderer.hidden_set(params)
    names = Enum.map(roots, & &1.label)

    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    legend = Legend.measure(cfg, names, w, h)

    {box_w, box_h} =
      case legend.position do
        :right -> {w - legend.w, h - title_h}
        pos when pos in [:bottom, :top] -> {w, h - title_h - legend.h}
        _ -> {w, h - title_h}
      end

    top = if legend.position == :top, do: title_h + legend.h, else: title_h
    visible = Enum.reject(roots, &MapSet.member?(hidden, &1.index))
    geo = geometry(cfg, visible, box_w, box_h)
    geo = %{geo | cy: geo.cy + top}

    l = %Layout{
      w: w,
      h: h,
      grid_x: 0,
      grid_y: title_h,
      grid_w: box_w,
      grid_h: box_h,
      legend: legend,
      title_h: title_h
    }

    svg =
      Renderer.svg_open(cfg, l, id, [
        Renderer.background(cfg, l),
        Renderer.title(cfg, l),
        arcs(cfg, geo, params[:on_click]),
        labels(cfg, geo),
        total(cfg, geo),
        Legend.render(legend, cfg, l, hidden: hidden, on_click: params[:on_legend_click])
      ])

    Renderer.container(cfg, params, id, svg, tooltips(cfg, geo))
  end

  # ── Data ────────────────────────────────────────────────────────────────

  @doc """
  Top-level nodes from the chart params (see the moduledoc for how series map
  to branches).
  """
  def roots(params) do
    leaf = fn v -> max(v, 0) end
    labels = params[:labels] || []

    case params[:series] do
      [%{} = s] ->
        Hierarchy.nodes(s[:data] || [], leaf, labels)

      [n | _] = list when is_number(n) ->
        Hierarchy.nodes(list, leaf, labels)

      [_ | _] = series ->
        series
        |> Enum.with_index()
        |> Enum.map(fn {s, i} ->
          data = if is_map(s), do: s[:data] || [], else: s
          name = if is_map(s), do: s[:name], else: nil
          children = Hierarchy.nodes(data, leaf, [])

          %{
            label: to_string(name || "series-#{i + 1}"),
            value: children |> Enum.map(& &1.value) |> Enum.sum(),
            children: children,
            index: i
          }
        end)

      _ ->
        []
    end
  end

  # ── Geometry ────────────────────────────────────────────────────────────

  @doc """
  Lays out `roots` in a `box_w` x `box_h` box. Returns
  `%{cx, cy, r, hole_r, ring_w, depth, total, arcs}`; each arc is
  `%{key, path, labels, depth, index, branch, label, value, parent_value,
  start, angle, r_in, r_out, color}` (angles in degrees, 0 = 12 o'clock,
  clockwise).
  """
  def geometry(cfg, roots, box_w, box_h) do
    sb = cfg.plot_options.sunburst
    size = min(box_w, box_h)
    r = max(size / 2.05 - cfg.stroke.width, 0)
    hole_r = r * pct(sb.hole_size) / 100
    depth = Hierarchy.depth(roots)
    ring_w = if depth > 0, do: (r - hole_r) / depth, else: 0
    total = roots |> Enum.map(& &1.value) |> Enum.sum()
    full = abs(sb.end_angle - sb.start_angle)

    ctx = %{cfg: cfg, hole_r: hole_r, ring_w: ring_w, depth: depth, si: sb.shade_intensity}

    arcs =
      roots
      |> place(sb.start_angle, full, total, 0, [], [], nil, ctx)
      |> List.flatten()

    %{
      cx: box_w / 2 + sb.offset_x,
      cy: box_h / 2 + sb.offset_y,
      r: r,
      hole_r: hole_r,
      ring_w: ring_w,
      depth: depth,
      total: total,
      arcs: arcs
    }
  end

  # Partition layout: siblings share their parent's angle in proportion to
  # their values, laid out clockwise from the parent's start.
  defp place(nodes, start, angle, parent_value, d, path, labels, branch, ctx) do
    n = length(nodes)

    {arcs, _} =
      Enum.map_reduce(nodes, start, fn node, a0 ->
        a = if parent_value > 0, do: angle * node.value / parent_value, else: 0
        branch = branch || node.index
        node_path = path ++ [node.index]
        node_labels = labels ++ [node.label]
        r_in = ctx.hole_r + d * ctx.ring_w

        arc = %{
          key: Enum.join(node_path, "-"),
          path: node_path,
          labels: node_labels,
          depth: d,
          index: node.index,
          branch: branch,
          label: node.label,
          value: node.value,
          parent_value: parent_value,
          start: a0,
          angle: a,
          r_in: r_in,
          r_out: r_in + ctx.ring_w,
          color: color(ctx, branch, d, node.index, n)
        }

        children =
          place(node.children, a0, a, node.value, d + 1, node_path, node_labels, branch, ctx)

        {[arc | children], a0 + a}
      end)

    arcs
  end

  # Depth 0 is the palette colour; ring d (of `depth - 1` child rings) spans
  # the shade band [(d-1)/(D-1), d/(D-1)] * shade_intensity, siblings stepping
  # through it.
  defp color(ctx, branch, 0, _j, _n), do: Config.color_at(ctx.cfg, branch)

  defp color(ctx, branch, d, j, n) do
    rings = max(ctx.depth - 1, 1)
    p = ctx.si * (d - 1 + (j + 1) / (n + 1)) / rings
    Color.shade(Config.color_at(ctx.cfg, branch), p)
  end

  # ── Arcs ────────────────────────────────────────────────────────────────

  defp arcs(cfg, geo, on_click) do
    stroke = first_color(cfg.stroke.colors, "#fff")

    paths =
      geo.arcs
      |> Enum.filter(&(&1.angle > 0))
      |> Enum.map(fn a ->
        attrs = %{
          class: "eexcharts-sunburst-arc",
          data_j: a.key,
          d: arc_path(geo.cx, geo.cy, a),
          fill: a.color,
          fill_opacity: cfg.fill.opacity,
          stroke: stroke,
          stroke_width: cfg.stroke.width,
          stroke_linejoin: "round"
        }

        attrs =
          if on_click do
            Map.merge(attrs, %{
              "phx-click" => on_click,
              "phx-value-path" => a.key,
              "phx-value-name" => a.label,
              "phx-value-depth" => a.depth,
              "phx-value-index" => a.index,
              "phx-value-series" => a.branch,
              cursor: "pointer"
            })
          else
            attrs
          end

        el("path", attrs)
      end)

    el("g", %{class: "eexcharts-sunburst"}, paths)
  end

  @doc false
  # Annular sector (or a wedge when the inner radius is 0). A full turn is
  # drawn as two half-circles per edge, since one SVG arc cannot close.
  def arc_path(cx, cy, %{angle: angle} = a) when angle >= 360 - @full_turn_eps do
    ring =
      fn r, sweep ->
        {x0, y0} = polar(cx, cy, r, a.start)
        {x1, y1} = polar(cx, cy, r, a.start + 180)
        [move(x0, y0), arc(r, r, 0, 1, sweep, x1, y1), arc(r, r, 0, 1, sweep, x0, y0), close()]
      end

    if a.r_in > 0, do: [ring.(a.r_out, 1), ring.(a.r_in, 0)], else: ring.(a.r_out, 1)
  end

  def arc_path(cx, cy, a) do
    a1 = a.start + a.angle
    large = if a.angle > 180, do: 1, else: 0
    {ox0, oy0} = polar(cx, cy, a.r_out, a.start)
    {ox1, oy1} = polar(cx, cy, a.r_out, a1)
    outer = [move(ox0, oy0), arc(a.r_out, a.r_out, 0, large, 1, ox1, oy1)]

    if a.r_in > 0 do
      {ix1, iy1} = polar(cx, cy, a.r_in, a1)
      {ix0, iy0} = polar(cx, cy, a.r_in, a.start)
      [outer, line(ix1, iy1), arc(a.r_in, a.r_in, 0, large, 0, ix0, iy0), close()]
    else
      [outer, line(cx, cy), close()]
    end
  end

  # ── Labels ──────────────────────────────────────────────────────────────

  defp labels(cfg, geo) do
    dl = cfg.data_labels

    if dl.enabled do
      texts =
        geo.arcs
        |> Enum.filter(&(&1.angle > 0))
        |> Enum.flat_map(&arc_label(cfg, geo, &1))

      el("g", %{class: "eexcharts-sunburst-labels"}, texts)
    else
      []
    end
  end

  defp arc_label(cfg, geo, a) do
    dl = cfg.data_labels
    font = dl.style.font_size
    text = label_text(cfg, a)
    tw = Layout.text_width(text, font, Layout.metrics(cfg, dl.style))

    case label_orientation(cfg.plot_options.sunburst.labels, a, tw, font) do
      nil ->
        []

      orientation ->
        # A full ring labels at 12 o'clock rather than the bottom.
        mid = if a.angle >= 360 - @full_turn_eps, do: a.start, else: a.start + a.angle / 2

        rm =
          if a.r_in == 0 and a.angle >= 360 - @full_turn_eps, do: 0, else: (a.r_in + a.r_out) / 2

        {x, y} = polar(geo.cx, geo.cy, rm, mid)

        [
          el(
            "text",
            %{
              x: x + dl.offset_x,
              y: y + dl.offset_y,
              transform: rotate(rotation(orientation, mid, a), x, y),
              text_anchor: "middle",
              dominant_baseline: "central",
              fill: label_color(dl, a.color),
              font_size: font,
              font_weight: dl.style.font_weight,
              class: "eexcharts-datalabel"
            },
            esc(text)
          )
        ]
    end
  end

  @doc false
  # Which orientation (if any) fits a `tw` x `font` label inside arc `a`.
  def label_orientation(opts, a, tw, font) do
    candidates =
      case opts.orientation do
        :radial -> [:radial]
        :tangential -> [:tangential]
        _ -> [:tangential, :radial]
      end

    Enum.find(candidates, &fits?(&1, a, tw, font, opts.padding))
  end

  defp fits?(_orientation, %{angle: angle, r_in: 0} = a, tw, font, pad)
       when angle >= 360 - @full_turn_eps do
    # A full disc in the centre: the label sits horizontally on the centre.
    tw + 2 * pad <= 2 * a.r_out and font + 2 * pad <= 2 * a.r_out
  end

  defp fits?(:tangential, a, tw, font, pad) do
    thick = a.r_out - a.r_in
    rm = (a.r_in + a.r_out) / 2
    inner = rm - font / 2

    # The straight text's inner edge must fit the chord at its radius, and
    # its outer corners must stay inside the ring.
    font + 2 * pad <= thick and
      tw + 2 * pad <= chord(inner, a.angle) and
      :math.sqrt(:math.pow(rm + font / 2, 2) + :math.pow(tw / 2, 2)) <= a.r_out - pad
  end

  defp fits?(:radial, a, tw, font, pad) do
    thick = a.r_out - a.r_in
    # Narrowest point of the text band is at its inner end.
    inner = max((a.r_in + a.r_out) / 2 - tw / 2, 0)
    tw + 2 * pad <= thick and font + 2 * pad <= chord(inner, a.angle)
  end

  defp chord(r, angle) when angle >= 180, do: 2 * r
  defp chord(r, angle), do: 2 * r * :math.sin(angle * :math.pi() / 360)

  # Text runs along +x; angle 0 is 12 o'clock, clockwise.
  defp rotation(_o, _mid, %{r_in: 0, angle: angle}) when angle >= 360 - @full_turn_eps, do: 0

  defp rotation(:tangential, mid, _a) do
    m = normalize_deg(mid)
    if m > 90 and m < 270, do: m - 180, else: m
  end

  defp rotation(:radial, mid, _a) do
    m = normalize_deg(mid)
    if m <= 180, do: m - 90, else: m + 90
  end

  defp normalize_deg(d) do
    r = :math.fmod(d * 1.0, 360.0)
    if r < 0, do: r + 360, else: r
  end

  defp label_text(cfg, a) do
    case cfg.data_labels.formatter do
      f when is_function(f, 1) -> to_string(f.(a.label))
      f when is_function(f, 2) -> to_string(f.(a.label, a))
      _ -> a.label
    end
  end

  defp label_color(dl, fill) do
    case dl.style.colors do
      nil -> contrast(fill)
      [] -> contrast(fill)
      colors when is_list(colors) -> hd(colors)
      c when is_binary(c) -> c
    end
  end

  # White on dark fills, dark grey on light ones (relative luminance).
  defp contrast("#" <> _ = hex) do
    {r, g, b} = Color.parse(hex)
    lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    if lum > 0.62, do: "#373d3f", else: "#fff"
  end

  defp contrast(_), do: "#fff"

  # ── Total in the hole ───────────────────────────────────────────────────

  defp total(cfg, geo) do
    t = cfg.plot_options.sunburst.total

    if t.show and geo.hole_r > 0 and geo.arcs != [] do
      value =
        case t.formatter do
          f when is_function(f, 1) -> to_string(f.(geo.total))
          _ -> fmt_value(geo.total)
        end

      avail = 2 * geo.hole_r - 8
      fore = cfg.chart.fore_color

      lines =
        [{t.label, 12, 400, -9}, {value, 16, 600, 9}]
        |> Enum.filter(fn {text, size, _, _} ->
          text not in [nil, ""] and Layout.text_width(to_string(text), size) <= avail and
            size * 2.4 <= 2 * geo.hole_r
        end)

      offset = if length(lines) == 1, do: fn _ -> 0 end, else: & &1

      texts =
        Enum.map(lines, fn {text, size, weight, dy} ->
          el(
            "text",
            %{
              x: geo.cx,
              y: geo.cy + offset.(dy),
              text_anchor: "middle",
              dominant_baseline: "central",
              fill: fore,
              font_size: size,
              font_weight: weight
            },
            esc(text)
          )
        end)

      el("g", %{class: "eexcharts-sunburst-total"}, texts)
    else
      []
    end
  end

  # ── Tooltips ────────────────────────────────────────────────────────────

  defp tooltips(cfg, geo) do
    if cfg.tooltip.enabled do
      tips =
        Enum.map(geo.arcs, fn a ->
          {share_label, base} =
            if a.depth == 0,
              do: {"Share of total", geo.total},
              else: {"Share of parent", a.parent_value}

          Hierarchy.tooltip(
            cfg,
            a.key,
            a.color,
            a.labels,
            a.value,
            share_label,
            Hierarchy.share(a.value, base)
          )
        end)

      Renderer.tooltip_container(cfg, tips)
    else
      []
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp polar(cx, cy, r, deg) do
    rad = :math.pi() * (deg - 90) / 180
    {cx + r * :math.cos(rad), cy + r * :math.sin(rad)}
  end

  defp pct(value) when is_number(value), do: value

  defp pct(value) when is_binary(value) do
    case Float.parse(value) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp first_color([c | _], _default), do: c
  defp first_color(c, _default) when is_binary(c), do: c
  defp first_color(_, default), do: default

  defp dim(v, _default) when is_number(v), do: v
  defp dim(_, default), do: default
end
