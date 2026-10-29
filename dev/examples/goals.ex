defmodule Dev.ChartExamples.Goals do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  # {item, q1, median, q3, value}
  @rows [
    {"Item 01", 58, 68, 74, 35},
    {"Item 02", 38, 42, 53, 8},
    {"Item 03", 71, 77, 85, 63},
    {"Item 04", 70, 77, 91, 70},
    {"Item 05", 70, 76, 84, 92},
    {"Item 06", 82, 89, 93, 100},
    {"Item 07", 70, 82, 88, 85},
    {"Item 08", 73, 80, 84, 91}
  ]

  @warning "#FF4560"

  def examples do
    [
      %{
        id: "gl1",
        title: "Range band with a median line and a value dot",
        group: :range_bar,
        type: :range_bar,
        series: [%{name: "Reference", data: Enum.map(@rows, &band/1)}],
        categories: Enum.map(@rows, &elem(&1, 0)),
        options: %{
          colors: ["#008FFB"],
          plot_options: %{bar: %{horizontal: true, bar_height: "45%", border_radius: 4}},
          fill: %{opacity: 0.3},
          xaxis: %{min: 0, max: 100},
          legend: %{
            show: true,
            custom_legend_items: ["Band (q1-q3)", "Median", "Value", "Value below q1"],
            markers: %{fill_colors: ["#008FFB", "#a8a8a8", "#775DD0", @warning]}
          }
        }
      },
      %{
        id: "gl2",
        title: "Columns with target lines",
        group: :bar,
        type: :bar,
        series: [
          %{
            name: "Actual",
            data:
              Enum.map(
                [
                  {"Item 01", 1292, 1400},
                  {"Item 02", 4432, 5400},
                  {"Item 03", 5423, 5200},
                  {"Item 04", 6653, 6500},
                  {"Item 05", 8133, 6600},
                  {"Item 06", 7132, 7500}
                ],
                fn {x, y, goal} ->
                  %{
                    x: x,
                    y: y,
                    goals: [
                      %{name: "Expected", value: goal, stroke_height: 5, stroke_color: "#775DD0"}
                    ]
                  }
                end
              )
          }
        ],
        categories: ["Item 01", "Item 02", "Item 03", "Item 04", "Item 05", "Item 06"],
        options: %{
          colors: ["#00E396"],
          legend: %{
            show: true,
            custom_legend_items: ["Actual", "Expected"],
            markers: %{fill_colors: ["#00E396", "#775DD0"]}
          }
        }
      },
      %{
        id: "gl3",
        title: "Stacked bars with a dashed goal per row",
        group: :bar,
        type: :bar,
        series: [
          %{
            name: "Series 1",
            data:
              Enum.zip_with([[44, 55, 41, 37], [70, 80, 60, 75]], fn [y, goal] ->
                %{
                  y: y,
                  goals: [
                    %{
                      name: "Goal",
                      value: goal,
                      stroke_width: 3,
                      stroke_dash_array: 4,
                      stroke_line_cap: :round
                    }
                  ]
                }
              end)
          },
          %{name: "Series 2", data: [13, 23, 20, 8]},
          %{name: "Series 3", data: [11, 17, 15, 15]}
        ],
        categories: ["Row A", "Row B", "Row C", "Row D"],
        options: %{chart: %{stacked: true}, plot_options: %{bar: %{horizontal: true}}}
      },
      %{
        id: "gl4",
        title: "Grouped columns with line and dot goals",
        group: :bar,
        type: :bar,
        series: [
          %{
            name: "Series 1",
            data: [
              %{y: 31, goals: [%{name: "Plan", value: 40}]},
              %{y: 40, goals: [%{name: "Plan", value: 38}]},
              %{y: 28, goals: [%{name: "Plan", value: 35}]}
            ]
          },
          %{
            name: "Series 2",
            data: [
              %{y: 11, goals: [%{name: "Last year", value: 20, shape: :circle}]},
              %{y: 32, goals: [%{name: "Last year", value: 25, shape: :circle}]},
              %{y: 45, goals: [%{name: "Last year", value: 52, shape: :circle, size: 7}]}
            ]
          }
        ],
        categories: ["Group 1", "Group 2", "Group 3"]
      }
    ]
  end

  defp band({item, q1, median, q3, value}) do
    %{
      x: item,
      y: [q1, q3],
      goals: [
        %{name: "Median", value: median, stroke_width: 4, stroke_height: 9},
        %{
          name: "Value",
          value: value,
          shape: :circle,
          size: 6,
          stroke_color: if(value < q1, do: @warning, else: "#775DD0")
        }
      ]
    }
  end
end
