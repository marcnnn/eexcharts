defmodule Dev.ChartExamples.BarFamily do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  def examples do
    [
      %{
        id: "bf1",
        title: "Funnel",
        group: :funnel,
        type: :funnel,
        series: [%{name: "Visitors", data: [1380, 1100, 990, 880, 740, 548]}],
        categories: ["Visited", "Signed up", "Activated", "Trial", "Paid", "Renewed"],
        options: %{title: %{text: "Conversion funnel"}}
      },
      %{
        id: "bf2",
        title: "Pyramid",
        group: :funnel,
        type: :pyramid,
        series: [%{name: "Population (m)", data: [12.4, 10.1, 8.3, 6.0, 3.9, 1.6]}],
        categories: ["0-14", "15-29", "30-44", "45-59", "60-74", "75+"],
        options: %{
          colors: ["#775DD0"],
          plot_options: %{bar: %{bar_height: "85%", distributed: false}},
          title: %{text: "Age pyramid (widest first, drawn at the base)"}
        }
      },
      %{
        id: "bf3",
        title: "Bar with is_funnel (v4.7.0), no 3d connectors",
        group: :funnel,
        type: :bar,
        series: [%{name: "Leads", data: [200, 160, 120, 80, 40]}],
        categories: ~w(Leads Qualified Proposal Negotiation Won),
        options: %{
          plot_options: %{
            bar: %{is_funnel: true, is_funnel_3d: false, distributed: true, border_radius: 4}
          }
        }
      },
      %{
        id: "bf4",
        title: "Waterfall with subtotal and total",
        group: :waterfall,
        type: :waterfall,
        series: [
          %{
            name: "Cash",
            data: [
              %{x: "Opening", y: 120},
              %{x: "Sales", y: 80},
              %{x: "Services", y: 35},
              %{x: "Costs", y: -95},
              %{x: "H1", subtotal: true},
              %{x: "Payroll", y: -40},
              %{x: "Grants", y: 25},
              %{x: "Tax", y: -30},
              %{x: "Closing", total: true}
            ]
          }
        ],
        options: %{title: %{text: "Cash flow"}}
      },
      %{
        id: "bf5",
        title: "Waterfall below zero, custom colours and legend",
        group: :waterfall,
        type: :waterfall,
        series: [%{name: "Profit", data: [40, -70, -25, 30, nil, 45, %{total: true}]}],
        categories: ~w(Jan Feb Mar Apr May Jun YTD),
        options: %{
          plot_options: %{
            bar: %{column_width: "55%", border_radius: 3},
            waterfall: %{
              colors: %{increase: "#13d8aa", decrease: "#d4526e", total: "#546E7A"},
              connector: %{color: "#546E7A", dash_array: 0},
              total_label: "Year to date"
            }
          },
          legend: %{
            custom_legend_items: ["Increase", "Decrease", "Total"],
            markers: %{fill_colors: ["#13d8aa", "#d4526e", "#546E7A"]}
          }
        }
      },
      %{
        id: "bf6",
        title: "Dumbbell",
        group: :dumbbell,
        type: :dumbbell,
        series: [
          %{
            name: "Median salary (k)",
            ends: ["2015", "2025"],
            data: [
              %{x: "Design", y: [42, 61]},
              %{x: "Engineering", y: [55, 78]},
              %{x: "Marketing", y: [40, 52]},
              %{x: "Operations", y: [38, 45]},
              %{x: "Sales", y: [47, 44]},
              %{x: "Support", y: [31, 39]}
            ]
          }
        ],
        options: %{title: %{text: "Salaries, 2015 vs 2025"}}
      },
      %{
        id: "bf7",
        title: "Horizontal dumbbell, two series",
        group: :dumbbell,
        type: :dumbbell,
        series: [
          %{
            name: "Women",
            ends: ["Women 1990", "Women 2020"],
            data: [[74.2, 81.0], [77.1, 83.4], [72.5, 79.9], [69.8, 78.3]]
          },
          %{
            name: "Men",
            ends: ["Men 1990", "Men 2020"],
            data: [[67.5, 76.3], [70.4, 78.9], [66.0, 75.1], [62.9, 72.6]]
          }
        ],
        categories: ["Region A", "Region B", "Region C", "Region D"],
        options: %{
          plot_options: %{bar: %{horizontal: true}},
          markers: %{size: 5},
          yaxis: %{min: 60, max: 85, tick_amount: 5},
          title: %{text: "Life expectancy"}
        }
      },
      %{
        id: "bf8",
        title: "Grouped stacks",
        group: :bar,
        type: :bar,
        series: [
          %{name: "Q1 budget", group: "Budget", data: [44, 55, 41, 37]},
          %{name: "Q2 budget", group: "Budget", data: [13, 23, 20, 8]},
          %{name: "Q1 actual", group: "Actual", data: [48, 50, 40, 41]},
          %{name: "Q2 actual", group: "Actual", data: [10, 30, 22, 12]}
        ],
        categories: ~w(North South East West),
        options: %{
          chart: %{stacked: true},
          colors: ["#008FFB", "#80c7fd", "#00E396", "#80f1cb"],
          title: %{text: "Budget vs actual by region"}
        }
      },
      %{
        id: "bf9",
        title: "Grouped stacks, 100%",
        group: :bar,
        type: :bar,
        series: [
          %{name: "Online 2024", group: "2024", data: [30, 45, 20]},
          %{name: "Store 2024", group: "2024", data: [70, 35, 60]},
          %{name: "Online 2025", group: "2025", data: [52, 60, 25]},
          %{name: "Store 2025", group: "2025", data: [48, 20, 50]}
        ],
        categories: ["Books", "Games", "Toys"],
        options: %{
          chart: %{stacked: true, stack_type: "100%"},
          colors: ["#775DD0", "#c5b8ec", "#FEB019", "#ffdf8c"]
        }
      },
      %{
        id: "bf10",
        title: "Horizontal grouped stacks",
        group: :bar,
        type: :bar,
        series: [
          %{name: "Men <30", group: "Men", data: [12, 18, 9]},
          %{name: "Men 30+", group: "Men", data: [20, 14, 16]},
          %{name: "Women <30", group: "Women", data: [15, 11, 13]},
          %{name: "Women 30+", group: "Women", data: [18, 21, 10]}
        ],
        categories: ["Team A", "Team B", "Team C"],
        options: %{
          chart: %{stacked: true},
          plot_options: %{bar: %{horizontal: true, bar_height: "80%"}},
          colors: ["#008FFB", "#80c7fd", "#FF4560", "#ffa2af"]
        }
      }
    ]
  end
end
