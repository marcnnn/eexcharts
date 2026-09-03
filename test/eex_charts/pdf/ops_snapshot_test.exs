defmodule EexCharts.PDF.OpsSnapshotTest do
  @moduledoc """
  The PDF equivalent of `EexCharts.SvgSnapshotTest`: every chart type is
  rendered to its content operations and compared, operation for operation,
  against a committed golden under `test/snapshots/pdf/`.

  The operations are the whole backend's output — geometry, colours, state
  changes, text placement — so a golden diff shows exactly which coordinate or
  which operator a change moved, which a rendered PDF never would.

  Fixtures are frozen here rather than taken from `Dev.ChartExamples`, because
  the examples exist to look good in the storybook and are edited for that;
  these exist to pin numbers.

  ## Regenerating goldens

      EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test test/eex_charts/pdf/ops_snapshot_test.exs

  Review the diff in `test/snapshots/pdf/` before committing.
  """
  use ExUnit.Case, async: true

  @snapshots_dir Path.join([__DIR__, "..", "..", "snapshots", "pdf"]) |> Path.expand()
  @update? System.get_env("EEXCHARTS_UPDATE_SNAPSHOTS") not in [nil, ""]

  @cartesian [%{name: "Alpha", data: [31, 40, 28, 51, 42, 60]}]
  @two_series [
    %{name: "Alpha", data: [31, 40, 28, 51, 42, 60]},
    %{name: "Beta", data: [11, 32, 45, 32, 34, 52]}
  ]
  @months ~w(Jan Feb Mar Apr May Jun)

  @charts [
    %{
      name: "line",
      type: :line,
      series: @two_series,
      opts: [categories: @months, options: %{stroke: %{curve: :smooth, width: 3}}]
    },
    %{
      name: "line_markers",
      type: :line,
      series: @cartesian,
      opts: [
        categories: @months,
        options: %{markers: %{size: 5}, data_labels: %{enabled: true}}
      ]
    },
    %{
      name: "area_gradient",
      type: :area,
      series: @two_series,
      opts: [categories: @months]
    },
    %{
      name: "bar_rounded_negative",
      type: :bar,
      series: [%{name: "Net", data: [31, -40, 28, -51, 42, 60]}],
      opts: [
        categories: @months,
        options: %{plot_options: %{bar: %{border_radius: 6}}, data_labels: %{enabled: true}}
      ]
    },
    %{
      name: "bar_stacked",
      type: :bar,
      series: [
        %{name: "Cash", data: [44, 55, 41, 67, 22]},
        %{name: "Credit", data: [13, 23, 20, 8, 13]},
        %{name: "Refunds", data: [-11, -17, -15, -15, -21]}
      ],
      opts: [
        categories: ~w(Q1 Q2 Q3 Q4 Q5),
        options: %{
          chart: %{stacked: true},
          plot_options: %{bar: %{border_radius: 4}},
          data_labels: %{enabled: true}
        }
      ]
    },
    %{
      name: "bar_horizontal",
      type: :bar,
      series: [%{name: "Cities", data: [400, 430, 448, 470, 540]}],
      opts: [
        categories: ~w(Seoul Toronto London Berlin Rome),
        options: %{plot_options: %{bar: %{horizontal: true}}, data_labels: %{enabled: true}}
      ]
    },
    %{
      name: "pie",
      type: :pie,
      series: [44, 55, 13, 43, 22],
      opts: [labels: ~w(Team-A Team-B Team-C Team-D Team-E)]
    },
    %{
      name: "donut",
      type: :donut,
      series: [44, 55, 41, 17],
      opts: [
        labels: ~w(Apples Oranges Bananas Cherries),
        options: %{plot_options: %{pie: %{donut: %{labels: %{show: true}}}}}
      ]
    },
    %{
      name: "scatter",
      type: :scatter,
      series: [
        %{name: "A", data: [[16.4, 5.4], [21.7, 2], [25.4, 3], [19, 2]]},
        %{name: "B", data: [[36.4, 13.4], [1.7, 11], [5.4, 8]]}
      ],
      opts: [options: %{xaxis: %{type: :numeric}}]
    },
    %{
      name: "bubble",
      type: :bubble,
      series: [
        %{name: "A", data: [[5, 40, 30], [10, 25, 50], [15, 50, 20]]},
        %{name: "B", data: [[7, 10, 40], [12, 45, 25]]}
      ],
      opts: [options: %{xaxis: %{type: :numeric}}]
    },
    %{
      name: "radial_bar",
      type: :radial_bar,
      series: [76, 61, 90],
      opts: [labels: ~w(Vimeo Messenger Facebook), width: 420, height: 340]
    },
    %{
      name: "polar_area",
      type: :polar_area,
      series: [14, 23, 21, 17, 15, 10],
      opts: [labels: ~w(A B C D E F), width: 420, height: 340]
    },
    %{
      name: "radar",
      type: :radar,
      series: @two_series,
      opts: [categories: @months, width: 480, height: 360]
    },
    %{
      name: "heatmap",
      type: :heatmap,
      series: [
        %{name: "Metric1", data: [10, 42, 33, 74, 25, 66]},
        %{name: "Metric2", data: [61, 22, 83, 14, 55, 36]},
        %{name: "Metric3", data: [30, 71, 12, 53, 94, 45]}
      ],
      opts: [categories: @months]
    },
    %{
      name: "treemap",
      type: :treemap,
      series: [
        %{
          name: "Population",
          data: [
            %{x: "New Delhi", y: 218},
            %{x: "Kolkata", y: 149},
            %{x: "Mumbai", y: 184},
            %{x: "Pune", y: 31},
            %{x: "Chennai", y: 70}
          ]
        }
      ],
      opts: []
    },
    %{
      name: "candlestick",
      type: :candlestick,
      series: [
        %{
          name: "BTC",
          data: [
            [6629, 6650, 6623, 6633],
            [6632, 6641, 6620, 6630],
            [6630, 6655, 6625, 6650],
            [6650, 6680, 6645, 6675],
            [6675, 6690, 6635, 6640]
          ]
        }
      ],
      opts: [categories: ~w(Mon Tue Wed Thu Fri)]
    },
    %{
      name: "box_plot",
      type: :box_plot,
      series: [
        %{
          name: "Stats",
          data: [[40, 45, 52, 60, 65], [43, 48, 55, 62, 70], [35, 40, 47, 55, 62]]
        }
      ],
      opts: [categories: ~w(Q1 Q2 Q3)]
    },
    %{
      name: "range_bar",
      type: :range_bar,
      series: [%{name: "Temperature", data: [[-2, 8], [1, 12], [5, 17], [9, 22]]}],
      opts: [categories: ~w(Jan Feb Mar Apr)]
    },
    # Everything the walker has a special case for, on one chart: a rotated
    # x-axis label group, a rotated y-axis title, dashed strokes, a filled
    # region annotation, a rotated annotation label and a point annotation.
    %{
      name: "annotated",
      type: :line,
      series: [%{name: "Sales", data: [31, 40, 28, 51, 42, 60, 100]}],
      opts: [
        categories: ~w(Monday Tuesday Wednesday Thursday Friday Saturday Sunday),
        options: %{
          stroke: %{curve: :smooth, width: 3, dash_array: 5},
          xaxis: %{labels: %{rotate: -45}},
          yaxis: %{title: %{text: "Revenue"}},
          annotations: %{
            yaxis: [%{y: 50, border_color: "#00E396", label: %{text: "target"}}],
            xaxis: [
              %{x: "Thursday", x2: "Saturday", fill_color: "#B3F7CA", label: %{text: "weekend"}}
            ],
            points: [%{x: "Sunday", y: 100, marker: %{size: 6}, label: %{text: "record"}}]
          }
        }
      ]
    },
    # Placement and scaling are part of the output, so pin them too.
    %{
      name: "placed_and_scaled",
      type: :bar,
      series: @cartesian,
      opts: [categories: @months, x: 42.5, y: 300, scale: 0.75]
    }
  ]

  setup_all do
    File.mkdir_p!(@snapshots_dir)
    :ok
  end

  # One operation per line, with inspect options pinned so the file is a
  # readable diff rather than a wrapped blob.
  defp format(ops) do
    Enum.map_join(ops, fn op ->
      inspect(op, limit: :infinity, printable_limit: :infinity, width: :infinity) <> "\n"
    end)
  end

  for chart <- @charts do
    @chart chart
    @golden Path.join(@snapshots_dir, "#{chart.name}.ops")

    test "#{@chart.name} (#{@chart.type})" do
      actual =
        EexCharts.PDF.ops("snap", @chart.type, @chart.series, @chart.opts)
        |> format()

      if @update? do
        File.write!(@golden, actual)
      else
        assert File.exists?(@golden),
               "missing golden #{@golden}. Seed it with EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test"

        assert actual == File.read!(@golden),
               "PDF op snapshot mismatch for #{@chart.name}.\n" <>
                 "If this change is intentional, regenerate with " <>
                 "EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test."
      end
    end
  end

  test "op lists are stable across runs" do
    chart = %{type: :bar, series: @two_series, opts: [categories: @months]}

    assert EexCharts.PDF.ops("snap", chart.type, chart.series, chart.opts) ==
             EexCharts.PDF.ops("snap", chart.type, chart.series, chart.opts)
  end

  test "every chart type is covered" do
    covered = @charts |> Enum.map(& &1.type) |> MapSet.new()

    all =
      MapSet.new([
        :line,
        :area,
        :bar,
        :pie,
        :donut,
        :scatter,
        :bubble,
        :radial_bar,
        :polar_area,
        :radar,
        :heatmap,
        :treemap,
        :candlestick,
        :box_plot,
        :range_bar
      ])

    assert MapSet.difference(all, covered) |> MapSet.to_list() == []
  end
end
