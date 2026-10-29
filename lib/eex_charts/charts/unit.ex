defmodule EexCharts.Charts.Unit do
  @moduledoc """
  Unit charts (`type: :unit`) and waffle charts (`type: :waffle`): one mark
  per unit of value, coloured per category.

  Written from the public description of the feature and from the usual
  geometry of these charts; it is not a port of any ApexCharts source.

  ## Data

  Each category is one *mark group* (one legend entry, one colour, one
  tooltip). Accepted shapes:

    * a list of numbers plus `labels:`: like pie/donut;
    * a single series whose `data` is `[%{x: label, y: value}, ...]` (or
      `{label, value}` tuples);
    * a list of series maps, one category each: `%{name: "A", data: 42}`
      (a numeric `data` list is summed).

  The `:beeswarm` layout instead takes ordinary series of x values:
  `[%{name: "A", data: [3.2, 4.1, ...]}]`, where a point may also be
  `%{x: value, label: "name"}` or `{label, value}`. Each point is one mark,
  coloured by its series.

  ## Options (`plot_options.unit`)

    * `layout`: `:grid` (default), `:parliament` or `:beeswarm`.
    * `per_unit`: value one mark stands for (default `1`). A category gets
      `round(value / per_unit)` marks; negative values count as zero.
    * `max_units`: ceiling on the marks drawn (default `2000`). When the
      counts exceed it, `per_unit` is raised to the next 1/2/5 x 10^k step
      that fits, and the tooltip reports the scale actually used.
    * `shape`: `:square`, `:rounded_square` or `:circle`; `nil` (default)
      means `:square`, or `:circle` for the beeswarm. Marks are plain SVG
      primitives.
    * `size`: mark edge / diameter in px; `nil` fits the marks to the plot
      area (beeswarm: `10`; marks and gap shrink together if the swarm
      would not fit the plot height).
    * `gap`: px between neighbouring marks (default `2`).
    * `radius`: corner radius of `:rounded_square` (default `size / 4`).
    * `rows`, `columns`: grid dimensions; either may be `nil` (derived).
      When both are given but too small for the marks, the dimension that is
      not being filled first grows.
    * `fill_order`: `:row` (left to right, then down; default) or
      `:column` (top to bottom, then right).
    * `parliament`: `inner_radius` (fraction of the outer radius, default
      `0.4`), `rows` (arcs; `nil` picks the count that gives the largest
      seats), `show_total` (default `true`: total in the hemicycle's centre).

  ## Layouts

  **Grid**: marks fill a `rows x columns` lattice in `fill_order`, category
  after category. Without explicit dimensions the column count is the one
  that gives the largest square cell for the plot area.

  **Parliament** (hemicycle): `rows` concentric half-rings of equal
  thickness between the inner and outer radius. Seats are shared between
  rows in proportion to arc length (largest remainder), spaced evenly in
  each row, then all seats are ordered by angle from left to right and
  handed to the categories in order, so every party forms a wedge. The mark
  size is the smaller of ring thickness and the tightest chord between two
  neighbours in a row, so no two seats overlap.

  **Beeswarm**: a numeric x-axis; every point keeps its exact x and is moved
  vertically by the smallest offset that does not overlap any mark already
  placed. Points are placed in x order (ties: input order) and the candidate
  offsets are `0` and the tangent positions against each nearby mark; the
  smallest `|offset|` wins (upward first on a tie), so the layout is
  deterministic.

  ## Waffle

  `type: :waffle` is a unit grid preset to `rows: 10, columns: 10`. The
  grid's cells (100 by default) are shared between the categories by the
  largest-remainder method, so each cell is one percent of the total and
  the cells always add up exactly.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, Legend, Renderer, Scale}

  @steps [1, 2, 5]

  @doc "Renders the complete unit / waffle container."
  def render_chart(cfg, params, id) do
    geo = geometry(cfg, params)
    l = geo.layout

    svg =
      Renderer.svg_open(cfg, l, id, [
        Renderer.background(cfg, l),
        Renderer.title(cfg, l),
        axis(cfg, geo),
        marks(cfg, geo, params),
        total_label(cfg, geo),
        Legend.render(geo.legend, cfg, legend_layout(l),
          hidden: Renderer.hidden_set(params),
          on_click: params[:on_legend_click]
        )
      ])

    Renderer.container(cfg, params, id, svg, tooltips(cfg, geo))
  end

  # ── Geometry ─────────────────────────────────────────────────────────────

  @doc """
  Computes the chart geometry without rendering it.

  Returns a map with `:kind` (`:grid`, `:parliament` or `:beeswarm`),
  `:marks` (`%{group: index, cx:, cy:, size:}`, plus `:point`/`:x` for the
  beeswarm), `:groups`, `:size`, `:per_unit` and the plot `:layout`.
  """
  def geometry(cfg, params) do
    opts = cfg.plot_options.unit
    hidden = Renderer.hidden_set(params)

    case opts.layout do
      :beeswarm -> beeswarm_geometry(cfg, opts, params, hidden)
      kind -> unit_geometry(cfg, opts, params, hidden, kind)
    end
  end

  defp unit_geometry(cfg, opts, params, hidden, kind) do
    groups = normalize_groups(params)
    visible = Enum.reject(groups, &MapSet.member?(hidden, &1.index))
    {l, legend} = frame(cfg, Enum.map(groups, & &1.name), 0)
    box = {l.grid_x, l.grid_y, l.grid_w, l.grid_h}

    waffle? = cfg.chart.type == :waffle
    {counts, per_unit} = counts(visible, opts, waffle?)
    total_values = visible |> Enum.map(&max(&1.value, 0)) |> Enum.sum()

    count_of = visible |> Enum.map(& &1.index) |> Enum.zip(counts) |> Map.new()

    groups =
      Enum.map(groups, fn g ->
        count = Map.get(count_of, g.index, 0)
        share = if total_values > 0, do: max(g.value, 0) / total_values, else: 0

        Map.merge(g, %{
          count: count,
          share: share,
          color: Config.color_at(cfg, g.index),
          hidden: MapSet.member?(hidden, g.index)
        })
      end)

    owners =
      visible
      |> Enum.zip(counts)
      |> Enum.flat_map(fn {g, c} -> List.duplicate(g.index, c) end)

    n = length(owners)

    {positions, size, extra} =
      case kind do
        :parliament ->
          {seats, size, center} = parliament(n, box, opts)
          {seats, size, %{center: center, total: total_values}}

        _ ->
          {cells, size} = grid(n, box, opts)
          {cells, size, %{}}
      end

    marks =
      owners
      |> Enum.zip(positions)
      |> Enum.map(fn {g, {cx, cy}} -> %{group: g, cx: cx, cy: cy, size: size} end)

    Map.merge(
      %{
        kind: if(kind == :parliament, do: :parliament, else: :grid),
        waffle: waffle?,
        groups: groups,
        marks: marks,
        size: size,
        per_unit: per_unit,
        layout: l,
        legend: legend
      },
      extra
    )
  end

  # ── Unit counts ──────────────────────────────────────────────────────────

  defp counts(visible, opts, true) do
    total = waffle_cells(opts)
    {largest_remainder(Enum.map(visible, & &1.value), total), nil}
  end

  defp counts(visible, opts, false) do
    values = Enum.map(visible, &max(&1.value, 0))
    per_unit = fit_per_unit(values, positive(opts.per_unit, 1), opts.max_units)
    {Enum.map(values, &round(&1 / per_unit)), per_unit}
  end

  defp waffle_cells(opts) do
    rows = positive(opts.rows, 10)
    cols = positive(opts.columns, 10)
    round(rows) * round(cols)
  end

  # Raises `per_unit` along the 1/2/5 ladder until the mark count fits.
  defp fit_per_unit(values, per_unit, max_units) do
    total = values |> Enum.map(&round(&1 / per_unit)) |> Enum.sum()

    if is_number(max_units) and total > max_units do
      fit_per_unit(values, next_step(per_unit), max_units)
    else
      per_unit
    end
  end

  defp next_step(v) do
    mag = :math.pow(10, :math.floor(:math.log10(v)))
    next = Enum.find(@steps, &(&1 * mag > v * (1 + 1.0e-9)))
    if next, do: next * mag, else: 10 * mag
  end

  @doc """
  Splits `total` whole units between `values` in proportion, using the
  largest-remainder (Hamilton) method: every value gets the floor of its
  quota, and the units left over go to the largest fractional remainders
  (earlier values win ties). The result always sums to `total` unless every
  value is zero or negative, in which case it is all zeros.
  """
  def largest_remainder(values, total) do
    values = Enum.map(values, fn v -> if is_number(v) and v > 0, do: v, else: 0 end)
    sum = Enum.sum(values)

    if sum <= 0 or total <= 0 do
      Enum.map(values, fn _ -> 0 end)
    else
      quotas = Enum.map(values, &(&1 * total / sum))
      floors = Enum.map(quotas, &trunc(&1 + 1.0e-9))
      left = total - Enum.sum(floors)

      bonus =
        quotas
        |> Enum.zip(floors)
        |> Enum.with_index()
        |> Enum.sort_by(fn {{q, f}, i} -> {-(q - f), i} end)
        |> Enum.take(max(left, 0))
        |> MapSet.new(fn {_, i} -> i end)

      floors
      |> Enum.with_index()
      |> Enum.map(fn {f, i} -> if MapSet.member?(bonus, i), do: f + 1, else: f end)
    end
  end

  # ── Grid ─────────────────────────────────────────────────────────────────

  @doc """
  Grid placement of `n` marks inside `{x, y, w, h}`. Returns
  `{[{cx, cy}], size}` in fill order.
  """
  def grid(0, _box, _opts), do: {[], 0}

  def grid(n, {x, y, w, h}, opts) do
    gap = gap(opts)
    order = opts.fill_order
    {rows, cols} = grid_dims(n, w, h, opts, gap)

    size =
      case opts.size do
        s when is_number(s) and s > 0 -> s
        _ -> max(min((w + gap) / cols, (h + gap) / rows) - gap, 1)
      end

    pitch = size + gap
    x0 = x + (w - (cols * pitch - gap)) / 2 + size / 2
    y0 = y + (h - (rows * pitch - gap)) / 2 + size / 2

    cells =
      Enum.map(0..(n - 1), fn k ->
        {r, c} =
          if order == :column,
            do: {rem(k, rows), div(k, rows)},
            else: {div(k, cols), rem(k, cols)}

        {x0 + c * pitch, y0 + r * pitch}
      end)

    {cells, size}
  end

  defp grid_dims(n, w, h, opts, gap) do
    rows = int_opt(opts.rows)
    cols = int_opt(opts.columns)
    column? = opts.fill_order == :column

    case {rows, cols} do
      {r, c} when is_integer(r) and is_integer(c) ->
        cond do
          r * c >= n -> {r, c}
          column? -> {r, ceil_div(n, r)}
          true -> {ceil_div(n, c), c}
        end

      {nil, c} when is_integer(c) ->
        {ceil_div(n, c), c}

      {r, nil} when is_integer(r) ->
        {r, ceil_div(n, r)}

      {nil, nil} ->
        auto_dims(n, w, h, opts.size, gap, column?)
    end
  end

  # With a fixed mark size, fill the plot's width (rows) or height (columns).
  defp auto_dims(n, w, h, size, gap, column?) when is_number(size) and size > 0 do
    pitch = size + gap

    if column? do
      r = (h + gap) |> Kernel./(pitch) |> trunc() |> max(1) |> min(n)
      {r, ceil_div(n, r)}
    else
      c = (w + gap) |> Kernel./(pitch) |> trunc() |> max(1) |> min(n)
      {ceil_div(n, c), c}
    end
  end

  # Otherwise pick the column count that gives the largest square cell
  # (fewest empty cells on a tie).
  defp auto_dims(n, w, h, _size, gap, _column?) do
    {_, _, rows, cols} =
      1..n
      |> Enum.map(fn c ->
        r = ceil_div(n, c)
        pitch = min((w + gap) / c, (h + gap) / r)
        {pitch, -(r * c), r, c}
      end)
      |> Enum.max()

    {rows, cols}
  end

  # ── Parliament ───────────────────────────────────────────────────────────

  @doc """
  Hemicycle placement of `n` seats inside `{x, y, w, h}`. Returns
  `{[{cx, cy}] ordered left to right by angle, size, {cx, cy, inner_r}}`.
  """
  def parliament(0, {x, y, w, h}, _opts), do: {[], 0, {x + w / 2, y + h, 0}}

  def parliament(n, {x, y, w, h} = box, opts) do
    p = opts.parliament
    rho = p.inner_radius |> num(0.4) |> max(0.0) |> min(0.95)
    gap = gap(opts)

    k =
      case int_opt(p.rows) do
        nil -> best_rows(n, box, rho, gap)
        r -> min(r, n)
      end

    {r_out, per_row, pitch} = hemicycle(n, k, w, h, rho)
    band = (1 - rho) * r_out / k
    height = r_out + band / 2
    cx = x + w / 2
    cy = y + (h - height) / 2 + r_out

    size =
      case opts.size do
        s when is_number(s) and s > 0 -> s
        _ -> max(pitch - gap, 1)
      end

    seats =
      per_row
      |> Enum.with_index()
      |> Enum.flat_map(fn {n_i, i} ->
        r = r_out * (rho + (i + 0.5) * (1 - rho) / k)

        if n_i == 0 do
          []
        else
          Enum.map(0..(n_i - 1), fn s ->
            theta = :math.pi() * (1 - (s + 0.5) / n_i)
            {theta, i, {cx + r * :math.cos(theta), cy - r * :math.sin(theta)}}
          end)
        end
      end)
      |> Enum.sort_by(fn {theta, i, _} -> {-theta, i} end)
      |> Enum.map(fn {_, _, pos} -> pos end)

    {seats, size, {cx, cy, rho * r_out}}
  end

  # Outer radius, seats per row, and the free spacing between neighbours
  # (smaller of ring thickness and the tightest in-row chord).
  defp hemicycle(n, k, w, h, rho) do
    r_out = min(w / 2, h / (1 + (1 - rho) / (2 * k)))
    radii = Enum.map(0..(k - 1), fn i -> rho + (i + 0.5) * (1 - rho) / k end)
    per_row = largest_remainder(radii, n)
    band = (1 - rho) * r_out / k

    chord =
      radii
      |> Enum.zip(per_row)
      |> Enum.filter(fn {_, n_i} -> n_i > 1 end)
      |> Enum.map(fn {r, n_i} -> 2 * r * r_out * :math.sin(:math.pi() / (2 * n_i)) end)
      |> Enum.min(fn -> band end)

    {r_out, per_row, min(band, chord)}
  end

  defp best_rows(n, {_x, _y, w, h}, rho, _gap) do
    1..min(n, 60)
    |> Enum.map(fn k ->
      {_, _, pitch} = hemicycle(n, k, w, h, rho)
      {pitch, -k}
    end)
    |> Enum.max()
    |> then(fn {_, neg_k} -> -neg_k end)
  end

  # ── Beeswarm ─────────────────────────────────────────────────────────────

  defp beeswarm_geometry(cfg, opts, params, hidden) do
    series = normalize_swarm(params)
    visible = Enum.reject(series, &MapSet.member?(hidden, &1.index))
    axis_font = cfg.xaxis.labels.style.font_size
    title_extra = if cfg.xaxis.title.text, do: cfg.xaxis.title.style.font_size + 6, else: 0

    {l, legend} = frame(cfg, Enum.map(series, & &1.name), axis_font + 14 + title_extra)

    xs = Enum.flat_map(visible, fn s -> Enum.map(s.points, & &1.x) end)
    scale = swarm_scale(cfg, xs, l.grid_w)
    x_for = x_mapper(scale, l)

    points =
      visible
      |> Enum.flat_map(fn s ->
        s.points
        |> Enum.with_index()
        |> Enum.map(fn {pt, j} -> Map.merge(pt, %{series: s.index, j: j, px: x_for.(pt.x)}) end)
      end)

    gap = gap(opts)
    base = if is_number(opts.size) and opts.size > 0, do: opts.size, else: 10
    {offsets, size, gap} = fit_swarm(Enum.map(points, & &1.px), base, gap, l.grid_h / 2, 0)
    mid = l.grid_y + l.grid_h / 2

    marks =
      points
      |> Enum.zip(offsets)
      |> Enum.map(fn {pt, dy} ->
        %{
          group: pt.series,
          j: pt.j,
          x: pt.x,
          label: pt.label,
          cx: pt.px,
          cy: mid - dy,
          size: size
        }
      end)

    groups =
      Enum.map(series, fn s ->
        %{
          name: s.name,
          index: s.index,
          color: Config.color_at(cfg, s.index),
          hidden: MapSet.member?(hidden, s.index)
        }
      end)

    %{
      kind: :beeswarm,
      waffle: false,
      groups: groups,
      marks: marks,
      size: size,
      gap: gap,
      per_unit: nil,
      scale: scale,
      x_for: x_for,
      layout: l,
      legend: legend
    }
  end

  # Shrinks marks and gap together until the swarm fits in the plot's half
  # height. Marks never overlap; a swarm that cannot fit even at 1 px marks
  # (thousands of points on one x) overflows the plot rather than overlap.
  defp fit_swarm(pxs, size, gap, half_h, tries) do
    offsets = swarm(pxs, size + gap)
    extent = offsets |> Enum.map(&abs/1) |> Enum.max(fn -> 0 end)

    if extent + size / 2 > half_h and tries < 40 and size > 1 do
      fit_swarm(pxs, max(size * 0.85, 1), gap * 0.85, half_h, tries + 1)
    else
      {offsets, size, gap}
    end
  end

  @doc """
  Greedy beeswarm: vertical offsets (positive = up) for marks at the given
  x pixel positions, so that no two centres are closer than `d`. Returns
  offsets in input order.
  """
  def swarm(pxs, d) do
    pxs
    |> Enum.with_index()
    |> Enum.sort_by(fn {x, i} -> {x, i} end)
    |> Enum.reduce({[], %{}}, fn {x, i}, {placed, acc} ->
      near = Enum.take_while(placed, fn {px, _} -> x - px < d end)
      y = swarm_offset(x, near, d)
      {[{x, y} | placed], Map.put(acc, i, y)}
    end)
    |> then(fn {_, acc} -> Enum.map(0..(length(pxs) - 1)//1, &Map.fetch!(acc, &1)) end)
  end

  defp swarm_offset(_x, [], _d), do: 0.0

  defp swarm_offset(x, near, d) do
    d2 = d * d

    candidates =
      Enum.flat_map(near, fn {px, py} ->
        h = :math.sqrt(max(d2 - (x - px) * (x - px), 0))
        [py + h, py - h]
      end)

    [0.0 | candidates]
    |> Enum.filter(fn y ->
      Enum.all?(near, fn {px, py} -> (x - px) * (x - px) + (y - py) * (y - py) >= d2 - 1.0e-6 end)
    end)
    |> Enum.min_by(fn y -> {abs(y), y < 0} end)
  end

  defp swarm_scale(_cfg, [], _w), do: %{ticks: [0, 1], min: 0, max: 1}

  defp swarm_scale(cfg, xs, w) do
    {lo, hi} = Enum.min_max(xs)
    lo = if is_number(cfg.xaxis.min), do: cfg.xaxis.min, else: lo
    hi = if is_number(cfg.xaxis.max), do: cfg.xaxis.max, else: hi
    {lo, hi} = if lo == hi, do: {lo - 1, hi + 1}, else: {lo, hi}

    ticks =
      if is_number(cfg.xaxis.tick_amount),
        do: round(cfg.xaxis.tick_amount),
        else: max(round(w / 90), 2)

    s =
      Scale.nice_scale(lo, hi,
        min: cfg.xaxis.min,
        max: cfg.xaxis.max,
        tick_amount: ticks,
        step_size: cfg.xaxis.step_size
      )

    %{ticks: s.ticks, min: s.nice_min, max: s.nice_max}
  end

  defp x_mapper(%{min: mn, max: mx}, l) do
    span = mx - mn
    fn v -> l.grid_x + (v - mn) / span * l.grid_w end
  end

  # ── Frame (title, legend, plot area) ──────────────────────────────────────

  defp frame(cfg, names, bottom_extra) do
    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    legend = Legend.measure(cfg, names, w, h)
    pad = cfg.grid.padding

    {right, top, bottom} =
      case legend do
        %Legend{show: false} -> {0, 0, 0}
        %Legend{position: :right, w: lw} -> {lw, 0, 0}
        %Legend{position: :top, h: lh} -> {0, lh, 0}
        %Legend{h: lh} -> {0, 0, lh}
      end

    x = pad.left
    y = title_h + top + pad.top + 10
    gw = max(w - x - pad.right - right, 10)
    gh = max(h - y - pad.bottom - bottom - bottom_extra - 10, 10)

    l = %Layout{
      w: w,
      h: h,
      grid_x: x,
      grid_y: y,
      grid_w: gw,
      grid_h: gh,
      legend: legend,
      title_h: title_h
    }

    {l, legend}
  end

  # The legend places a top legend relative to `grid_y` the way the pie does
  # (the plot starts below the title).
  defp legend_layout(%Layout{legend: %Legend{position: :top}} = l), do: %{l | grid_y: l.title_h}
  defp legend_layout(l), do: l

  # ── Marks ────────────────────────────────────────────────────────────────

  defp marks(cfg, geo, params) do
    opts = cfg.plot_options.unit
    shape = shape(opts.shape, geo.kind)
    on_click = params[:on_click]
    by_group = Enum.group_by(geo.marks, & &1.group)

    groups =
      geo.groups
      |> Enum.reject(& &1.hidden)
      |> Enum.map(fn g ->
        ms = Map.get(by_group, g.index, [])

        if geo.kind == :beeswarm do
          el(
            "g",
            %{class: "eexcharts-unit-series", fill: g.color, fill_opacity: cfg.fill.opacity},
            Enum.map(ms, fn m ->
              m
              |> mark(shape, opts, %{data_j: "#{g.index}-#{m.j}"})
              |> click(on_click, m.j, g.index)
            end)
          )
        else
          %{
            class: "eexcharts-unit-group",
            data_j: g.index,
            fill: g.color,
            fill_opacity: cfg.fill.opacity
          }
          |> click_attrs(on_click, g.index, g.index)
          |> then(&el("g", &1, Enum.map(ms, fn m -> mark(m, shape, opts, %{}) end)))
        end
      end)

    el("g", %{class: "eexcharts-unit eexcharts-unit-#{geo.kind}"}, groups)
  end

  defp shape(s, _kind) when s in [:square, :rounded_square, :circle], do: s
  defp shape(_, :beeswarm), do: :circle
  defp shape(_, _), do: :square

  defp mark(m, :circle, _opts, attrs) do
    el("circle", Map.merge(%{cx: m.cx, cy: m.cy, r: m.size / 2}, attrs))
  end

  defp mark(m, shape, opts, attrs) do
    s = m.size

    rx =
      case {shape, opts.radius} do
        {:rounded_square, r} when is_number(r) -> min(r, s / 2)
        {:rounded_square, _} -> s / 4
        _ -> nil
      end

    el(
      "rect",
      Map.merge(%{x: m.cx - s / 2, y: m.cy - s / 2, width: s, height: s, rx: rx}, attrs)
    )
  end

  defp click({:el, tag, attrs, children}, on_click, j, series),
    do: {:el, tag, click_attrs(attrs, on_click, j, series), children}

  defp click_attrs(attrs, nil, _j, _series), do: attrs

  defp click_attrs(attrs, on_click, j, series) do
    Map.merge(attrs, %{
      "phx-click" => on_click,
      "phx-value-index" => j,
      "phx-value-series" => series,
      cursor: "pointer"
    })
  end

  # ── Parliament total ─────────────────────────────────────────────────────

  defp total_label(cfg, %{kind: :parliament, center: {cx, cy, inner}} = geo) do
    if cfg.plot_options.unit.parliament.show_total and inner > 12 and geo.marks != [] do
      font = min(28, inner * 0.45)

      el(
        "text",
        %{
          class: "eexcharts-unit-total",
          x: cx,
          y: cy - font * 0.15,
          text_anchor: "middle",
          fill: cfg.chart.fore_color,
          font_size: font,
          font_weight: 600
        },
        esc(Renderer.format_tooltip_y(cfg, geo.total))
      )
    else
      []
    end
  end

  defp total_label(_cfg, _geo), do: []

  # ── Beeswarm axis ────────────────────────────────────────────────────────

  defp axis(cfg, %{kind: :beeswarm, scale: scale, x_for: x_for, layout: l}) do
    bottom = l.grid_y + l.grid_h
    style = cfg.xaxis.labels.style
    color = label_color(style.colors, cfg.chart.fore_color)

    grid =
      if cfg.grid.show do
        Enum.map(scale.ticks, fn t ->
          x = x_for.(t)

          el("line", %{
            class: "eexcharts-grid-line",
            x1: x,
            y1: l.grid_y,
            x2: x,
            y2: bottom,
            stroke: cfg.grid.border_color,
            stroke_width: cfg.grid.border_width
          })
        end)
      else
        []
      end

    border =
      if cfg.xaxis.axis_border.show do
        el("line", %{
          class: "eexcharts-axis-border",
          x1: l.grid_x,
          y1: bottom,
          x2: l.grid_x + l.grid_w,
          y2: bottom,
          stroke: cfg.xaxis.axis_border.color,
          stroke_width: cfg.xaxis.axis_border.height
        })
      else
        []
      end

    labels =
      if cfg.xaxis.labels.show do
        Enum.map(scale.ticks, fn t ->
          el(
            "text",
            %{
              class: "eexcharts-xaxis-label",
              x: x_for.(t),
              y: bottom + style.font_size + 8,
              text_anchor: "middle",
              fill: color,
              font_family: style.font_family,
              font_size: style.font_size,
              font_weight: style.font_weight
            },
            esc(format_x(cfg, t))
          )
        end)
      else
        []
      end

    title =
      case cfg.xaxis.title do
        %{text: text, style: ts} when is_binary(text) ->
          el(
            "text",
            %{
              class: "eexcharts-xaxis-title",
              x: l.grid_x + l.grid_w / 2,
              y: bottom + style.font_size + ts.font_size + 16,
              text_anchor: "middle",
              fill: ts.color || cfg.chart.fore_color,
              font_size: ts.font_size,
              font_weight: ts.font_weight
            },
            esc(text)
          )

        _ ->
          []
      end

    el("g", %{class: "eexcharts-unit-axis"}, [grid, border, labels, title])
  end

  defp axis(_cfg, _geo), do: []

  defp format_x(cfg, v) do
    case cfg.xaxis.labels.formatter do
      f when is_function(f, 1) -> to_string(f.(v))
      _ -> fmt_value(v)
    end
  end

  defp label_color([c | _], _fore), do: c
  defp label_color(c, _fore) when is_binary(c), do: c
  defp label_color(_, fore), do: fore

  # ── Tooltips ─────────────────────────────────────────────────────────────

  defp tooltips(cfg, geo) do
    if cfg.tooltip.enabled do
      geo |> tips(cfg) |> then(&Renderer.tooltip_container(cfg, &1))
    else
      []
    end
  end

  defp tips(%{kind: :beeswarm} = geo, cfg) do
    colors = Map.new(geo.groups, &{&1.index, &1})

    Enum.map(geo.marks, fn m ->
      g = colors[m.group]
      title = if m.label, do: [el("div", %{class: "eexcharts-tip-title"}, esc(m.label))], else: []

      el("div", %{class: "eexcharts-tip", data_j: "#{m.group}-#{m.j}", hidden: true}, [
        title,
        Renderer.tooltip_row(g.color, g.name, Renderer.format_tooltip_y(cfg, m.x))
      ])
    end)
  end

  defp tips(geo, cfg) do
    geo.groups
    |> Enum.reject(& &1.hidden)
    |> Enum.map(fn g ->
      value = Renderer.format_tooltip_y(cfg, g.value)
      value = if geo.waffle, do: "#{value} (#{g.count}%)", else: value

      units =
        if geo.waffle or geo.per_unit == nil,
          do: [],
          else: [
            el("div", %{class: "eexcharts-tip-row eexcharts-tip-units"}, [
              esc("#{g.count} x #{fmt_value(geo.per_unit)}")
            ])
          ]

      el("div", %{class: "eexcharts-tip", data_j: g.index, hidden: true}, [
        Renderer.tooltip_row(g.color, g.name, value),
        units
      ])
    end)
  end

  # ── Input normalization ──────────────────────────────────────────────────

  defp normalize_groups(params) do
    labels = params[:labels] || []

    case params[:series] do
      [_ | _] = list ->
        cond do
          Enum.all?(list, &is_number/1) ->
            Enum.with_index(list, fn v, i -> group(label_at(labels, i), v, i) end)

          match?([%{data: [p | _]}] when is_map(p) or is_tuple(p), list) ->
            [%{data: data}] = list

            Enum.with_index(data, fn pt, i ->
              {label, v} = point(pt)
              group(label || label_at(labels, i), v, i)
            end)

          true ->
            Enum.with_index(list, fn s, i ->
              name = if is_map(s), do: s[:name], else: nil
              group(name || label_at(labels, i), series_value(s), i)
            end)
        end

      _ ->
        []
    end
  end

  defp group(name, value, i), do: %{name: to_string(name), value: value, index: i}

  defp series_value(%{data: v}) when is_number(v), do: v

  defp series_value(%{data: list}) when is_list(list),
    do: list |> Enum.filter(&is_number/1) |> Enum.sum()

  defp series_value(v) when is_number(v), do: v
  defp series_value(_), do: 0

  defp point(%{x: x, y: y}), do: {x, num(y, 0)}
  defp point(%{label: x, value: y}), do: {x, num(y, 0)}
  defp point({x, y}), do: {x, num(y, 0)}
  defp point(_), do: {nil, 0}

  defp label_at(labels, i), do: Enum.at(labels, i) || "series-#{i + 1}"

  defp normalize_swarm(params) do
    case params[:series] do
      [_ | _] = list ->
        if Enum.all?(list, &is_number/1) do
          [%{name: "series-1", index: 0, points: swarm_points(list)}]
        else
          Enum.with_index(list, fn s, i ->
            {name, data} = if is_map(s), do: {s[:name], s[:data]}, else: {nil, s}
            %{name: to_string(name || "series-#{i + 1}"), index: i, points: swarm_points(data)}
          end)
        end

      _ ->
        []
    end
  end

  defp swarm_points(data) when is_list(data) do
    Enum.flat_map(data, fn
      v when is_number(v) -> [%{x: v, label: nil}]
      %{x: x} = p when is_number(x) -> [%{x: x, label: label_or_nil(p[:label] || p[:name])}]
      {label, x} when is_number(x) -> [%{x: x, label: to_string(label)}]
      _ -> []
    end)
  end

  defp swarm_points(_), do: []

  defp label_or_nil(nil), do: nil
  defp label_or_nil(v), do: to_string(v)

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp gap(opts), do: opts.gap |> num(2) |> max(0)

  defp int_opt(v) when is_number(v) and v >= 1, do: round(v)
  defp int_opt(_), do: nil

  defp positive(v, _default) when is_number(v) and v > 0, do: v
  defp positive(_, default), do: default

  defp num(v, _default) when is_number(v), do: v
  defp num(_, default), do: default

  defp ceil_div(a, b), do: div(a + b - 1, b)

  defp dim(v, _default) when is_number(v), do: v
  defp dim(_, default), do: default
end
