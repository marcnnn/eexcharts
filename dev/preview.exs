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
