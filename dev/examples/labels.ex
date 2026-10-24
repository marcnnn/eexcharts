defmodule Dev.ChartExamples.Labels do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  def examples do
    [
      %{
        id: "lb1",
        title: "Annotation dash patterns and line caps",
        group: :labels,
        type: :line,
        series: [%{name: "Throughput", data: [42, 48, 55, 51, 63, 70, 66, 74, 81, 77]}],
        categories: ~w(W1 W2 W3 W4 W5 W6 W7 W8 W9 W10),
        options: %{
          stroke: %{width: 3},
          annotations: %{
            yaxis: [
              %{
                y: 80,
                border_color: "#FF4560",
                border_width: 2,
                stroke_dash_array: "8 4 2 4",
                label: %{text: "dash-dot 8 4 2 4", border_color: "#FF4560"}
              },
              %{
                y: 60,
                border_color: "#775DD0",
                border_width: 4,
                stroke_dash_array: [0, 9],
                stroke_linecap: :round,
                label: %{text: "round caps, [0, 9]", border_color: "#775DD0"}
              },
              %{
                y: 45,
                border_color: "#00E396",
                border_width: 4,
                stroke_dash_array: 10,
                stroke_linecap: :square,
                label: %{
                  text: "square caps, 10",
                  border_color: "#00E396",
                  position: :left,
                  text_anchor: :start
                }
              }
            ],
            xaxis: [
              %{
                x: "W6",
                x2: "W8",
                fill_color: "#FEB019",
                opacity: 0.15,
                border_color: "#FEB019",
                border_width: 2,
                stroke_dash_array: [12, 4],
                label: %{text: "release window", border_color: "#FEB019"}
              }
            ]
          }
        }
      },
      %{
        id: "lb2",
        title: "Data labels: balanced overlap hiding",
        group: :labels,
        type: :line,
        series: [
          %{name: "North", data: [31, 34, 36, 35, 40, 43, 41, 46, 48, 47, 52, 55, 54, 58]},
          %{name: "South", data: [29, 35, 34, 37, 38, 44, 43, 45, 50, 45, 53, 54, 56, 57]}
        ],
        categories: Enum.map(1..14, &"D#{&1}"),
        width: 640,
        height: 340,
        options: %{
          data_labels: %{enabled: true, hide_overlapping: true},
          markers: %{size: 4},
          title: %{text: "Overlapping labels hidden, alternating between series"}
        }
      },
      %{
        id: "lb3",
        title: "Horizontal bars: crowded category labels thinned",
        group: :labels,
        type: :bar,
        series: [
          %{
            name: "Score",
            data: Enum.map(1..48, fn i -> 20 + rem(i * 37, 61) end)
          }
        ],
        categories: Enum.map(1..48, &"Team #{&1}"),
        height: 360,
        options: %{
          plot_options: %{bar: %{horizontal: true}},
          data_labels: %{enabled: false},
          title: %{text: "48 categories in 360px: every 3rd label kept"}
        }
      },
      %{
        id: "lb4",
        title: "Data labels: per-point offset functions",
        group: :labels,
        type: :line,
        series: [%{name: "Temperature", data: [12, 18, 9, 21, 15, 26, 11, 19, 14]}],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun Mon Tue),
        options: %{
          markers: %{size: 5},
          stroke: %{width: 3},
          data_labels: %{
            enabled: true,
            # Valleys get their label below the point, peaks keep it above.
            offset_y: &__MODULE__.valley_offset/2
          }
        }
      },
      %{
        id: "lb5",
        title: "Logarithmic y-axis with values below 1",
        group: :labels,
        type: :line,
        series: [
          %{name: "Concentration", data: [0.004, 0.012, 0.05, 0.3, 1.8, 6.5, 24, 90]},
          %{
            name: "Detection limit",
            data: [0.002, 0.002, 0.002, 0.002, 0.002, 0.002, 0.002, 0.002]
          }
        ],
        categories: ~w(t0 t1 t2 t3 t4 t5 t6 t7),
        options: %{
          stroke: %{width: 3, dash_array: [0, 5]},
          markers: %{size: 4},
          yaxis: %{logarithmic: true, log_base: 10}
        }
      },
      %{
        id: "lb6",
        title: "Point annotations with hover tooltips",
        group: :labels,
        type: :line,
        series: [%{name: "Visitors", data: [120, 132, 101, 134, 290, 230, 210, 182, 191, 234]}],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun Mon Tue Wed),
        options: %{
          stroke: %{width: 3},
          annotations: %{
            points: [
              %{
                x: "Fri",
                y: 290,
                marker: %{size: 6, fill_color: "#FF4560", stroke_color: "#fff"},
                label: %{text: "Launch"},
                tooltip: "Product launch: newsletter + social campaign"
              },
              %{
                x: 2,
                y: 101,
                marker: %{size: 6, fill_color: "#775DD0", stroke_color: "#fff"},
                label: %{text: "Outage"},
                tooltip: "API outage, 2h 14m"
              }
            ]
          }
        }
      }
    ]
  end

  @lb4_data [12, 18, 9, 21, 15, 26, 11, 19, 14]

  @doc false
  def valley_offset(v, %{data_point_index: j}) do
    prev = Enum.at(@lb4_data, j - 1)
    next = Enum.at(@lb4_data, j + 1)
    if (j == 0 or v < prev) and (next == nil or v < next), do: 26, else: 0
  end
end
