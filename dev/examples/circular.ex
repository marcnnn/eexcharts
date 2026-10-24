defmodule Dev.ChartExamples.Circular do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  def examples do
    [
      %{
        id: "ci1",
        title: "Gauge",
        group: :gauge,
        type: :gauge,
        series: [72],
        labels: ["Speed"],
        width: 420,
        height: 300,
        options: %{
          plot_options: %{
            gauge: %{
              max: 160,
              ticks: %{amount: 8, minor: %{amount: 3}}
            }
          }
        }
      },
      %{
        id: "ci2",
        title: "Gauge with bands",
        group: :gauge,
        type: :gauge,
        series: [%{name: "Engine load", data: [152]}],
        width: 420,
        height: 340,
        options: %{
          plot_options: %{
            gauge: %{
              start_angle: -120,
              end_angle: 120,
              max: 200,
              band_gap: 3,
              bands: [
                %{from: 0, to: 120, color: "#00E396"},
                %{from: 120, to: 170, color: "#FEB019"},
                %{from: 170, to: 200, color: "#FF4560"}
              ],
              ticks: %{amount: 10, minor: %{amount: 1}}
            }
          }
        }
      },
      %{
        id: "ci3",
        title: "Radial bar with targets",
        group: :gauge,
        type: :radial_bar,
        series: [
          %{name: "Sales", data: [76], targets: [85]},
          %{name: "Leads", data: [61]},
          %{name: "Renewals", data: [90]}
        ],
        width: 420,
        height: 340,
        options: %{
          legend: %{show: true},
          plot_options: %{radial_bar: %{targets: [nil, [55, %{value: 80, color: "#FF4560"}], 95]}}
        }
      },
      %{
        id: "ci4",
        title: "Pie with spacing and rounded corners",
        group: :pie,
        type: :pie,
        series: [44, 55, 13, 43, 22],
        labels: ~w(Team-A Team-B Team-C Team-D Team-E),
        width: 420,
        height: 320,
        options: %{plot_options: %{pie: %{spacing: 4, border_radius: 6}}}
      },
      %{
        id: "ci5",
        title: "Donut with spacing, rounded corners and a sliver",
        group: :pie,
        type: :donut,
        series: [44, 55, 41, 17, 1],
        labels: ~w(Apples Oranges Bananas Cherries Limes),
        width: 420,
        height: 320,
        options: %{
          plot_options: %{
            pie: %{
              spacing: 3,
              border_radius: 8,
              donut: %{labels: %{show: true, total: %{show: true}}}
            }
          }
        }
      },
      %{
        id: "ci6",
        title: "Polar area with spacing",
        group: :pie,
        type: :polar_area,
        series: [14, 23, 21, 17, 15, 10],
        labels: ~w(Rose-A Rose-B Rose-C Rose-D Rose-E Rose-F),
        width: 420,
        height: 340,
        options: %{plot_options: %{pie: %{spacing: 3, border_radius: 4}}}
      },
      %{
        id: "ci7",
        title: "Semi donut with spacing",
        group: :pie,
        type: :donut,
        series: [30, 25, 20, 15],
        labels: ~w(North East South West),
        width: 420,
        height: 260,
        options: %{
          plot_options: %{
            pie: %{start_angle: -90, end_angle: 90, spacing: 6, border_radius: 10}
          }
        }
      }
    ]
  end
end
