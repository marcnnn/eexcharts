defmodule EexCharts.Charts.Violin do
  @moduledoc """
  Violin chart (`type: :violin`): per category, the kernel density of the raw
  observations mirrored around the category's centre line.

  Each data point carries one category's raw observations:

      series: [
        %{name: "Response", data: [
          %{x: "A", y: [12.1, 15.3, 9.8, ...]},
          %{x: "B", y: [20.4, 18.0, ...]}
        ]}
      ]

  `%{x: label, observations: [...]}` and a bare list of numbers work too.
  When `categories` are not given they are taken from the points' `x`
  labels. Several series sit side by side in each category slot, like grouped
  columns (`plot_options.bar.column_width` sets the group width).

  ## Options (`plot_options: %{violin: %{...}}`)

    * `bandwidth` — KDE bandwidth: `:silverman` (default), `:scott`, or a
      number in y units (see `EexCharts.Stats.bandwidth/2`)
    * `cut` — how far the density extends past the extreme observations, in
      bandwidths (default `2`; `0` clips the shape at the data range)
    * `points` — density samples per violin (default `64`)
    * `scale` — `:width` (default; every violin is equally wide), `:area`
      (one density scale for all violins, so each has the same area) or
      `:count` (like `:area`, then scaled by the number of observations)
    * `inner` — `:box` (default; a narrow interquartile box with whiskers
      and a white median dot), `:median` (a line across the violin at the
      median) or `:none`
    * `raincloud` — `true` draws a raincloud plot instead: a half violin
      (the "cloud") to the right of the centre line, a narrow box at its
      base, and the raw observations as jittered points (the "rain") to the
      left. The jitter is a fixed hash of each observation's index
      (`EexCharts.Stats.jitter/1`), so the points never move between renders
    * `point_size` — radius of the raincloud points (default `2.5`)

  Fill and outline use the series color with `fill.opacity` (default `0.5`)
  and `stroke.width`; the inner box and whiskers use `chart.fore_color`. The
  tooltip lists each series' median, quartiles and observation count.

  Horizontal violins are not supported.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout, Stats}

  @doc """
  Computes the summary and density curve for every point and returns
  `{cfg, series}`. Each point becomes `%{x: label, values: [...], summary:
  map, curve: [{y, density}], bandwidth: h, scale: s}`, where `density * s`
  is the violin's half-width as a fraction of the space it may use.
  """
  def prepare(cfg, series) do
    vo = cfg.plot_options.violin
    curve_opts = [bandwidth: vo.bandwidth, cut: vo.cut, points: vo.points]

    series =
      Enum.map(series, fn s ->
        data =
          Enum.map(s.data, fn p ->
            values = observations(p)

            case Stats.density_curve(values, curve_opts) do
              nil ->
                %{x: label(p), values: [], summary: nil, curve: [], bandwidth: nil, max_d: 0}

              %{bandwidth: h, points: curve} ->
                %{
                  x: label(p),
                  values: values,
                  summary: Stats.summary(values),
                  curve: curve,
                  bandwidth: h,
                  max_d: curve |> Enum.map(&elem(&1, 1)) |> Enum.max()
                }
            end
          end)

        %{s | data: data}
      end)

    {derive_categories(cfg, series), apply_scale(series, vo.scale)}
  end

  defp observations(%{observations: obs}) when is_list(obs), do: Enum.filter(obs, &is_number/1)
  defp observations(%{y: obs}) when is_list(obs), do: Enum.filter(obs, &is_number/1)
  defp observations(obs) when is_list(obs), do: Enum.filter(obs, &is_number/1)
  defp observations(_), do: []

  defp label(%{x: x}), do: x
  defp label(_), do: nil

  defp derive_categories(%{xaxis: %{categories: []}} = cfg, series) do
    labels = for s <- series, p <- s.data, p.x != nil, uniq: true, do: to_string(p.x)
    if labels == [], do: cfg, else: put_in(cfg, [:xaxis, :categories], labels)
  end

  defp derive_categories(cfg, _series), do: cfg

  defp apply_scale(series, mode) do
    points = for s <- series, p <- s.data, p.max_d > 0, do: p
    global_max = points |> Enum.map(& &1.max_d) |> Enum.max(fn -> 0 end)
    count_max = points |> Enum.map(&(&1.max_d * &1.summary.n)) |> Enum.max(fn -> 0 end)

    Enum.map(series, fn s ->
      data =
        Enum.map(s.data, fn
          %{max_d: d} = p when d <= 0 ->
            Map.put(p, :scale, 0)

          p ->
            scale =
              case mode do
                :area -> 1 / global_max
                :count -> p.summary.n / count_max
                _width -> 1 / p.max_d
              end

            Map.put(p, :scale, scale)
        end)

      %{s | data: data}
    end)
  end

  @doc "Renders the prepared violin series into the cartesian grid."
  def render(cfg, series, %Layout{} = l, _opts \\ []) do
    vo = cfg.plot_options.violin
    n_series = max(length(series), 1)
    slot = l.grid_w / l.n
    group_w = slot * column_ratio(cfg.plot_options.bar.column_width)
    w = group_w / n_series

    series
    |> Enum.with_index()
    |> Enum.map(fn {s, pos_i} ->
      color = Config.color_at(cfg, s.index)
      paint = %{fill: color, stroke: Config.color_for(cfg.stroke.colors, s.index) || color}

      shapes =
        s.data
        |> Enum.with_index()
        |> Enum.flat_map(fn
          {%{summary: nil}, _j} ->
            []

          {p, j} ->
            cx = Layout.category_pos(l, j) - group_w / 2 + w * (pos_i + 0.5)
            violin(cfg, vo, l, p, j, cx, w, paint)
        end)

      el("g", %{class: "eexcharts-series"}, shapes)
    end)
  end

  defp violin(cfg, %{raincloud: true} = vo, l, p, j, cx, w, paint) do
    base = cx - 0.1 * w
    cloud = half_path(l, p, base, 0.6 * w)
    box_w = max(0.07 * w, 3)
    box_cx = base - 0.03 * w - box_w / 2
    rain_lo = cx - 0.5 * w
    rain_w = max(box_cx - box_w / 2 - 0.05 * w - rain_lo, 0)

    rain =
      p.values
      |> Enum.with_index()
      |> Enum.map(fn {v, i} ->
        el("circle", %{
          class: "eexcharts-violin-point",
          cx: rain_lo + Stats.jitter(i) * rain_w,
          cy: Layout.y_for(l, clamp(l, v)),
          r: vo.point_size,
          fill: paint.fill,
          fill_opacity: 0.7
        })
      end)

    [
      el("path", shape_attrs(cfg, cloud, j, paint)),
      inner_box(cfg, l, p.summary, box_cx, box_w),
      el("g", %{class: "eexcharts-violin-rain"}, rain)
    ]
  end

  defp violin(cfg, vo, l, p, j, cx, w, paint) do
    [
      el("path", shape_attrs(cfg, full_path(l, p, cx, w / 2), j, paint)),
      inner(cfg, vo.inner, l, p, cx, w)
    ]
  end

  defp shape_attrs(cfg, d, j, paint) do
    %{
      class: "eexcharts-violin",
      data_j: j,
      d: d,
      fill: paint.fill,
      fill_opacity: cfg.fill.opacity,
      stroke: paint.stroke,
      stroke_width: cfg.stroke.width
    }
  end

  # Right edge bottom-to-top, then the mirrored left edge back down.
  defp full_path(l, p, cx, half) do
    pts = Enum.map(p.curve, fn {y, d} -> {d * p.scale * half, Layout.y_for(l, clamp(l, y))} end)
    [{dx0, y0} | rest] = pts
    right = Enum.map(rest, fn {dx, y} -> line(cx + dx, y) end)
    left = pts |> Enum.reverse() |> Enum.map(fn {dx, y} -> line(cx - dx, y) end)
    [move(cx + dx0, y0) | right] ++ left ++ [close()]
  end

  # One-sided density, rising to the right of `base`.
  defp half_path(l, p, base, half) do
    pts =
      Enum.map(p.curve, fn {y, d} ->
        line(base + d * p.scale * half, Layout.y_for(l, clamp(l, y)))
      end)

    {y_first, _} = hd(p.curve)
    {y_last, _} = List.last(p.curve)

    [move(base, Layout.y_for(l, clamp(l, y_first)))] ++
      pts ++ [line(base, Layout.y_for(l, clamp(l, y_last))), close()]
  end

  defp inner(cfg, :box, l, p, cx, w), do: inner_box(cfg, l, p.summary, cx, max(0.08 * w, 3))

  defp inner(cfg, :median, l, p, cx, w) do
    med = p.summary.median
    [d] = Stats.kde(p.values, [med], p.bandwidth)
    half = d * p.scale * w / 2
    y = Layout.y_for(l, clamp(l, med))

    el("line", %{
      class: "eexcharts-violin-median",
      x1: cx - half,
      x2: cx + half,
      y1: y,
      y2: y,
      stroke: cfg.chart.fore_color,
      stroke_width: 2
    })
  end

  defp inner(_cfg, _none, _l, _p, _cx, _w), do: []

  # A narrow interquartile box, a whisker line across the Tukey whiskers and
  # a white median dot.
  defp inner_box(cfg, l, s, cx, box_w) do
    y = fn v -> Layout.y_for(l, clamp(l, v)) end
    ink = cfg.chart.fore_color

    el("g", %{class: "eexcharts-violin-box"}, [
      el("line", %{x1: cx, x2: cx, y1: y.(s.lower), y2: y.(s.upper), stroke: ink, stroke_width: 1}),
      el("rect", %{
        x: cx - box_w / 2,
        y: y.(s.q3),
        width: box_w,
        height: max(y.(s.q1) - y.(s.q3), 0),
        fill: ink
      }),
      el("circle", %{cx: cx, cy: y.(s.median), r: max(box_w * 0.3, 1.5), fill: "#fff"})
    ])
  end

  @doc "Returns `{y_min, y_max}` over every density curve and observation."
  def data_range(series) do
    ys =
      for s <- series,
          p <- s.data,
          y <- Enum.map(p.curve, &elem(&1, 0)) ++ p.values,
          do: y

    case ys do
      [] -> {nil, nil}
      _ -> Enum.min_max(ys)
    end
  end

  @doc "Formats one prepared violin point for the tooltip."
  def tooltip_value(cfg, %{summary: %{} = s}) do
    "Median: #{fmt_num(cfg, s.median)} Q1: #{fmt_num(cfg, s.q1)} " <>
      "Q3: #{fmt_num(cfg, s.q3)} n: #{s.n}"
  end

  def tooltip_value(_cfg, _p), do: ""

  defp fmt_num(cfg, n) do
    case cfg.tooltip.y_formatter do
      f when is_function(f, 1) -> to_string(f.(n))
      _ -> fmt_value(n)
    end
  end

  defp clamp(l, v), do: v |> max(l.scale.nice_min) |> min(l.scale.nice_max)

  defp column_ratio(v) when is_number(v), do: v / 100

  defp column_ratio(v) when is_binary(v) do
    case Integer.parse(v) do
      {pct, _} -> pct / 100
      :error -> 0.7
    end
  end

  defp column_ratio(_), do: 0.7
end
