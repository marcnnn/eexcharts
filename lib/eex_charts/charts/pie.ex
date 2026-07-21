defmodule EexCharts.Charts.Pie do
  @moduledoc """
  Pie / donut rendering, ported from ApexCharts `src/charts/Pie.js`.

  The chart fits a `min(width, height)` square; the outer radius is
  `size / 2.05 - stroke_width` (ApexCharts' constant). Slice angles are
  proportional shares of `end_angle - start_angle`; a donut cuts an inner
  circle at `donut.size%` of the outer radius. Slice labels sit at the
  mid-angle, at `radius / 1.25` for pies and the ring midpoint for donuts.
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Legend}

  @doc """
  Computes slice geometry. Returns `%{cx, cy, r, donut_r, slices}` where each
  slice is `%{index, label, value, pct, angle, start_angle, color}`.

  `opts[:indices]` supplies each value's original series index (so colors and
  event payloads stay stable when slices are hidden via the legend).
  """
  def geometry(cfg, values, labels, box_w, box_h, opts \\ []) do
    indices = opts[:indices] || Enum.to_list(0..max(length(values) - 1, 0))
    pie_cfg = cfg.plot_options.pie
    stroke_w = cfg.stroke.width

    size = min(box_w, box_h)
    cx = box_w / 2 + pie_cfg.offset_x
    cy = box_h / 2 + pie_cfg.offset_y
    r = (size / 2.05 - stroke_w) * pie_cfg.custom_scale

    donut_r =
      if cfg.chart.type == :donut do
        max(r * pct(pie_cfg.donut.size) / 100, 0)
      else
        0
      end

    full_angle = abs(pie_cfg.end_angle - pie_cfg.start_angle)
    total = values |> Enum.map(&max(&1, 0)) |> Enum.sum()

    {slices, _} =
      values
      |> Enum.with_index()
      |> Enum.map_reduce(pie_cfg.start_angle, fn {v, pos}, start ->
        v = max(v, 0)
        angle = if total > 0, do: full_angle * v / total, else: 0
        index = Enum.at(indices, pos, pos)

        slice = %{
          index: index,
          label: Enum.at(labels, pos) || "series-#{index + 1}",
          value: v,
          pct: if(total > 0, do: 100 * v / total, else: 0),
          angle: angle,
          start_angle: start,
          color: Config.color_at(cfg, index)
        }

        {slice, start + angle}
      end)

    %{cx: cx, cy: cy, r: r, donut_r: donut_r, full_angle: full_angle, slices: slices}
  end

  @doc "Renders slices, slice labels and donut center labels."
  def render(cfg, %{} = geo, opts \\ []) do
    on_click = opts[:on_click]

    slices =
      geo.slices
      |> Enum.reject(&(&1.angle <= 0))
      |> Enum.map(fn s ->
        attrs = %{
          class: "eexcharts-slice",
          data_j: s.index,
          d: slice_path(geo, s),
          fill: s.color,
          fill_opacity: cfg.fill.opacity,
          stroke: pie_stroke(cfg),
          stroke_width: cfg.stroke.width,
          stroke_linejoin: "round"
        }

        attrs =
          if on_click do
            Map.merge(attrs, %{
              "phx-click" => on_click,
              "phx-value-index" => s.index,
              cursor: "pointer"
            })
          else
            attrs
          end

        el("path", attrs)
      end)

    [
      donut_background(cfg, geo),
      el("g", %{class: "eexcharts-pie-series"}, slices),
      slice_labels(cfg, geo),
      donut_center_labels(cfg, geo)
    ]
  end

  # Outer arc clockwise, then either wedge to center (pie) or inner arc
  # back (donut). Angle 0 points up; clamped just under a full turn so a
  # 100% slice still renders.
  defp slice_path(geo, s) do
    angle = min(s.angle, geo.full_angle - 0.01)
    end_angle = s.start_angle + angle
    large_arc = if angle > 180, do: 1, else: 0

    {x1, y1} = polar(geo.cx, geo.cy, geo.r, s.start_angle)
    {x2, y2} = polar(geo.cx, geo.cy, geo.r, end_angle)

    outer = [move(x1, y1), arc(geo.r, geo.r, 0, large_arc, 1, x2, y2)]

    if geo.donut_r > 0 do
      {ix1, iy1} = polar(geo.cx, geo.cy, geo.donut_r, end_angle)
      {ix2, iy2} = polar(geo.cx, geo.cy, geo.donut_r, s.start_angle)

      [outer, line(ix1, iy1), arc(geo.donut_r, geo.donut_r, 0, large_arc, 0, ix2, iy2), " Z"]
    else
      [outer, line(geo.cx, geo.cy), " Z"]
    end
  end

  defp donut_background(cfg, geo) do
    bg = cfg.plot_options.pie.donut.background

    if geo.donut_r > 0 and bg not in [nil, "transparent"] do
      el("circle", %{cx: geo.cx, cy: geo.cy, r: geo.donut_r, fill: bg})
    else
      []
    end
  end

  defp slice_labels(cfg, geo) do
    dl = cfg.data_labels
    pie_cfg = cfg.plot_options.pie

    if dl.enabled do
      label_r =
        if geo.donut_r > 0 do
          (geo.r + geo.donut_r) / 2 + pie_cfg.data_labels.offset
        else
          geo.r / 1.25 + pie_cfg.data_labels.offset
        end

      labels =
        geo.slices
        |> Enum.filter(&(&1.angle >= pie_cfg.data_labels.min_angle_to_show_label))
        |> Enum.map(fn s ->
          mid = s.start_angle + s.angle / 2
          {x, y} = polar(geo.cx, geo.cy, label_r, mid)

          el(
            "text",
            %{
              x: x,
              y: y,
              text_anchor: "middle",
              dominant_baseline: "central",
              fill: label_color(dl, s.index),
              font_size: dl.style.font_size,
              font_weight: dl.style.font_weight,
              class: "eexcharts-datalabel"
            },
            esc(data_label_text(cfg, s))
          )
        end)

      el("g", %{class: "eexcharts-pie-labels"}, labels)
    else
      []
    end
  end

  defp data_label_text(cfg, s) do
    case cfg.data_labels.formatter do
      :percent -> format_pct(s.pct)
      f when is_function(f, 1) -> to_string(f.(s.value))
      f when is_function(f, 2) -> to_string(f.(s.value, s))
      _ -> fmt_value(s.value)
    end
  end

  defp format_pct(pct) do
    rounded = Float.round(pct * 1.0, 1)

    if rounded == trunc(rounded) do
      "#{trunc(rounded)}%"
    else
      "#{rounded}%"
    end
  end

  defp label_color(dl, i) do
    case dl.style.colors do
      nil -> "#fff"
      colors -> Enum.at(colors, rem(i, length(colors)))
    end
  end

  defp donut_center_labels(cfg, geo) do
    labels_cfg = cfg.plot_options.pie.donut.labels

    if geo.donut_r > 0 and labels_cfg.show do
      total = geo.slices |> Enum.map(& &1.value) |> Enum.sum()
      fore = cfg.chart.fore_color

      {name, value} =
        if labels_cfg.total.show do
          formatted =
            case labels_cfg.total.formatter do
              f when is_function(f, 1) -> to_string(f.(total))
              _ -> fmt_value(total)
            end

          {labels_cfg.total.label, formatted}
        else
          first = List.first(geo.slices)
          {first.label, fmt_value(first.value)}
        end

      name_el =
        if labels_cfg.name.show do
          el(
            "text",
            %{
              x: geo.cx,
              y: geo.cy + labels_cfg.name.offset_y,
              text_anchor: "middle",
              fill: labels_cfg.name.color || fore,
              font_size: labels_cfg.name.font_size,
              font_weight: labels_cfg.name.font_weight
            },
            esc(name)
          )
        else
          []
        end

      value_el =
        if labels_cfg.value.show do
          formatted =
            case labels_cfg.value.formatter do
              f when is_function(f, 1) -> to_string(f.(value))
              _ -> value
            end

          el(
            "text",
            %{
              x: geo.cx,
              y: geo.cy + labels_cfg.value.offset_y + 6,
              text_anchor: "middle",
              fill: labels_cfg.value.color || fore,
              font_size: labels_cfg.value.font_size,
              font_weight: labels_cfg.value.font_weight
            },
            esc(formatted)
          )
        else
          []
        end

      el("g", %{class: "eexcharts-donut-labels"}, [name_el, value_el])
    else
      []
    end
  end

  defp pie_stroke(cfg) do
    case cfg.stroke.colors do
      [c | _] -> c
      c when is_binary(c) -> c
      _ -> "#fff"
    end
  end

  defp polar(cx, cy, r, deg) do
    rad = :math.pi() * (deg - 90) / 180
    {cx + r * :math.cos(rad), cy + r * :math.sin(rad)}
  end

  defp pct(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> 65
    end
  end

  defp pct(value) when is_number(value), do: value

  @doc "Measures the legend for a pie chart (labels are the legend items)."
  def measure_legend(cfg, labels, w, h), do: Legend.measure(cfg, labels, w, h)
end
