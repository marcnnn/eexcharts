defmodule Dev.ChartExamples do
  @moduledoc """
  Canonical list of chart examples — the single source of truth shared by the
  preview gallery (`dev/preview.exs`), the storybook stories
  (`dev/storybook/*.story.exs`), and the SVG golden-snapshot test
  (`test/svg_snapshot_test.exs`).

  Each entry is a map with an `:id` (stable, unique — used as the snapshot
  filename, storybook variation id, and DOM id), a `:title` (human label), a
  `:group` (which storybook story the example belongs to), and the
  `EexCharts.chart/1` / `EexCharts.render/4` attributes (`:type`, `:series`,
  and any of `:categories`, `:labels`, `:width`, `:height`, `:options`,
  `:hidden_series`, `:on_legend_click`).

  ## Groups

  `:group` is the chart family an example demonstrates, and it doubles as the
  storybook story name: group `:box_plot` is rendered by
  `dev/storybook/box_plot.story.exs` and served at
  `/storybook/box_plot` (iframe: `/storybook/iframe/box_plot`). A group can
  cover more than one `:type` when the types are variants of one family — the
  `:pie` group holds pie *and* donut, `:scatter` holds scatter *and* bubble.
  Keeping the group on the example (rather than in the story files) is what
  keeps the sidebar, the visual test's iframe path, and this list from
  drifting apart.

  `:id` and `:group` are deliberately independent: ids are frozen because they
  name the committed SVG goldens in `test/snapshots/`, while groups are free to
  be reorganised for browsing.

  Everything here is deterministic (the heatmap uses a fixed formula, not
  randomness) so the same input always produces byte-identical SVG.
  """

  @doc """
  Returns every chart example as a list of attribute maps.
  """
  def all do
    [
      %{
        id: "c1",
        title: "Smooth line (multi-series)",
        group: :line,
        type: :line,
        series: [
          %{name: "Desktops", data: [10, 41, 35, 51, 49, 62, 69, 91, 148]},
          %{name: "Mobile", data: [23, 12, 54, 61, 32, 56, 81, 19, 90]}
        ],
        categories: ~w(Jan Feb Mar Apr May Jun Jul Aug Sep),
        options: %{stroke: %{curve: :smooth, width: 3}, title: %{text: "Sales trends"}}
      },
      %{
        id: "c2",
        title: "Straight line + markers + data labels",
        group: :line,
        type: :line,
        series: [%{name: "Sessions", data: [45, 52, 38, 45, 19, 23, 2]}],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun),
        options: %{
          markers: %{size: 5},
          data_labels: %{enabled: true},
          stroke: %{curve: :straight, width: 3}
        }
      },
      %{
        id: "c3",
        title: "Area (gradient fill)",
        group: :area,
        type: :area,
        series: [
          %{name: "Revenue", data: [31, 40, 28, 51, 42, 109, 100]},
          %{name: "Cost", data: [11, 32, 45, 32, 34, 52, 41]}
        ],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun)
      },
      %{
        id: "c4",
        title: "Monotone cubic with gap (nil value)",
        group: :line,
        type: :line,
        series: [%{name: "Load", data: [12, 30, nil, 45, 30, 60, 55]}],
        options: %{stroke: %{curve: :monotone_cubic, width: 4}}
      },
      %{
        id: "c5",
        title: "Grouped columns",
        group: :bar,
        type: :bar,
        series: [
          %{name: "Net Profit", data: [44, 55, 57, 56, 61, 58]},
          %{name: "Revenue", data: [76, 85, 101, 98, 87, 105]},
          %{name: "Free Cash Flow", data: [35, 41, 36, 26, 45, 48]}
        ],
        categories: ~w(Feb Mar Apr May Jun Jul)
      },
      %{
        id: "c6",
        title: "Stacked columns, rounded ends, negatives",
        group: :bar,
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
      },
      %{
        id: "c7",
        title: "Horizontal bars",
        group: :bar,
        type: :bar,
        series: [%{name: "Score", data: [400, 430, 448, 470, 540, 580]}],
        categories: ["South Korea", "Canada", "United Kingdom", "Netherlands", "Italy", "France"],
        options: %{plot_options: %{bar: %{horizontal: true, border_radius: 4}}}
      },
      %{
        id: "c8",
        title: "Pie",
        group: :pie,
        type: :pie,
        series: [44, 55, 13, 43, 22],
        labels: ~w(Team-A Team-B Team-C Team-D Team-E),
        width: 420,
        height: 320
      },
      %{
        id: "c9",
        title: "Donut with total",
        group: :pie,
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
      },
      %{
        id: "c10",
        title: "Distributed columns (color per bar)",
        group: :bar,
        type: :bar,
        series: [%{name: "Visits", data: [21, 22, 10, 28, 16, 21]}],
        categories: ~w(John Joe Jake Amber Peter Mary),
        options: %{
          plot_options: %{bar: %{distributed: true, border_radius: 6}},
          legend: %{show: false}
        }
      },
      %{
        id: "c11",
        title: "Legend toggle (series 1 hidden)",
        group: :line,
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
      },
      %{
        id: "n1",
        title: "Scatter",
        group: :scatter,
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
      },
      %{
        id: "n2",
        title: "Bubble",
        group: :scatter,
        type: :bubble,
        series: [
          %{name: "Product A", data: [[5, 40, 30], [10, 25, 50], [15, 50, 20], [20, 30, 60]]},
          %{name: "Product B", data: [[7, 10, 40], [12, 45, 25], [18, 20, 45]]}
        ],
        options: %{xaxis: %{type: :numeric}}
      },
      %{
        id: "n3",
        title: "Datetime axis",
        group: :area,
        type: :area,
        series: [%{name: "Visitors", data: [31, 40, 28, 51, 42, 80]}],
        categories: [
          ~D[2026-01-01],
          ~D[2026-02-01],
          ~D[2026-03-01],
          ~D[2026-04-01],
          ~D[2026-05-01],
          ~D[2026-06-01]
        ],
        options: %{xaxis: %{type: :datetime}}
      },
      %{
        id: "n4",
        title: "Dark theme",
        group: :line,
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
      },
      %{
        id: "n5",
        title: "Radial bar",
        group: :radial_bar,
        type: :radial_bar,
        series: [76, 61, 90],
        labels: ~w(Vimeo Messenger Facebook),
        width: 420,
        height: 340,
        options: %{legend: %{show: true}}
      },
      %{
        id: "n6",
        title: "Polar area",
        group: :polar_area,
        type: :polar_area,
        series: [14, 23, 21, 17, 15, 10],
        labels: ~w(Rose-A Rose-B Rose-C Rose-D Rose-E Rose-F),
        width: 420,
        height: 340
      },
      %{
        id: "n7",
        title: "Radar",
        group: :radar,
        type: :radar,
        series: [
          %{name: "Series 1", data: [80, 50, 30, 40, 100, 20]},
          %{name: "Series 2", data: [20, 30, 40, 80, 20, 80]}
        ],
        categories: ~w(Jan Feb Mar Apr May Jun),
        width: 480,
        height: 360
      },
      %{
        id: "n8",
        title: "Heatmap",
        group: :heatmap,
        type: :heatmap,
        series:
          for name <- ~w(Metric1 Metric2 Metric3 Metric4 Metric5) do
            %{
              name: name,
              data: Enum.map(1..12, fn i -> rem(i * 37 + String.length(name) * 13, 90) + 10 end)
            }
          end,
        categories: ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
      },
      %{
        id: "n9",
        title: "Treemap",
        group: :treemap,
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
      },
      %{
        id: "n10",
        title: "Candlestick",
        group: :candlestick,
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
      },
      %{
        id: "n11",
        title: "Box plot",
        group: :box_plot,
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
      },
      %{
        id: "n12",
        title: "Range bar",
        group: :range_bar,
        type: :range_bar,
        series: [
          %{name: "Temperature", data: [[-2, 8], [1, 12], [5, 17], [9, 22], [13, 26], [16, 30]]}
        ],
        categories: ~w(Jan Feb Mar Apr May Jun)
      },
      %{
        id: "n13",
        title: "Annotations",
        group: :line,
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
      }
    ]
  end

  @doc """
  Returns every example belonging to `group`, in declaration order.
  """
  def by_group(group) when is_atom(group) do
    Enum.filter(all(), &(&1.group == group))
  end

  @doc """
  Returns the example with the given `:id`, raising when there is none.
  """
  def fetch!(id) when is_binary(id) do
    Enum.find(all(), &(&1.id == id)) || raise ArgumentError, "unknown chart example #{id}"
  end

  @doc """
  Returns the storybook path segment (and story file base name) for an example
  or a group — e.g. `"box_plot"` for `:box_plot`.
  """
  def story_path(%{group: group}), do: story_path(group)
  def story_path(group) when is_atom(group), do: Atom.to_string(group)

  @doc """
  Returns the `EexCharts.chart/1` / `EexCharts.render/4` attributes for an
  example, i.e. the map without the presentation-only `:title` and `:group`
  keys — every remaining key must be a real component attribute, so anything
  added here for bookkeeping has to be dropped in this function too.
  """
  def attributes(example), do: Map.drop(example, [:title, :group])
end
