defmodule EexCharts.Style.ChartJS do
  @moduledoc """
  The look of [Chart.js](https://www.chartjs.org) v4 with its `Colors` plugin:
  translucent fills under solid series-colored borders, small point markers,
  thin grey grid lines on both axes, `#666` 12px text, and the wide 40x12
  legend boxes above the chart.

  Values are Chart.js' own defaults (`defaults.font`, `elements.*`, the scale
  grid, `plugins.legend.labels`, `plugins.colors`), translated onto the
  ApexCharts option tree. Layout algorithms (nice scale, gutters, legend
  wrapping) stay ApexCharts'; only the styling changes. Chart types Chart.js
  does not have (heatmap, treemap, candlestick…) pick up the shared chrome
  and palette and keep their ApexCharts mark styling.
  """
  @behaviour EexCharts.Style

  # `plugins.colors` BORDER_COLORS, in its order. The plugin pairs each with a
  # 50% alpha background; we draw that as the same color at fill-opacity 0.5.
  @palette ["#36A2EB", "#FF6384", "#FF9F40", "#FFCD56", "#4BC0C0", "#9966FF", "#C9CBCF"]
  @translucent 0.5

  # `defaults.color` and `defaults.borderColor`.
  @text "#666"
  @line "rgba(0,0,0,0.1)"

  @doc "The `Colors` plugin palette."
  def palette, do: @palette

  @impl true
  def defaults(type), do: EexCharts.Config.deep_merge(common(), for_type(type))

  defp common do
    %{
      chart: %{font_family: "Helvetica Neue, Helvetica, Arial, sans-serif", fore_color: @text},
      theme: %{palette: :chartjs},
      title: %{align: :center, style: %{font_size: 12, font_weight: 700}},
      grid: %{
        border_color: @line,
        xaxis_lines: true,
        yaxis_lines: true
      },
      xaxis: %{
        title: %{style: %{font_weight: 400}},
        axis_border: %{color: @line},
        # `grid.tickLength`: Chart.js ticks are the grid lines run past the axis.
        axis_ticks: %{color: @line, height: 8}
      },
      yaxis: %{
        title: %{style: %{font_size: 12, font_weight: 400}},
        labels: %{style: %{font_size: 12}}
      },
      legend: %{
        position: :top,
        # `labels.boxWidth` 40, `boxHeight` = font size, `padding` 10.
        markers: %{shape: :square, width: 40, height: 12, radius: 0, stroke_color: nil},
        item_margin: %{horizontal: 5, vertical: 5}
      },
      tooltip: %{theme: :dark}
    }
  end

  # `elements.line` + `elements.point`: 3px straight lines, radius-3 points
  # with a translucent body and a 1px solid ring, radius 4 on hover.
  @points %{
    size: 3,
    fill_opacity: @translucent,
    stroke_colors: nil,
    stroke_width: 1,
    stroke_opacity: 1,
    hover: %{size: 4}
  }

  defp for_type(:line) do
    %{
      stroke: %{width: 3, curve: :straight},
      markers: @points,
      legend: %{markers: %{fill_opacity: @translucent, stroke_width: 3}}
    }
  end

  # A line dataset with `fill: 'origin'`: flat translucent fill, no gradient.
  defp for_type(:area) do
    for_type(:line)
    |> Map.put(:fill, %{type: :solid, opacity: @translucent})
  end

  # `elements.bar` has no border by default (`borderWidth: 0`); the stroke is
  # still series-colored, so `stroke: %{width: 1}` gives the bordered look.
  # `categoryPercentage` 0.8 x `barPercentage` 0.9 = 72% of the category.
  defp for_type(:bar) do
    %{
      data_labels: %{enabled: false},
      fill: %{opacity: @translucent},
      stroke: %{width: 0},
      plot_options: %{bar: %{column_width: "72%", bar_height: "72%"}},
      legend: %{markers: %{fill_opacity: @translucent, stroke_width: 0}}
    }
  end

  # `elements.arc`: 2px white borders between translucent slices; the
  # doughnut `cutout` is 50%.
  defp for_type(pie) when pie in [:pie, :donut] do
    %{
      data_labels: %{enabled: false},
      fill: %{opacity: @translucent},
      plot_options: %{pie: %{donut: %{size: "50%"}}},
      legend: %{
        position: :top,
        markers: %{fill_opacity: @translucent, stroke_width: 2, stroke_color: "#fff"}
      }
    }
  end

  defp for_type(:polar_area) do
    %{
      data_labels: %{enabled: false},
      fill: %{opacity: @translucent},
      stroke: %{width: 2},
      # The polar area's radial scale draws rings but hides `angleLines`.
      plot_options: %{
        polar_area: %{rings: %{stroke_color: @line}, spokes: %{stroke_width: 0}}
      },
      legend: %{
        position: :top,
        markers: %{fill_opacity: @translucent, stroke_width: 2, stroke_color: "#fff"}
      }
    }
  end

  # Radar datasets fill to the centre (`fill: 'start'`).
  defp for_type(:radar) do
    %{
      stroke: %{width: 3},
      fill: %{opacity: @translucent},
      markers: @points,
      plot_options: %{
        radar: %{polygons: %{stroke_colors: @line, connector_colors: @line}}
      },
      xaxis: %{labels: %{style: %{colors: [@text], font_size: 12}}},
      legend: %{markers: %{fill_opacity: @translucent, stroke_width: 3}}
    }
  end

  defp for_type(:scatter) do
    %{
      fill: %{opacity: @translucent},
      markers: Map.merge(@points, %{hover: %{size: nil, size_offset: 1}}),
      legend: %{markers: %{fill_opacity: @translucent, stroke_width: 1}}
    }
  end

  defp for_type(:bubble) do
    %{
      fill: %{opacity: @translucent},
      markers: %{stroke_colors: nil, stroke_width: 1, stroke_opacity: 1},
      legend: %{markers: %{fill_opacity: @translucent, stroke_width: 1}}
    }
  end

  defp for_type(_), do: %{}
end
