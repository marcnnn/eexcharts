defmodule Dev.ChartExamples.WaterfallHorizontal do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  def examples do
    [
      %{
        id: "wh1",
        title: "Horizontal waterfall, outline decreases",
        group: :waterfall,
        type: :waterfall,
        series: [
          %{
            name: "Count",
            data: [
              %{x: "Start", y: 25, fill_color: "#261e14"},
              %{x: "Decrease", y: -12},
              %{x: "Increase", y: 5},
              %{x: "End", total: true}
            ]
          }
        ],
        options: %{
          chart: %{height: 260},
          plot_options: %{
            bar: %{horizontal: true, bar_height: "55%", border_radius: 2},
            waterfall: %{
              colors: %{increase: "#ff6105", decrease: :outline, total: "#261e14"}
            }
          }
        }
      },
      %{
        id: "wh2",
        title: "Horizontal waterfall, two series per category",
        group: :waterfall,
        type: :waterfall,
        series: [
          %{
            name: "Plan",
            data: [
              %{x: "Item 01", y: 40},
              %{x: "Item 02", y: -15},
              %{x: "Item 03", y: 20},
              %{x: "Item 04", y: -10},
              %{x: "End", total: true}
            ]
          },
          %{name: "Actual", data: [35, -20, 30, -5, %{total: true}], fill: %{type: :none}}
        ],
        options: %{
          title: %{text: "Plan (solid) and actual (outline)"},
          plot_options: %{bar: %{horizontal: true}},
          legend: %{show: false}
        }
      },
      %{
        id: "wh3",
        title: "Vertical waterfall, outline decreases",
        group: :waterfall,
        type: :waterfall,
        series: [
          %{
            name: "Count",
            data: [
              %{x: "Start", y: 60},
              %{x: "Item 01", y: -18},
              %{x: "Item 02", y: 12},
              %{x: "Item 03", y: -9},
              %{x: "Item 04", y: 15, fill_color: "#775DD0"},
              %{x: "End", total: true}
            ]
          }
        ],
        options: %{plot_options: %{waterfall: %{colors: %{decrease: :outline}}}}
      }
    ]
  end
end
