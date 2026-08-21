defmodule EexCharts.Layout do
  @moduledoc """
  Computes the cartesian chart geometry: the plot ("grid") rectangle inside
  the SVG after reserving space for title, axis labels and legend, plus the
  value scale and coordinate mapping.

  ApexCharts measures rendered DOM text; server-side we estimate text extents
  from character counts (`text_width/2`).

  Supports a single value scale (the common case) as well as multiple y-axes
  (`cfg.yaxis` as a list), logarithmic y-axes, and numeric/datetime x-axes.
  The primary y-axis scale is always in `scale`; `scales`/`y_axes` carry the
  full per-axis lists.
  """

  alias EexCharts.{Config, Legend, Scale, SVG, TimeScale}

  defstruct w: 600,
            h: 350,
            grid_x: 0,
            grid_y: 0,
            grid_w: 0,
            grid_h: 0,
            n: 0,
            tick_placement: :on,
            horizontal: false,
            scale: nil,
            scales: [],
            y_axes: [],
            x_scale: nil,
            x_type: :category,
            legend: nil,
            title_h: 0

  @type t :: %__MODULE__{}

  @doc """
  Builds the layout for a cartesian chart.

    * `names` — series names (for legend sizing)
    * `n` — number of data points / categories
    * `{y_min, y_max}` — raw value range from the data

  This 4-arity form is the single-y-axis, category-x entry point; it delegates
  to `build/5` with one range and no x-value scale.
  """
  def build(cfg, names, n, {y_min, y_max}) do
    build(cfg, names, n, [{y_min, y_max}], nil)
  end

  @doc """
  Builds the layout given a list of per-y-axis `{min, max}` ranges and an
  optional `{x_min, x_max}` range for a numeric/datetime x-axis.
  """
  def build(cfg, names, n, y_ranges, x_range) when is_list(y_ranges) do
    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    horizontal = get_in(cfg, [:plot_options, :bar, :horizontal]) == true && cfg.chart.type == :bar
    pad = cfg.grid.padding

    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    legend = Legend.measure(cfg, names, w, h)

    y_axes = Config.yaxes(cfg)
    svg_dim = if horizontal, do: w, else: h

    # Pair each axis with its range (falling back to the first range/axis when
    # the caller supplied fewer of one than the other).
    scales =
      y_axes
      |> Enum.with_index()
      |> Enum.map(fn {axis, i} ->
        {mn, mx} = Enum.at(y_ranges, i, hd(y_ranges))
        axis_scale(axis, mn, mx, svg_dim)
      end)

    primary = hd(scales)

    x_font = cfg.xaxis.labels.style.font_size
    categories = cfg.xaxis.categories

    # ── Left / right gutters ────────────────────────────────────────────────
    {left_axes, right_axes} =
      y_axes
      |> Enum.zip(scales)
      |> Enum.with_index()
      |> Enum.split_with(fn {{axis, _s}, _i} -> not axis.opposite end)

    {left_label_w, left_title_w} =
      if horizontal do
        # Horizontal bars: the left gutter shows category labels, not values.
        y_font = hd(y_axes).labels.style.font_size

        w0 =
          if hd(y_axes).labels.show and categories != [] do
            categories
            |> Enum.map(&text_width(to_string(&1), y_font))
            |> Enum.max(fn -> 0 end)
            |> max(hd(y_axes).labels.min_width)
            |> min(hd(y_axes).labels.max_width)
          else
            0
          end

        {w0, if(hd(y_axes).title.text, do: hd(y_axes).title.style.font_size + 10, else: 0)}
      else
        {axes_label_width(cfg, left_axes), axes_title_width(left_axes)}
      end

    {right_label_w, right_title_w} =
      if horizontal,
        do: {0, 0},
        else: {axes_label_width(cfg, right_axes), axes_title_width(right_axes)}

    x_label_h =
      if cfg.xaxis.labels.show do
        tick_h = if cfg.xaxis.axis_ticks.show, do: cfg.xaxis.axis_ticks.height, else: 0
        tick_h + rotated_label_height(cfg, categories, x_font) + 12
      else
        4
      end

    # An x-axis title sits below the labels, so it eats into the plot height.
    x_label_h =
      if cfg.xaxis.title.text,
        do: x_label_h + cfg.xaxis.title.style.font_size + 10,
        else: x_label_h

    grid_x = pad.left + left_title_w + left_label_w + if(left_label_w > 0, do: 10, else: 0)
    grid_y = pad.top + title_h + 12

    legend_right = if legend.position == :right, do: legend.w, else: 0

    right =
      pad.right + legend_right + right_title_w + right_label_w +
        if(right_label_w > 0, do: 10, else: 0)

    bottom_legend_h = if legend.position in [:bottom, :top], do: legend.h, else: 0

    {grid_y, bottom} =
      if legend.position == :top do
        {grid_y + bottom_legend_h, pad.bottom + x_label_h}
      else
        {grid_y, pad.bottom + x_label_h + bottom_legend_h}
      end

    grid_w = max(w - grid_x - right, 10)
    grid_h = max(h - grid_y - bottom, 10)

    x_scale = build_x_scale(cfg, x_range, grid_w)

    %__MODULE__{
      w: w,
      h: h,
      grid_x: grid_x,
      grid_y: grid_y,
      grid_w: grid_w,
      grid_h: grid_h,
      n: max(n, 1),
      tick_placement: cfg.xaxis.tick_placement,
      horizontal: horizontal,
      scale: primary,
      scales: scales,
      y_axes: y_axes,
      x_scale: x_scale,
      x_type: if(x_scale, do: x_scale.type, else: :category),
      legend: legend,
      title_h: title_h
    }
  end

  # Chooses the appropriate scale (linear/nice or logarithmic) for one y-axis.
  defp axis_scale(axis, mn, mx, svg_dim) do
    if axis.logarithmic do
      Scale.log_scale(mn, mx, axis.log_base, axis.force_nice_scale)
    else
      Scale.nice_scale(mn, mx,
        min: axis.min,
        max: axis.max,
        tick_amount: axis.tick_amount,
        step_size: axis.step_size,
        svg_height: svg_dim
      )
    end
  end

  defp axes_label_width(_cfg, []), do: 0

  defp axes_label_width(cfg, axes_with_scales) do
    axes_with_scales
    |> Enum.map(fn {{axis, scale}, _i} ->
      if axis.labels.show do
        scale.ticks
        |> Enum.with_index()
        |> Enum.map(fn {t, i} ->
          text_width(format_y_label(cfg, axis, t, i), axis.labels.style.font_size)
        end)
        |> Enum.max(fn -> 0 end)
        |> max(axis.labels.min_width)
        |> min(axis.labels.max_width)
      else
        0
      end
    end)
    |> Enum.sum()
  end

  defp axes_title_width([]), do: 0

  defp axes_title_width(axes_with_scales) do
    axes_with_scales
    |> Enum.map(fn {{axis, _s}, _i} ->
      if axis.title.text, do: axis.title.style.font_size + 10, else: 0
    end)
    |> Enum.sum()
  end

  # ── X value scale (numeric / datetime) ─────────────────────────────────────

  defp build_x_scale(_cfg, nil, _grid_w), do: nil

  defp build_x_scale(cfg, {x_min, x_max}, grid_w) do
    case cfg.xaxis.type do
      :datetime -> datetime_x_scale(cfg, x_min, x_max, grid_w)
      _ -> numeric_x_scale(cfg, x_min, x_max, grid_w)
    end
  end

  defp numeric_x_scale(cfg, x_min, x_max, grid_w) do
    x_min = if is_number(cfg.xaxis.min), do: cfg.xaxis.min, else: x_min
    x_max = if is_number(cfg.xaxis.max), do: cfg.xaxis.max, else: x_max
    x_min = if is_number(cfg.xaxis.range), do: x_max - cfg.xaxis.range, else: x_min

    ticks =
      if is_number(cfg.xaxis.tick_amount),
        do: round(cfg.xaxis.tick_amount),
        else: max(round(grid_w / 150), 1)

    {result, nmin, nmax} = Scale.linear_scale(x_min, x_max, ticks, cfg.xaxis.step_size)

    labels = Enum.map(result, fn v -> %{value: v, label: SVG.fmt_value(v)} end)
    %{type: :numeric, ticks: labels, nice_min: nmin, nice_max: nmax}
  end

  defp datetime_x_scale(cfg, x_min, x_max, grid_w) do
    x_min = if is_number(cfg.xaxis.min), do: cfg.xaxis.min, else: x_min
    x_max = if is_number(cfg.xaxis.max), do: cfg.xaxis.max, else: x_max

    ticks = TimeScale.ticks(x_min, x_max, grid_w)
    labels = Enum.map(ticks, fn t -> %{value: t.value, label: t.label} end)
    %{type: :datetime, ticks: labels, nice_min: x_min, nice_max: x_max}
  end

  @doc "Pixel position of the center of category slot `i` on the category axis."
  def category_pos(%__MODULE__{horizontal: true} = l, i) do
    slot = l.grid_h / l.n
    l.grid_y + slot * (i + 0.5)
  end

  def category_pos(%__MODULE__{tick_placement: :between} = l, i) do
    slot = l.grid_w / l.n
    l.grid_x + slot * (i + 0.5)
  end

  def category_pos(%__MODULE__{} = l, i) do
    if l.n == 1 do
      l.grid_x + l.grid_w / 2
    else
      l.grid_x + l.grid_w * i / (l.n - 1)
    end
  end

  @doc "Pixel x for a numeric / datetime x value (charts with an x-value scale)."
  def x_value_pos(%__MODULE__{x_scale: xs} = l, x) when is_map(xs) do
    range = xs.nice_max - xs.nice_min

    if range == 0,
      do: l.grid_x + l.grid_w / 2,
      else: l.grid_x + (x - xs.nice_min) / range * l.grid_w
  end

  @doc "Pixel y for a data value on the primary y-axis (vertical charts)."
  def y_for(%__MODULE__{} = l, v), do: y_for(l, v, l.scale)

  @doc "Pixel y for a data value on the given `scale` (log-aware)."
  def y_for(%__MODULE__{} = l, v, %Scale{log: true, log_base: base} = scale) do
    lb = :math.log(base)
    lmin = safe_log(scale.nice_min, lb)
    lmax = safe_log(scale.nice_max, lb)
    range = lmax - lmin
    lv = safe_log(v, lb)
    l.grid_y + l.grid_h - (lv - lmin) / range * l.grid_h
  end

  def y_for(%__MODULE__{} = l, v, %{nice_min: min, nice_max: max}) do
    range = max - min
    l.grid_y + l.grid_h - (v - min) / range * l.grid_h
  end

  defp safe_log(v, _lb) when not is_number(v) or v <= 0, do: 0.0
  defp safe_log(v, lb), do: :math.log(v) / lb

  @doc "Pixel x for a data value (horizontal bar charts)."
  def x_for(%__MODULE__{} = l, v) do
    %{nice_min: min, nice_max: max} = l.scale
    range = max - min
    l.grid_x + (v - min) / range * l.grid_w
  end

  @doc "Pixel y of the zero baseline, clamped into the grid."
  def zero_y(%__MODULE__{} = l) do
    %{nice_min: min, nice_max: max} = l.scale
    y_for(l, 0 |> max(min) |> min(max))
  end

  @doc "Pixel x of the zero baseline for horizontal bars."
  def zero_x(%__MODULE__{} = l) do
    %{nice_min: min, nice_max: max} = l.scale
    x_for(l, 0 |> max(min) |> min(max))
  end

  @doc "Estimated rendered width of `text` at `font_size` (px)."
  def text_width(text, font_size) do
    String.length(to_string(text)) * font_size * 0.6
  end

  @doc """
  Estimated rendered height of one line of text at `font_size` (px) — the
  server-side stand-in for `getBBox().height`, which for common sans-serif
  faces lands near 1.15 em.
  """
  def text_height(font_size), do: font_size * 1.15

  @doc "Estimated distance from a text's baseline to the top of its box (px)."
  def text_ascent(font_size), do: font_size * 0.95

  @doc """
  Vertical space one row of x-axis labels occupies, accounting for
  `xaxis.labels.rotate`. Unrotated labels are one line tall; a rotated label's
  bounding box grows with the label's own width.
  """
  def rotated_label_height(cfg, categories, font_size) do
    rotate = cfg.xaxis.labels.rotate || 0

    if rotate == 0 do
      font_size
    else
      rad = abs(rotate) * :math.pi() / 180

      max_w =
        categories
        |> Enum.map(&text_width(to_string(&1), font_size))
        |> Enum.max(fn -> 0 end)

      max_w * :math.sin(rad) + font_size * :math.cos(rad)
    end
  end

  @doc "Formats a y-axis tick label according to the primary y-axis config."
  def format_y_label(cfg, v), do: format_y_label(cfg, cfg.yaxis, v, 0)

  @doc """
  Formats a y-axis tick label according to a specific axis map.

  `i` is the tick's index; formatters of arity 2 receive it as their second
  argument, matching ApexCharts' `(value, index)` signature (used to thin out
  labels, e.g. showing only every other tick).
  """
  def format_y_label(cfg, axis, v), do: format_y_label(cfg, axis, v, 0)

  def format_y_label(_cfg, axis, v, i) do
    cond do
      is_function(axis.formatter, 2) ->
        to_string(axis.formatter.(v, i))

      is_function(axis.formatter, 1) ->
        to_string(axis.formatter.(v))

      is_integer(axis.decimals_in_float) and is_float(v) ->
        :erlang.float_to_binary(v, decimals: axis.decimals_in_float)

      true ->
        SVG.fmt_value(v)
    end
  end

  @doc """
  Parses a cartesian data point into `{x, y, z}` for slot index `j`.

  Accepts a plain number (`y`; `x` defaults to the slot index — `j+1` for
  value x-axes, `j` for category), an `[x, y]` / `[x, y, z]` list, or a map
  with `:x`/`:y`/`:z` keys. Datetime x values are converted to unix ms.
  """
  def point(v, j, x_type) when is_number(v) do
    x = if x_type in [:numeric, :datetime], do: j + 1, else: j
    {x, v, nil}
  end

  def point([x, y], _j, x_type), do: {to_x(x, x_type), y, nil}
  def point([x, y, z | _], _j, x_type), do: {to_x(x, x_type), y, z}

  def point(%{} = m, j, x_type) do
    x = m[:x] || m["x"]

    x =
      if is_nil(x),
        do: if(x_type in [:numeric, :datetime], do: j + 1, else: j),
        else: to_x(x, x_type)

    {x, m[:y] || m["y"], m[:z] || m["z"]}
  end

  def point(_v, j, _x_type), do: {j, nil, nil}

  @doc "Converts an x value to a number (unix ms for datetime axes)."
  def to_x(v, :datetime), do: TimeScale.to_ms(v)
  def to_x(v, _type) when is_number(v), do: v
  def to_x(v, _type), do: TimeScale.to_ms(v)

  @doc "The effective x-axis kind for a config: `:category`, `:numeric` or `:datetime`."
  def x_type(cfg) do
    cond do
      cfg.xaxis.type == :datetime -> :datetime
      cfg.xaxis.type == :numeric -> :numeric
      cfg.chart.type in [:scatter, :bubble] -> :numeric
      true -> :category
    end
  end

  @doc "True when the x-axis is positioned by value rather than category slot."
  def value_x?(cfg), do: x_type(cfg) != :category

  @doc """
  Resolves a series' `data` into `[{j, x, y, z}]` tuples using the config's
  x-axis type. Plain-number data on a value x-axis takes its x from
  `xaxis.categories` when those are provided, else its slot index (`j+1`).
  """
  def series_points(cfg, data) do
    xt = x_type(cfg)
    cats = cfg.xaxis.categories

    data
    |> Enum.with_index()
    |> Enum.map(fn {v, j} ->
      {x, y, z} = point(v, j, xt)

      x =
        if is_number(v) and cats != [] and xt in [:numeric, :datetime] do
          to_x(Enum.at(cats, j), xt)
        else
          x
        end

      {j, x, y, z}
    end)
  end

  @doc """
  Index of the y-axis that a series binds to. Matches `series_name` first
  (ApexCharts `seriesName`), then falls back to the series' own position,
  then axis 0.
  """
  def axis_index_for(y_axes, s) do
    named =
      Enum.find_index(y_axes, fn a -> a.series_name && to_string(a.series_name) == s.name end)

    cond do
      is_integer(named) -> named
      s.index < length(y_axes) -> s.index
      true -> 0
    end
  end

  @doc "The scale bound to a given series (for multiple y-axes)."
  def scale_for_series(%__MODULE__{scales: scales} = l, s) do
    Enum.at(scales, axis_index_for(l.y_axes, s), l.scale)
  end

  defp dim(v, _default) when is_number(v), do: v
  defp dim(_, default), do: default
end
