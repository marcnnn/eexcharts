# Byte-identity harness for the SVG serializer.
#
#   mix run dev/svg_bytes.exs /tmp/eexcharts_baseline
#
# Renders one representative config per chart type (plus the option corners
# that exercise every path helper: gradients, rounded/negative bars, dash
# arrays, rotated labels, every marker shape, annotations, the HTML legend)
# through `EexCharts.to_svg/4` and writes each to `<dir>/<name>.svg`. Run it on
# two revisions and `diff -r` the directories to prove the output is unchanged.

defmodule SvgBytes do
  @cats ~w(Jan Feb Mar Apr May Jun Jul Aug Sep)
  @shapes [:circle, :square, :triangle, :diamond, :star, :sparkle, :cross, :plus, :line, :rect]

  def cases do
    [
      {"line", :line, [%{name: "Desktops", data: [10, 41, 35, 51, 49, 62, 69, 91, 148]}],
       [categories: @cats, options: %{title: %{text: "Sales"}, stroke: %{curve: :smooth}}]},
      {"line_straight_markers", :line,
       [
         %{name: "A", data: [45, 52, 38, 45, 19, 23, 2]},
         %{name: "B", data: [12, 22, 48, 15, 29, 33, 12]}
       ],
       [
         categories: ~w(Mon Tue Wed Thu Fri Sat Sun),
         options: %{
           markers: %{size: 5},
           data_labels: %{enabled: true, background: %{enabled: true}},
           stroke: %{curve: :straight, width: 3}
         }
       ]},
      {"line_stepline_dash", :line,
       [
         %{name: "A", data: [10, 41, 35, 51, 49]},
         %{name: "B", data: [110, 141, 135, 151, 149]}
       ],
       [
         categories: ~w(Jan Feb Mar Apr May),
         options: %{stroke: %{curve: :stepline, dash_array: [4, 8]}}
       ]},
      {"line_monotone_gap", :line, [%{name: "Load", data: [12, 30, nil, 45, 30, 60, 55]}],
       [options: %{stroke: %{curve: :monotone_cubic, width: 4}}]},
      {"line_rotated_labels", :line, [%{name: "Sales", data: [31, 40, 28, 51, 42, 60, 100]}],
       [
         categories: [
           "Very long label one",
           "Very long label two",
           "Very long label three",
           "Very long label four",
           "Very long label five",
           "Very long label six",
           "Very long label seven"
         ],
         options: %{xaxis: %{labels: %{rotate: -45}}}
       ]},
      {"line_annotations", :line, [%{name: "Sales", data: [31, 40, 28, 51, 42, 60, 100]}],
       [
         categories: ~w(Mon Tue Wed Thu Fri Sat Sun),
         options: %{
           stroke: %{curve: :smooth, width: 3},
           annotations: %{
             yaxis: [%{y: 50, border_color: "#00E396", label: %{text: "target"}}],
             xaxis: [
               %{x: "Thu", x2: "Sat", fill_color: "#B3F7CA", label: %{text: "weekend push"}}
             ],
             points: [%{x: "Sun", y: 100, marker: %{size: 6}, label: %{text: "record"}}]
           }
         }
       ]},
      {"line_html_legend", :line,
       [%{name: "Alpha", data: [10, 41, 35]}, %{name: "Beta", data: [23, 12, 54]}],
       [categories: ~w(Jan Feb Mar), options: %{legend: %{html: true}}]},
      {"line_dark_grid_gradient", :line,
       [
         %{name: "North", data: [10, 41, 35, 51, 49, 62]},
         %{name: "South", data: [23, 12, 54, 61, 32, 56]}
       ],
       [
         categories: ~w(Jan Feb Mar Apr May Jun),
         options: %{
           theme: %{mode: :dark},
           chart: %{background: "#343E59"},
           grid: %{
             stroke_dash_array: 4,
             xaxis_lines: true,
             background: %{
               opacity: 0.5,
               gradient: %{angle: 135, stops: [{0, "#fff"}, {100, "#123"}]}
             }
           }
         }
       ]},
      {"line_daisy", :line, [%{name: "A", data: [3, 1, 4, 1, 5]}],
       [categories: ~w(a b c d e), options: %{theme: %{mode: :daisy}}]},
      {"area_gradient", :area,
       [
         %{name: "Revenue", data: [31, 40, 28, 51, 42, 109, 100]},
         %{name: "Cost", data: [11, 32, 45, 32, 34, 52, 41]}
       ], [categories: ~w(Mon Tue Wed Thu Fri Sat Sun)]},
      # NB: a `:datetime` axis with `Date` categories cannot go through
      # `to_svg/4` — `Renderer.resolve_cfg_vars/1` walks structs as maps and
      # blows up on `Date`. The datetime axis is covered by the `render_n3`
      # catalogue entry below instead.
      {"bar_grouped", :bar,
       [
         %{name: "Net Profit", data: [44, 55, 57, 56, 61, 58]},
         %{name: "Revenue", data: [76, 85, 101, 98, 87, 105]},
         %{name: "Free Cash Flow", data: [35, 41, 36, 26, 45, 48]}
       ], [categories: ~w(Feb Mar Apr May Jun Jul)]},
      {"bar_radius_negative", :bar, [%{name: "Delta", data: [44, -55, 41, -67, 22]}],
       [
         categories: ~w(Q1 Q2 Q3 Q4 Q5),
         options: %{
           data_labels: %{enabled: true},
           plot_options: %{bar: %{border_radius: 6, border_radius_application: :around}}
         }
       ]},
      {"bar_stacked", :bar,
       [
         %{name: "Cash", data: [44, 55, 41, 67, 22]},
         %{name: "Credit", data: [13, 23, 20, 8, 13]},
         %{name: "Refunds", data: [-11, -17, -15, -15, -21]}
       ],
       [
         categories: ~w(Q1 Q2 Q3 Q4 Q5),
         options: %{
           chart: %{stacked: true},
           plot_options: %{bar: %{border_radius: 5, border_radius_application: :end}}
         }
       ]},
      {"bar_horizontal", :bar, [%{name: "Score", data: [400, 430, 448, 470, 540, 580]}],
       [
         categories: ["South Korea", "Canada", "United Kingdom", "Netherlands", "Italy", "France"],
         options: %{plot_options: %{bar: %{horizontal: true, border_radius: 4}}}
       ]},
      {"bar_distributed", :bar, [%{name: "Visits", data: [21, 22, 10, 28, 16, 21]}],
       [
         categories: ~w(John Joe Jake Amber Peter Mary),
         options: %{
           plot_options: %{bar: %{distributed: true, border_radius: 6}},
           legend: %{show: false}
         }
       ]},
      {"pie", :pie, [44, 55, 13, 43, 22],
       [labels: ~w(Team-A Team-B Team-C Team-D Team-E), width: 420, height: 320]},
      {"donut", :donut, [44, 55, 41, 17],
       [
         labels: ~w(Apples Oranges Bananas Cherries),
         width: 420,
         height: 320,
         options: %{
           plot_options: %{pie: %{donut: %{labels: %{show: true, total: %{show: true}}}}}
         }
       ]},
      {"scatter", :scatter,
       [
         %{name: "Sample A", data: [[16.4, 5.4], [21.7, 2], [25.4, 3], [19, 2], [10.9, 1]]},
         %{name: "Sample B", data: [[36.4, 13.4], [1.7, 11], [5.4, 8], [9, 17]]}
       ], [options: %{xaxis: %{type: :numeric}}]},
      {"scatter_all_marker_shapes", :scatter,
       for {shape, i} <- Enum.with_index(@shapes) do
         %{name: "#{shape}", data: [[i, i * 2], [i + 1, i * 3], [i + 2, i + 1]]}
       end,
       [
         width: 900,
         height: 500,
         options: %{
           markers: %{size: 8, shape: @shapes},
           legend: %{markers: %{shape: @shapes}},
           xaxis: %{type: :numeric}
         }
       ]},
      {"bubble", :bubble,
       [
         %{name: "Product A", data: [[5, 40, 30], [10, 25, 50], [15, 50, 20], [20, 30, 60]]},
         %{name: "Product B", data: [[7, 10, 40], [12, 45, 25], [18, 20, 45]]}
       ], [options: %{xaxis: %{type: :numeric}}]},
      {"radial_bar", :radial_bar, [76, 61, 90],
       [
         labels: ~w(Vimeo Messenger Facebook),
         width: 420,
         height: 340,
         options: %{legend: %{show: true}}
       ]},
      {"polar_area", :polar_area, [14, 23, 21, 17, 15, 10],
       [labels: ~w(Rose-A Rose-B Rose-C Rose-D Rose-E Rose-F), width: 420, height: 340]},
      {"radar", :radar,
       [
         %{name: "Series 1", data: [80, 50, 30, 40, 100, 20]},
         %{name: "Series 2", data: [20, 30, 40, 80, 20, 80]}
       ], [categories: ~w(Jan Feb Mar Apr May Jun), width: 480, height: 360]},
      {"heatmap", :heatmap,
       for name <- ~w(Metric1 Metric2 Metric3 Metric4 Metric5) do
         %{
           name: name,
           data: Enum.map(1..12, fn i -> rem(i * 37 + String.length(name) * 13, 90) + 10 end)
         }
       end, [categories: ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)]},
      {"treemap", :treemap,
       [
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
       ], []},
      {"candlestick", :candlestick,
       [
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
       ], [categories: ~w(Mon Tue Wed Thu Fri Sat)]},
      {"box_plot", :box_plot,
       [
         %{
           name: "Stats",
           data: [
             [40, 45, 52, 60, 65],
             [43, 48, 55, 62, 70],
             [35, 40, 47, 55, 62],
             [48, 52, 58, 63, 68]
           ]
         }
       ], [categories: ~w(Q1 Q2 Q3 Q4)]},
      {"range_bar", :range_bar,
       [%{name: "Temperature", data: [[-2, 8], [1, 12], [5, 17], [9, 22], [13, 26], [16, 30]]}],
       [categories: ~w(Jan Feb Mar Apr May Jun)]},
      {"line_hidden_series", :line,
       [
         %{name: "Alpha", data: [10, 41, 35, 51, 49]},
         %{name: "Beta", data: [110, 141, 135, 151, 149]},
         %{name: "Gamma", data: [23, 12, 54, 61, 32]}
       ], [categories: ~w(Jan Feb Mar Apr May), hidden_series: [1]]}
    ]
  end

  defp serialize(node), do: node |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()

  def run(dir) do
    File.mkdir_p!(dir)

    for {name, type, series, opts} <- cases() do
      svg = EexCharts.to_svg("t", type, series, opts)
      File.write!(Path.join(dir, name <> ".svg"), svg)
    end

    # The full example catalogue too, through the non-static path.
    for example <- Dev.ChartExamples.all() do
      opts =
        example
        |> Dev.ChartExamples.attributes()
        |> Map.drop([:id, :type, :series])
        |> Map.put(:hook, false)
        |> Map.to_list()

      {:safe, io} = EexCharts.render(example.id, example.type, example.series, opts)
      File.write!(Path.join(dir, "render_#{example.id}.svg"), IO.iodata_to_binary(io))
    end

    # `Marker.path/4`'s circular branch is unreachable through `render/5`
    # (which emits a `<circle>`), so dump every shape's path data directly —
    # that is the only coverage of the relative-move (` m `) fragment.
    marker_paths =
      Enum.map_join(@shapes ++ [:unknown], "\n", fn shape ->
        d = EexCharts.Marker.path(shape, 12.5, 7.25, 4.5)
        "#{shape}\t" <> serialize(EexCharts.SVG.el("path", %{d: d}))
      end)

    File.write!(Path.join(dir, "marker_paths.txt"), marker_paths <> "\n")

    IO.puts("wrote #{length(File.ls!(dir))} files to #{dir}")
  end
end

SvgBytes.run(List.first(System.argv()) || "/tmp/eexcharts_baseline")
