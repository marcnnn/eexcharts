defmodule Dev.ChartExamples.PointStyle do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  def examples do
    [
      %{
        id: "ps1",
        title: "Outline-only series next to a solid one",
        group: :bar,
        type: :bar,
        series: [
          %{name: "Series 1", data: [44, 55, 41, 64, 22]},
          %{name: "Series 2", data: [53, 32, 33, 52, 13], fill: %{type: :none}}
        ],
        categories: ["Group 1", "Group 2", "Group 3", "Group 4", "Group 5"],
        options: %{data_labels: %{enabled: true}}
      },
      %{
        id: "ps2",
        title: "Per-point fill_color",
        group: :bar,
        type: :bar,
        series: [
          %{
            name: "Series 1",
            data: [
              %{x: "Item 01", y: 32},
              %{x: "Item 02", y: 47},
              %{x: "Item 03", y: 18, fill_color: "#FF4560"},
              %{x: "Item 04", y: 52},
              %{x: "Item 05", y: 26, fill_color: "#FF4560"},
              %{x: "Item 06", y: 39}
            ]
          }
        ],
        categories: ["Item 01", "Item 02", "Item 03", "Item 04", "Item 05", "Item 06"]
      },
      %{
        id: "ps3",
        title: "Range bar with solid, outline and pattern points",
        group: :range_bar,
        type: :range_bar,
        series: [
          %{
            name: "Series 1",
            data: [
              %{x: "Row A", y: [2, 6]},
              %{x: "Row B", y: [4, 9], fill: %{type: :none}},
              %{
                x: "Row C",
                y: [1, 5],
                fill: %{type: :pattern, pattern: %{style: :slanted_lines}}
              },
              %{x: "Row D", y: [5, 11]},
              %{
                x: "Row E",
                y: [3, 8],
                fill_color: "#775DD0",
                fill: %{type: :pattern, pattern: %{style: :vertical_lines}}
              }
            ]
          }
        ],
        categories: ["Row A", "Row B", "Row C", "Row D", "Row E"],
        options: %{plot_options: %{bar: %{horizontal: true}}}
      },
      %{
        id: "ps4",
        title: "Dumbbell with flagged rows",
        group: :dumbbell,
        type: :dumbbell,
        series: [
          %{
            name: "Series 1",
            ends: ["Start", "End"],
            data: [
              %{x: "Row A", y: [24, 41]},
              %{x: "Row B", y: [18, 52], fill_color: "#FF4560"},
              %{x: "Row C", y: [31, 38]},
              %{x: "Row D", y: [12, 29], stroke_color: "#FF4560"},
              %{x: "Row E", y: [27, 46], fill: %{type: :none}}
            ]
          }
        ],
        options: %{plot_options: %{bar: %{horizontal: true}}}
      },
      %{
        id: "ps5",
        title: "Global pattern fill on bars",
        group: :bar,
        type: :bar,
        series: [
          %{name: "Series 1", data: [44, 55, 41, 64]},
          %{name: "Series 2", data: [53, 32, 33, 52]},
          %{name: "Series 3", data: [12, 17, 11, 9]}
        ],
        categories: ["Group 1", "Group 2", "Group 3", "Group 4"],
        options: %{
          chart: %{stacked: true},
          plot_options: %{bar: %{horizontal: true}},
          fill: %{
            type: :pattern,
            opacity: 1,
            pattern: %{
              style: [:circles, :slanted_lines, :vertical_lines],
              width: 9,
              height: 9,
              stroke_width: 1
            }
          },
          data_labels: %{enabled: true}
        }
      }
    ]
  end
end
