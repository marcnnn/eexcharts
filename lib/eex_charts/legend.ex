defmodule EexCharts.Legend do
  @moduledoc """
  Legend measurement and SVG rendering (bottom, top or right positions).
  """

  import EexCharts.SVG

  alias EexCharts.{Config, Layout}

  @marker_gap 4

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

      items =
        Enum.with_index(names, fn name, i ->
          text = to_string(name)
          item_w =
            marker_d + @marker_gap + Layout.text_width(text, font, Layout.metrics(cfg)) +
              2 * im.horizontal
          %{text: text, index: i, w: item_w}
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
          rows = wrap_rows(items, cfg.legend.width || w)
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
        # Centred on the title band when there is a title, else at the top.
        :top -> {0, max((l.title_h - legend.h) / 2, 0) + 4}
        :right -> {l.w - legend.w, l.grid_y + max((l.grid_h - legend.h) / 2, 0)}
      end

    # Measured against ApexCharts' legend placement.
    {x0, y0} = {x0 + cfg.legend.offset_x + 3, y0 + cfg.legend.offset_y - 2}

    rows =
      legend.rows
      |> Enum.with_index()
      |> Enum.map(fn {row, r} ->
        row_w = row |> Enum.map(& &1.w) |> Enum.sum()

        start_x =
          case {legend.position, cfg.legend.horizontal_align} do
            {:right, _} -> x0
            {_, :left} -> x0 + l.grid_x
            {_, :right} -> x0 + l.w - row_w - 10
            _ -> x0 + (l.w - row_w) / 2
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
end
