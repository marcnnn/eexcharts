defmodule Dev.ChartExamples.Unit do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  def examples do
    [
      %{
        id: "un1",
        title: "Unit grid (1 mark = 10 respondents)",
        group: :unit,
        type: :unit,
        series: [420, 310, 180, 90],
        labels: ["North", "South", "East", "West"],
        options: %{
          title: %{text: "Survey respondents by region"},
          plot_options: %{unit: %{per_unit: 10, shape: :rounded_square}}
        }
      },
      %{
        id: "un2",
        title: "Unit grid, column fill, circles",
        group: :unit,
        type: :unit,
        series: [
          %{name: "Completed", data: 23},
          %{name: "In progress", data: 9},
          %{name: "Blocked", data: 4}
        ],
        options: %{
          plot_options: %{unit: %{shape: :circle, rows: 4, fill_order: :column, gap: 4}}
        }
      },
      %{
        id: "un3",
        title: "Waffle (10 x 10, percent of total)",
        group: :unit,
        type: :waffle,
        series: [
          %{
            name: "Energy mix",
            data: [
              %{x: "Renewables", y: 46.3},
              %{x: "Gas", y: 31.9},
              %{x: "Nuclear", y: 13.5},
              %{x: "Coal", y: 8.3}
            ]
          }
        ],
        width: 520,
        height: 380,
        options: %{legend: %{position: :right}}
      },
      %{
        id: "un4",
        title: "Parliament (hemicycle)",
        group: :unit,
        type: :unit,
        series: [42, 115, 23, 67, 98, 36, 19],
        labels: [
          "Left",
          "Social Democrats",
          "Greens",
          "Liberals",
          "Conservatives",
          "Regionalists",
          "Independents"
        ],
        height: 380,
        options: %{
          title: %{text: "Seat distribution (400 seats)"},
          colors: ["#C0392B", "#E74C3C", "#27AE60", "#F1C40F", "#2C3E50", "#8E44AD", "#95A5A6"],
          plot_options: %{unit: %{layout: :parliament, shape: :circle}}
        }
      },
      %{
        id: "un5",
        title: "Beeswarm (numeric x-axis)",
        group: :unit,
        type: :unit,
        series: [
          %{name: "Team A", data: Enum.map(0..44, &swarm_value(&1, 52, 9))},
          %{name: "Team B", data: Enum.map(0..44, &swarm_value(&1 + 7, 68, 11))}
        ],
        options: %{
          title: %{text: "Response times (ms)"},
          xaxis: %{title: %{text: "milliseconds"}},
          plot_options: %{unit: %{layout: :beeswarm, size: 9, gap: 1}}
        }
      },
      %{
        id: "un6",
        title: "Waffle with circles, column fill",
        group: :unit,
        type: :waffle,
        series: [57, 28, 15],
        labels: ["Agree", "Neutral", "Disagree"],
        width: 420,
        height: 400,
        options: %{plot_options: %{unit: %{shape: :circle, fill_order: :column, gap: 3}}}
      }
    ]
  end

  # Deterministic, roughly bell-shaped spread: a sum of three sines folded
  # around `mid` (no randomness, so the goldens stay stable).
  defp swarm_value(i, mid, spread) do
    t = :math.sin(i * 1.7) + :math.sin(i * 0.61 + 1.3) + :math.sin(i * 2.9 + 0.4)
    Float.round(mid + spread * t / 1.6, 1)
  end
end
