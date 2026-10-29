defmodule Dev.ChartExamples.EndLabels do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @faint 0.3

  def examples do
    [
      %{
        id: "el1",
        title: "End labels instead of a legend, faint background rows",
        group: :line,
        type: :line,
        series: [
          %{name: "Group 1", data: [59, 67, 74], end_label: "74 · +15"},
          %{name: "Group 2", data: [61, 63, 66.5], end_label: "66 · +5"},
          %{name: "Mean", data: [60, 65, 68], end_label: "68 mean"},
          %{name: "Row A", data: [62, 70, 77], opacity: @faint},
          %{name: "Row B", data: [58, 66, 75], opacity: @faint},
          %{name: "Row C", data: [55, 63, 71], opacity: @faint},
          %{name: "Row D", data: [64, 66, 65], opacity: @faint},
          %{name: "Row E", data: [60, 61, 63], opacity: @faint},
          %{name: "Row F", data: [57, 60, 59], opacity: @faint}
        ],
        categories: ["2024", "2025", "2026"],
        options: %{
          colors: [
            "#546E7A",
            "#F86624",
            "#A5978B",
            "#546E7A",
            "#546E7A",
            "#546E7A",
            "#F86624",
            "#F86624",
            "#F86624"
          ],
          stroke: %{width: [4, 4, 3, 1.5, 1.5, 1.5, 1.5, 1.5, 1.5], dash_array: [0, 0, 6]},
          markers: %{size: [4, 4, 4, 0, 0, 0, 0, 0, 0]},
          yaxis: %{min: 50, max: 80, tick_amount: 3},
          legend: %{show: false},
          end_labels: %{enabled: true}
        }
      },
      %{
        id: "el2",
        title: "Area end labels from the series names",
        group: :area,
        type: :area,
        series: [
          %{name: "Series 1", data: [31, 40, 28, 51, 42, 60], end_label: true},
          %{name: "Series 2", data: [11, 32, 45, 32, 34, 57], end_label: true},
          %{name: "Series 3", data: [20, 25, 30, 22, 35, 30], end_label: true}
        ],
        categories: ["Jan", "Feb", "Mar", "Apr", "May", "Jun"],
        options: %{legend: %{show: false}, end_labels: %{enabled: true}}
      }
    ]
  end
end
