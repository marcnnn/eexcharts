defmodule EexCharts.Legend do
  @moduledoc """
  Legend measurement and SVG rendering (bottom, top or right positions).
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout}

  @marker_gap 4

  # ApexCharts' legend wrapper is `padding: 0 10px`.
  @html_padding_x 10

  defstruct show: false, position: :bottom, w: 0, h: 0, rows: []

  # Marker box size (diameter / square edge). ApexCharts sizes legend markers
  # by radius, so the drawn box is twice `legend.markers.size`.
  defp marker_d(cfg), do: (cfg.legend.markers.size || 6) * 2

  @doc """
  Measures the legend box for the given series names within an SVG of
  `w` x `h`. Returns a `%Legend{}` with row layout for rendering.
  """
  def measure(cfg, names, w, _h) do
    show = cfg.legend.show and (length(names) > 1 or cfg.legend.show_for_single_series)

    if show do
      font = cfg.legend.font_size
      im = cfg.legend.item_margin
      marker_d = marker_d(cfg)
      row_h = max(font, marker_d) + 2 * im.vertical

      html? = cfg.legend.html

      items =
        Enum.with_index(names, fn name, i ->
          text = to_string(name)
          text_w = Layout.text_width(text, font, Layout.metrics(cfg, cfg.legend))

          # The HTML legend's item is `marker box + 1px gap + text`; the SVG
          # one uses its own marker gap.
          lead = if html?, do: marker_d + 2 + 1, else: marker_d + @marker_gap

          %{text: text, index: i, w: lead + text_w + 2 * im.horizontal}
        end)

      case cfg.legend.position do
        :right ->
          legend_w = items |> Enum.map(& &1.w) |> Enum.max() |> Kernel.+(15)

          %__MODULE__{
            show: true,
            position: :right,
            w: legend_w,
            h: row_h * length(items),
            rows: Enum.map(items, &[&1])
          }

        pos when pos in [:bottom, :top] ->
          # The HTML legend wraps inside its padding, so the usable width is
          # narrower than the box — and the wrap decision can hang on a pixel.
          avail = (cfg.legend.width || w) - if(html?, do: 2 * @html_padding_x, else: 0)
          rows = wrap_rows(items, avail)
          %__MODULE__{show: true, position: pos, w: w, h: row_h * length(rows) + 8, rows: rows}
      end
    else
      %__MODULE__{show: false, position: cfg.legend.position, w: 0, h: 0, rows: []}
    end
  end

  defp wrap_rows(items, max_w) do
    Enum.reduce(items, {[], [], 0}, fn item, {rows, row, used} ->
      if row != [] and used + item.w > max_w do
        {[Enum.reverse(row) | rows], [item], item.w}
      else
        {rows, [item | row], used + item.w}
      end
    end)
    |> then(fn {rows, row, _} -> Enum.reverse([Enum.reverse(row) | rows]) end)
  end

  @doc """
  Renders the legend into the SVG at its measured position.

  Options:

    * `:hidden` — `MapSet` of series indexes toggled off (items render dimmed)
    * `:on_click` — event name; items get `phx-click` with `phx-value-series`
  """
  def render(legend, cfg, layout, opts \\ [])

  def render(%__MODULE__{show: false}, _cfg, _layout, _opts), do: []

  def render(%__MODULE__{} = legend, %{legend: %{html: true}} = cfg, %Layout{} = l, opts) do
    render_html(legend, cfg, l, opts)
  end

  def render(%__MODULE__{} = legend, cfg, %Layout{} = l, opts) do
    hidden = opts[:hidden] || MapSet.new()
    on_click = opts[:on_click]
    font = cfg.legend.font_size
    im = cfg.legend.item_margin
    marker_d = marker_d(cfg)
    row_h = max(font, marker_d) + 2 * im.vertical
    fore = cfg.legend.labels.colors || cfg.chart.fore_color

    {x0, y0} =
      case legend.position do
        :bottom -> {0, l.h - legend.h + 4}
        :top -> {0, (l.grid_y - legend.h - 8 + l.title_h) |> max(l.title_h + 4)}
        :right -> {l.w - legend.w, l.grid_y + max((l.grid_h - legend.h) / 2, 0)}
      end

    # Measured against ApexCharts' legend placement.
    {x0, y0} = {x0 + cfg.legend.offset_x + 3, y0 + cfg.legend.offset_y - 2}

    rows =
      legend.rows
      |> Enum.with_index()
      |> Enum.map(fn {row, r} ->
        row_w = row |> Enum.map(& &1.w) |> Enum.sum()

        # `legend.width` is a box the items lay out inside, anchored at the
        # chart's left edge — that is where ApexCharts puts it, and the rows
        # centre within the box rather than across the whole chart.
        box_w = if legend.position == :right, do: l.w, else: cfg.legend.width || l.w

        start_x =
          case {legend.position, cfg.legend.horizontal_align} do
            {:right, _} -> x0
            {_, :left} -> x0 + l.grid_x
            {_, :right} -> x0 + box_w - row_w - 10
            _ -> x0 + (box_w - row_w) / 2
          end

        y = y0 + r * row_h + row_h / 2

        {items_io, _} =
          Enum.reduce(row, {[], start_x}, fn item, {acc, x} ->
            color =
              if cfg.legend.labels.use_series_colors,
                do: Config.color_at(cfg, item.index),
                else: fore

            marker_color = Config.color_at(cfg, item.index)

            stroke_w = cfg.legend.markers.stroke_width
            stroke_c = if stroke_w && stroke_w > 0, do: cfg.legend.markers.stroke_color

            shape = EexCharts.Marker.shape_for(cfg.legend.markers.shape, item.index)

            marker =
              case shape do
                :square ->
                  el("rect", %{
                    class: "eexcharts-legend-marker",
                    x: x + im.horizontal,
                    y: y - marker_d / 2,
                    width: marker_d,
                    height: marker_d,
                    rx: cfg.legend.markers.radius || 2,
                    fill: marker_color,
                    stroke: stroke_c,
                    stroke_width: if(stroke_c, do: stroke_w)
                  })

                other ->
                  EexCharts.Marker.render(
                    other,
                    x + im.horizontal + marker_d / 2,
                    y,
                    marker_d / 2,
                    %{
                      class: "eexcharts-legend-marker",
                      fill: marker_color,
                      stroke: stroke_c,
                      stroke_width: if(stroke_c, do: stroke_w)
                    }
                  )
              end

            text =
              el(
                "text",
                %{
                  class: "eexcharts-legend-text",
                  x: x + im.horizontal + marker_d + @marker_gap,
                  y: y,
                  fill: color,
                  font_family: cfg.legend.font_family,
                  font_size: font,
                  font_weight: cfg.legend.font_weight,
                  dominant_baseline: "central"
                },
                esc(item.text)
              )

            group_attrs = %{
              class: "eexcharts-legend-item",
              data_series: item.index,
              opacity: if(MapSet.member?(hidden, item.index), do: 0.4, else: nil)
            }

            group_attrs =
              if on_click do
                Map.merge(group_attrs, %{
                  "phx-click" => on_click,
                  "phx-value-series" => item.index,
                  cursor: "pointer"
                })
              else
                group_attrs
              end

            {[acc, el("g", group_attrs, [marker, text])], x + item.w}
          end)

        items_io
      end)

    el("g", %{class: "eexcharts-legend"}, rows)
  end

  # ── HTML legend ──────────────────────────────────────────────────────────────

  # ApexCharts' legend is an HTML flex overlay, which is why its item widths
  # and row pitch are exact where a metrics-estimated SVG legend is close: the
  # browser measures the real glyphs. We hand the browser the same job through
  # a `foreignObject`, which keeps the legend inside the SVG (no chart has to
  # thread a second render target through) while still laying out as HTML.
  #
  # The box only has to be big enough not to clip; every position inside it is
  # the browser's. `line-height: normal` matters — without it the host page's
  # line-height leaks in and the rows grow.
  defp render_html(%__MODULE__{} = legend, cfg, %Layout{} = l, opts) do
    hidden = opts[:hidden] || MapSet.new()
    on_click = opts[:on_click]
    im = cfg.legend.item_margin
    font = cfg.legend.font_size
    fore = cfg.legend.labels.colors || cfg.chart.fore_color

    marker_box = html_marker_box(cfg)
    item_h = max(ceil(font * 4 / 3), marker_box)
    row_h = item_h + 2 * im.vertical
    box_w = if legend.position == :right, do: legend.w, else: cfg.legend.width || l.w

    {x0, y0} =
      case legend.position do
        :bottom -> {0, l.h - legend.h + 4}
        :top -> {0, (l.grid_y - legend.h - 8 + l.title_h) |> max(l.title_h + 4)}
        :right -> {l.w - legend.w, l.grid_y + max((l.grid_h - legend.h) / 2, 0)}
      end

    {x0, y0} = {x0 + cfg.legend.offset_x + 3, y0 + cfg.legend.offset_y - 2}

    justify =
      case cfg.legend.horizontal_align do
        :left -> "flex-start"
        :right -> "flex-end"
        _ -> "center"
      end

    items =
      legend.rows
      |> Enum.concat()
      |> Enum.map(&html_item(&1, cfg, fore, marker_box, im, font, hidden, on_click))

    wrapper_style =
      "display:flex;flex-direction:row;flex-wrap:wrap;justify-content:#{justify};" <>
        "align-items:center;padding:0 #{@html_padding_x}px;margin:0;box-sizing:border-box;" <>
        "line-height:normal;height:100%;overflow:hidden;"

    el(
      "foreignObject",
      %{
        class: "eexcharts-legend eexcharts-legend--html",
        x: x0,
        y: y0,
        width: box_w,
        height: row_h * length(legend.rows)
      },
      el(
        "div",
        %{xmlns: "http://www.w3.org/1999/xhtml", class: "eexcharts-legend-inner", style: wrapper_style},
        items
      )
    )
  end

  # ApexCharts pads its marker box one pixel around the drawn shape.
  defp html_marker_box(cfg), do: marker_d(cfg) + 2

  defp html_item(item, cfg, fore, marker_box, im, font, hidden, on_click) do
    color = if cfg.legend.labels.use_series_colors, do: Config.color_at(cfg, item.index), else: fore
    marker_color = Config.color_at(cfg, item.index)
    stroke_w = cfg.legend.markers.stroke_width
    stroke_c = if stroke_w && stroke_w > 0, do: cfg.legend.markers.stroke_color
    hidden? = MapSet.member?(hidden, item.index)
    r = marker_d(cfg) / 2
    shape = EexCharts.Marker.shape_for(cfg.legend.markers.shape, item.index)

    marker_shape =
      case shape do
        :square ->
          el("rect", %{
            x: marker_box / 2 - r,
            y: marker_box / 2 - r,
            width: r * 2,
            height: r * 2,
            rx: cfg.legend.markers.radius || 2,
            fill: marker_color,
            stroke: stroke_c,
            stroke_width: if(stroke_c, do: stroke_w)
          })

        other ->
          EexCharts.Marker.render(other, marker_box / 2, marker_box / 2, r, %{
            fill: marker_color,
            stroke: stroke_c,
            stroke_width: if(stroke_c, do: stroke_w)
          })
      end

    marker =
      el(
        "span",
        %{
          class: "eexcharts-legend-marker",
          style:
            "display:flex;position:relative;width:#{fmt(marker_box)}px;height:#{fmt(marker_box)}px;" <>
              "margin:0 1px 0 0;flex:0 0 auto;"
        },
        el(
          "svg",
          %{width: marker_box, height: marker_box, xmlns: "http://www.w3.org/2000/svg"},
          marker_shape
        )
      )

    text =
      el(
        "span",
        %{
          class: "eexcharts-legend-text",
          style:
            "padding-left:15px;margin-left:-15px;color:#{color};font-size:#{fmt(font)}px;" <>
              "font-weight:#{cfg.legend.font_weight};" <>
              if(cfg.legend.font_family, do: "font-family:#{cfg.legend.font_family};", else: "")
        },
        esc(item.text)
      )

    attrs = %{
      class: "eexcharts-legend-item eexcharts-legend-series",
      data_series: item.index,
      style:
        "display:flex;align-items:center;margin:#{fmt(im.vertical)}px #{fmt(im.horizontal)}px;" <>
          if(on_click, do: "cursor:pointer;", else: "") <>
          if(hidden?, do: "opacity:0.4;", else: "")
    }

    attrs =
      if on_click,
        do: Map.merge(attrs, %{"phx-click" => on_click, "phx-value-series" => item.index}),
        else: attrs

    el("div", attrs, [marker, text])
  end
end
