# Renders a gallery of charts to dev/preview.html for visual inspection.
# Run: mix run dev/preview.exs
#
# The page inlines the hover-hook JS (standalone, without LiveView) so
# tooltips, crosshairs and hover markers can be tested in a plain browser.

defmodule Preview do
  def chart(title, params) do
    {:safe, io} =
      EexCharts.render(params[:id], params[:type], params[:series], Map.to_list(params))

    """
    <div class="card">
      <h3>#{title}</h3>
      #{IO.iodata_to_binary(io)}
    </div>
    """
  end

  def run do
    charts = [
      chart("Smooth line (multi-series)", %{
        id: "c1",
        type: :line,
        series: [
          %{name: "Desktops", data: [10, 41, 35, 51, 49, 62, 69, 91, 148]},
          %{name: "Mobile", data: [23, 12, 54, 61, 32, 56, 81, 19, 90]}
        ],
        categories: ~w(Jan Feb Mar Apr May Jun Jul Aug Sep),
        options: %{stroke: %{curve: :smooth, width: 3}, title: %{text: "Sales trends"}}
      }),
      chart("Straight line + markers + data labels", %{
        id: "c2",
        type: :line,
        series: [%{name: "Sessions", data: [45, 52, 38, 45, 19, 23, 2]}],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun),
        options: %{
          markers: %{size: 5},
          data_labels: %{enabled: true},
          stroke: %{curve: :straight, width: 3}
        }
      }),
      chart("Area (gradient fill)", %{
        id: "c3",
        type: :area,
        series: [
          %{name: "Revenue", data: [31, 40, 28, 51, 42, 109, 100]},
          %{name: "Cost", data: [11, 32, 45, 32, 34, 52, 41]}
        ],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun)
      }),
      chart("Monotone cubic with gap (nil value)", %{
        id: "c4",
        type: :line,
        series: [%{name: "Load", data: [12, 30, nil, 45, 30, 60, 55]}],
        options: %{stroke: %{curve: :monotone_cubic, width: 4}}
      }),
      chart("Grouped columns", %{
        id: "c5",
        type: :bar,
        series: [
          %{name: "Net Profit", data: [44, 55, 57, 56, 61, 58]},
          %{name: "Revenue", data: [76, 85, 101, 98, 87, 105]},
          %{name: "Free Cash Flow", data: [35, 41, 36, 26, 45, 48]}
        ],
        categories: ~w(Feb Mar Apr May Jun Jul)
      }),
      chart("Stacked columns, rounded ends, negatives", %{
        id: "c6",
        type: :bar,
        series: [
          %{name: "Cash", data: [44, 55, 41, 67, 22]},
          %{name: "Credit", data: [13, 23, 20, 8, 13]},
          %{name: "Refunds", data: [-11, -17, -15, -15, -21]}
        ],
        categories: ~w(Q1 Q2 Q3 Q4 Q5),
        options: %{
          chart: %{stacked: true},
          plot_options: %{bar: %{border_radius: 5, border_radius_application: :end}}
        }
      }),
      chart("Horizontal bars", %{
        id: "c7",
        type: :bar,
        series: [%{name: "Score", data: [400, 430, 448, 470, 540, 580]}],
        categories: ["South Korea", "Canada", "United Kingdom", "Netherlands", "Italy", "France"],
        options: %{plot_options: %{bar: %{horizontal: true, border_radius: 4}}}
      }),
      chart("Pie", %{
        id: "c8",
        type: :pie,
        series: [44, 55, 13, 43, 22],
        labels: ~w(Team-A Team-B Team-C Team-D Team-E),
        width: 420,
        height: 320
      }),
      chart("Donut with total", %{
        id: "c9",
        type: :donut,
        series: [44, 55, 41, 17],
        labels: ~w(Apples Oranges Bananas Cherries),
        width: 420,
        height: 320,
        options: %{
          plot_options: %{
            pie: %{donut: %{labels: %{show: true, total: %{show: true}}}}
          }
        }
      }),
      chart("Distributed columns (color per bar)", %{
        id: "c10",
        type: :bar,
        series: [%{name: "Visits", data: [21, 22, 10, 28, 16, 21]}],
        categories: ~w(John Joe Jake Amber Peter Mary),
        options: %{
          plot_options: %{bar: %{distributed: true, border_radius: 6}},
          legend: %{show: false}
        }
      }),
      chart("Legend toggle (series 1 hidden)", %{
        id: "c11",
        type: :line,
        series: [
          %{name: "Alpha", data: [10, 41, 35, 51, 49]},
          %{name: "Beta", data: [110, 141, 135, 151, 149]},
          %{name: "Gamma", data: [23, 12, 54, 61, 32]}
        ],
        categories: ~w(Jan Feb Mar Apr May),
        hidden_series: [1],
        on_legend_click: "toggle-series",
        options: %{stroke: %{curve: :smooth, width: 3}}
      }),
      chart("Scatter", %{
        id: "n1",
        type: :scatter,
        series: [
          %{
            name: "Sample A",
            data: [
              [16.4, 5.4],
              [21.7, 2],
              [25.4, 3],
              [19, 2],
              [10.9, 1],
              [13.6, 3.2],
              [10.9, 7.4]
            ]
          },
          %{
            name: "Sample B",
            data: [[36.4, 13.4], [1.7, 11], [5.4, 8], [9, 17], [1.9, 4], [3.6, 12.2]]
          }
        ],
        options: %{xaxis: %{type: :numeric}}
      }),
      chart("Bubble", %{
        id: "n2",
        type: :bubble,
        series: [
          %{name: "Product A", data: [[5, 40, 30], [10, 25, 50], [15, 50, 20], [20, 30, 60]]},
          %{name: "Product B", data: [[7, 10, 40], [12, 45, 25], [18, 20, 45]]}
        ],
        options: %{xaxis: %{type: :numeric}}
      }),
      chart("Datetime axis", %{
        id: "n3",
        type: :area,
        series: [
          %{
            name: "Visitors",
            data: [
              [~D[2026-01-01], 31],
              [~D[2026-02-01], 40],
              [~D[2026-03-01], 28],
              [~D[2026-04-01], 51],
              [~D[2026-05-01], 42],
              [~D[2026-06-01], 80]
            ]
          }
        ],
        options: %{xaxis: %{type: :datetime}}
      }),
      chart("Dark theme", %{
        id: "n4",
        type: :line,
        series: [
          %{name: "North", data: [10, 41, 35, 51, 49, 62]},
          %{name: "South", data: [23, 12, 54, 61, 32, 56]}
        ],
        categories: ~w(Jan Feb Mar Apr May Jun),
        options: %{
          theme: %{mode: :dark},
          chart: %{background: "#343E59"},
          stroke: %{curve: :smooth, width: 3}
        }
      }),
      chart("Radial bar", %{
        id: "n5",
        type: :radial_bar,
        series: [76, 61, 90],
        labels: ~w(Vimeo Messenger Facebook),
        width: 420,
        height: 340,
        options: %{legend: %{show: true}}
      }),
      chart("Polar area", %{
        id: "n6",
        type: :polar_area,
        series: [14, 23, 21, 17, 15, 10],
        labels: ~w(Rose-A Rose-B Rose-C Rose-D Rose-E Rose-F),
        width: 420,
        height: 340
      }),
      chart("Radar", %{
        id: "n7",
        type: :radar,
        series: [
          %{name: "Series 1", data: [80, 50, 30, 40, 100, 20]},
          %{name: "Series 2", data: [20, 30, 40, 80, 20, 80]}
        ],
        categories: ~w(Jan Feb Mar Apr May Jun),
        width: 480,
        height: 360
      }),
      chart("Heatmap", %{
        id: "n8",
        type: :heatmap,
        series:
          for name <- ~w(Metric1 Metric2 Metric3 Metric4 Metric5) do
            %{
              name: name,
              data: Enum.map(1..12, fn i -> rem(i * 37 + String.length(name) * 13, 90) + 10 end)
            }
          end,
        categories: ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
      }),
      chart("Treemap", %{
        id: "n9",
        type: :treemap,
        series: [
          %{
            name: "Population",
            data: [
              %{x: "New Delhi", y: 218},
              %{x: "Kolkata", y: 149},
              %{x: "Mumbai", y: 184},
              %{x: "Ahmedabad", y: 55},
              %{x: "Bangaluru", y: 84},
              %{x: "Pune", y: 31},
              %{x: "Chennai", y: 70},
              %{x: "Jaipur", y: 30}
            ]
          }
        ]
      }),
      chart("Candlestick", %{
        id: "n10",
        type: :candlestick,
        series: [
          %{
            name: "BTC",
            data: [
              [6629, 6650, 6623, 6633],
              [6632, 6641, 6620, 6630],
              [6630, 6655, 6625, 6650],
              [6650, 6680, 6645, 6675],
              [6675, 6690, 6635, 6640],
              [6640, 6665, 6630, 6660]
            ]
          }
        ],
        categories: ~w(Mon Tue Wed Thu Fri Sat)
      }),
      chart("Box plot", %{
        id: "n11",
        type: :box_plot,
        series: [
          %{
            name: "Stats",
            data: [
              [40, 45, 52, 60, 65],
              [43, 48, 55, 62, 70],
              [35, 40, 47, 55, 62],
              [48, 52, 58, 63, 68]
            ]
          }
        ],
        categories: ~w(Q1 Q2 Q3 Q4)
      }),
      chart("Range bar", %{
        id: "n12",
        type: :range_bar,
        series: [
          %{name: "Temperature", data: [[-2, 8], [1, 12], [5, 17], [9, 22], [13, 26], [16, 30]]}
        ],
        categories: ~w(Jan Feb Mar Apr May Jun)
      }),
      chart("Annotations", %{
        id: "n13",
        type: :line,
        series: [%{name: "Sales", data: [31, 40, 28, 51, 42, 60, 100]}],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun),
        options: %{
          stroke: %{curve: :smooth, width: 3},
          annotations: %{
            yaxis: [%{y: 50, border_color: "#00E396", label: %{text: "target"}}],
            xaxis: [%{x: "Thu", x2: "Sat", fill_color: "#B3F7CA", label: %{text: "weekend push"}}],
            points: [%{x: "Sun", y: 100, marker: %{size: 6}, label: %{text: "record"}}]
          }
        }
      })
    ]

    js =
      "priv/static/eexcharts.js"
      |> File.read!()
      |> String.replace("export default EexCharts;", "")

    css = File.read!("priv/static/eexcharts.css")

    html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>EexCharts preview</title>
      <style>
        body { font-family: Helvetica, Arial, sans-serif; background: #f6f7f8; margin: 24px; }
        .grid { display: grid; grid-template-columns: repeat(2, minmax(380px, 640px)); gap: 24px; }
        .card { background: #fff; border-radius: 8px; padding: 16px; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
        .card h3 { margin: 0 0 8px; font-size: 14px; color: #373d3f; }
        #{css}
      </style>
    </head>
    <body>
      <h1>EexCharts preview</h1>
      <div class="grid">
        #{Enum.join(charts, "\n")}
      </div>
      <script>
        #{js}
        document.querySelectorAll(".eexcharts").forEach((el) => {
          const inst = Object.create(EexCharts);
          inst.el = el;
          inst.pushEvent = () => {};
          inst.mounted();
        });
      </script>
    </body>
    </html>
    """

    File.write!("dev/preview.html", html)
    IO.puts("wrote dev/preview.html")
  end
end

Preview.run()
