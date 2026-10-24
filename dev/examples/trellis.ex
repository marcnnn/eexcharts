defmodule Dev.ChartExamples.Trellis do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  def examples do
    [
      %{
        id: "tr1",
        title: "Trellis: one line panel per series (shared scales)",
        group: :trellis,
        type: :line,
        width: 760,
        height: 460,
        series: [
          %{name: "Berlin", data: [3, 4, 8, 13, 18, 21, 23, 23, 19, 13, 8, 4]},
          %{name: "Madrid", data: [10, 12, 15, 17, 21, 27, 31, 30, 26, 19, 13, 10]},
          %{name: "Oslo", data: [-2, -2, 2, 7, 13, 17, 19, 18, 13, 7, 2, -1]},
          %{name: "Rome", data: [12, 13, 16, 19, 23, 28, 31, 31, 27, 22, 16, 13]},
          %{name: "Dublin", data: [8, 9, 10, 12, 15, 17, 19, 19, 17, 14, 10, 8]},
          %{name: "Athens", data: [13, 14, 16, 20, 25, 30, 33, 33, 29, 24, 19, 15]}
        ],
        categories: @months,
        options: %{
          title: %{text: "Average daily high (°C)"},
          stroke: %{width: 2},
          trellis: %{by: :series, columns: 3}
        }
      },
      %{
        id: "tr2",
        title: "Trellis: area panels by group, last row part-filled",
        group: :trellis,
        type: :area,
        width: 760,
        height: 460,
        series: [
          %{name: "Web", group: "North", data: [31, 40, 28, 51, 42, 60, 70]},
          %{name: "Retail", group: "North", data: [11, 32, 45, 32, 34, 52, 41]},
          %{name: "Web", group: "South", data: [20, 25, 30, 41, 48, 55, 58]},
          %{name: "Retail", group: "South", data: [15, 18, 22, 26, 24, 30, 33]},
          %{name: "Web", group: "East", data: [44, 38, 36, 40, 52, 49, 61]},
          %{name: "Retail", group: "East", data: [22, 20, 25, 21, 28, 30, 27]},
          %{name: "Web", group: "West", data: [10, 18, 26, 34, 42, 50, 66]},
          %{name: "Retail", group: "West", data: [5, 9, 14, 20, 25, 28, 35]},
          %{name: "Partner", group: "Central", data: [12, 14, 13, 18, 20, 19, 24]}
        ],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun),
        options: %{
          title: %{text: "Orders by channel and region"},
          legend: %{position: :top},
          stroke: %{width: 2},
          data_labels: %{enabled: false},
          trellis: %{by: :group, columns: 3}
        }
      },
      %{
        id: "tr3",
        title: "Trellis: column panels with free y scales",
        group: :trellis,
        type: :bar,
        width: 680,
        height: 440,
        series: [
          %{name: "Visits", data: [1200, 1350, 1580, 1490, 1720, 1910]},
          %{name: "Sign-ups", data: [84, 96, 120, 101, 133, 150]},
          %{name: "Orders", data: [31, 36, 45, 39, 52, 61]},
          %{name: "Refunds", data: [3, 2, 5, 4, 2, 6]}
        ],
        categories: ~w(Jan Feb Mar Apr May Jun),
        options: %{
          data_labels: %{enabled: false},
          plot_options: %{bar: %{column_width: "60%"}},
          trellis: %{by: :series, columns: 2, shared_y: false}
        }
      },
      %{
        id: "tr4",
        title: "Trellis: scatter panels by group on a numeric x-axis",
        group: :trellis,
        type: :scatter,
        width: 720,
        height: 380,
        series: [
          %{name: "Setosa", group: "Short sepal", data: scatter(1, 4.4, 5.6, 2.9, 0.18)},
          %{name: "Versicolor", group: "Short sepal", data: scatter(2, 5.0, 5.9, 2.4, 0.22)},
          %{name: "Virginica", group: "Long sepal", data: scatter(3, 6.0, 7.6, 2.8, 0.2)},
          %{name: "Hybrid", group: "Long sepal", data: scatter(4, 5.9, 7.0, 3.2, 0.25)}
        ],
        options: %{
          xaxis: %{type: :numeric},
          markers: %{size: 5},
          title: %{text: "Sepal length vs width", align: :center},
          trellis: %{by: :group, columns: 2}
        }
      },
      %{
        id: "tr5",
        title: "Trellis: horizontal bars, legend on the right",
        group: :trellis,
        type: :bar,
        width: 720,
        height: 380,
        series: [
          %{name: "2022", data: [42, 35, 28, 19, 12]},
          %{name: "2023", data: [48, 33, 31, 22, 15]},
          %{name: "2024", data: [55, 30, 36, 24, 18]}
        ],
        categories: ["Product A", "Product B", "Product C", "Services", "Other"],
        options: %{
          plot_options: %{bar: %{horizontal: true}},
          data_labels: %{enabled: false},
          legend: %{position: :right},
          trellis: %{by: :series, columns: 3}
        }
      }
    ]
  end

  # Deterministic point cloud: x sweeps the range, y follows a slanted wave.
  defp scatter(seed, x0, x1, y0, slope) do
    for i <- 0..11 do
      x = x0 + (x1 - x0) * i / 11
      y = y0 + slope * (x - x0) + 0.15 * :math.sin(i * 1.7 + seed)
      [Float.round(x, 2), Float.round(y, 2)]
    end
  end
end
