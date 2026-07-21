defmodule EexCharts.Layout do
  @moduledoc """
  Computes the cartesian chart geometry: the plot ("grid") rectangle inside
  the SVG after reserving space for title, axis labels and legend, plus the
  value scale and coordinate mapping.

  ApexCharts measures rendered DOM text; server-side we estimate text extents
  from character counts (`text_width/2`).
  """

  alias EexCharts.{Legend, Scale, SVG}

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
            legend: nil,
            title_h: 0

  @type t :: %__MODULE__{}

  @doc """
  Builds the layout for a cartesian chart.

    * `names` — series names (for legend sizing)
    * `n` — number of data points / categories
    * `{y_min, y_max}` — raw value range from the data
  """
  def build(cfg, names, n, {y_min, y_max}) do
    w = dim(cfg.chart.width, 600)
    h = dim(cfg.chart.height, 350)
    horizontal = get_in(cfg, [:plot_options, :bar, :horizontal]) == true && cfg.chart.type == :bar
    pad = cfg.grid.padding

    title_h = if cfg.title.text, do: cfg.title.style.font_size + cfg.title.margin + 4, else: 0
    legend = Legend.measure(cfg, names, w, h)

    scale =
      Scale.nice_scale(y_min, y_max,
        min: cfg.yaxis.min,
        max: cfg.yaxis.max,
        tick_amount: cfg.yaxis.tick_amount,
        step_size: cfg.yaxis.step_size,
        svg_height: if(horizontal, do: w, else: h)
      )

    value_labels = Enum.map(scale.ticks, &format_y_label(cfg, &1))

    y_font = cfg.yaxis.labels.style.font_size
    x_font = cfg.xaxis.labels.style.font_size

    categories = cfg.xaxis.categories

    # Left gutter: category labels when horizontal, value labels otherwise.
    left_labels = if horizontal, do: Enum.map(categories, &to_string/1), else: value_labels

    left_label_w =
      if cfg.yaxis.labels.show and left_labels != [] do
        left_labels
        |> Enum.map(&text_width(&1, y_font))
        |> Enum.max()
        |> max(cfg.yaxis.labels.min_width)
        |> min(cfg.yaxis.labels.max_width)
      else
        0
      end

    y_title_w = if cfg.yaxis.title.text, do: cfg.yaxis.title.style.font_size + 10, else: 0

    x_label_h =
      if cfg.xaxis.labels.show do
        tick_h = if cfg.xaxis.axis_ticks.show, do: cfg.xaxis.axis_ticks.height, else: 0
        tick_h + x_font + 12
      else
        4
      end

    grid_x = pad.left + y_title_w + left_label_w + if(left_label_w > 0, do: 10, else: 0)
    grid_y = pad.top + title_h + 12
    right = pad.right + if(legend.position == :right, do: legend.w, else: 0)
    bottom_legend_h = if legend.position in [:bottom, :top], do: legend.h, else: 0

    {grid_y, bottom} =
      if legend.position == :top do
        {grid_y + bottom_legend_h, pad.bottom + x_label_h}
      else
        {grid_y, pad.bottom + x_label_h + bottom_legend_h}
      end

    %__MODULE__{
      w: w,
      h: h,
      grid_x: grid_x,
      grid_y: grid_y,
      grid_w: max(w - grid_x - right, 10),
      grid_h: max(h - grid_y - bottom, 10),
      n: max(n, 1),
      tick_placement: cfg.xaxis.tick_placement,
      horizontal: horizontal,
      scale: scale,
      legend: legend,
      title_h: title_h
    }
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

  @doc "Pixel y for a data value (vertical charts)."
  def y_for(%__MODULE__{} = l, v) do
    %{nice_min: min, nice_max: max} = l.scale
    range = max - min
    l.grid_y + l.grid_h - (v - min) / range * l.grid_h
  end

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

  @doc "Formats a y-axis tick label according to the config."
  def format_y_label(cfg, v) do
    cond do
      is_function(cfg.yaxis.formatter, 1) ->
        to_string(cfg.yaxis.formatter.(v))

      is_integer(cfg.yaxis.decimals_in_float) and is_float(v) ->
        :erlang.float_to_binary(v, decimals: cfg.yaxis.decimals_in_float)

      true ->
        SVG.fmt_value(v)
    end
  end

  defp dim(v, _default) when is_number(v), do: v
  defp dim(_, default), do: default
end
