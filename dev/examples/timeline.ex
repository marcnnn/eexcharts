defmodule Dev.ChartExamples.Timeline do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @outline %{type: :none}
  @pattern %{type: :pattern, pattern: %{style: :slanted_lines}}

  def examples do
    [
      %{
        id: "tl1",
        title: "Timeline with bar-end labels and a today marker",
        group: :range_bar,
        type: :range_bar,
        series: [
          %{
            name: "Tracks",
            data: [
              %{x: "Track 1", y: [~D[2024-01-01], ~D[2024-04-01]], label: "11/12"},
              %{x: "Track 1", y: [~D[2025-01-01], ~D[2025-04-01]], label: "12/12"},
              %{x: "Track 1", y: [~D[2026-01-01], ~D[2026-05-01]], label: "11/12"},
              %{x: "Track 2", y: [~D[2024-06-01], ~D[2024-08-15]], label: "8/12"},
              %{x: "Track 2", y: [~D[2025-06-01], ~D[2025-08-15]], label: "9/12"},
              %{x: "Track 2", y: [~D[2026-08-01], ~D[2026-11-05]], fill: @outline, label: "6/12"},
              %{x: "Track 3", y: [~D[2025-03-01], ~D[2025-08-01]], label: "4/12"},
              %{x: "Track 3", y: [~D[2026-09-01], ~D[2027-02-01]], fill: @outline, label: "3/12"},
              %{x: "Track 4", y: [~D[2025-10-01], ~D[2025-12-31]], label: "3/12"},
              %{x: "Track 4", y: [~D[2027-02-01], ~D[2027-04-15]], fill: @pattern, label: "0/12"},
              %{x: "Track 5", y: [~D[2027-03-01], ~D[2027-08-01]], fill: @pattern, label: "0/12"}
            ]
          }
        ],
        options: %{
          xaxis: %{type: :datetime},
          plot_options: %{
            bar: %{horizontal: true, bar_height: "50%", data_labels: %{position: :outside_end}}
          },
          data_labels: %{enabled: true},
          annotations: %{
            xaxis: [
              %{
                x: ~D[2026-10-29],
                border_color: "#F86624",
                border_width: 2,
                stroke_dash_array: 4,
                label: %{
                  text: "Today",
                  orientation: :horizontal,
                  text_anchor: :start,
                  offset_x: 4,
                  border_width: 0,
                  style: %{background: "transparent", color: "#F86624"}
                }
              }
            ]
          }
        }
      },
      %{
        id: "tl2",
        title: "Timeline rows shared by two series, overlaps split",
        group: :range_bar,
        type: :range_bar,
        series: [
          %{
            name: "Series 1",
            data: [
              %{x: "Row A", y: [~N[2026-01-05 00:00:00], ~N[2026-02-20 00:00:00]]},
              %{x: "Row A", y: [~N[2026-02-01 00:00:00], ~N[2026-03-15 00:00:00]]},
              %{x: "Row B", y: ["2026-01-20", "2026-04-01"]},
              %{x: "Row C", y: [~U[2026-03-01 00:00:00Z], ~U[2026-05-10 00:00:00Z]]}
            ]
          },
          %{
            name: "Series 2",
            data: [
              %{x: "Row B", y: [~D[2026-04-10], ~D[2026-05-20]]},
              %{x: "Row C", y: [~D[2026-01-10], ~D[2026-02-15]]}
            ]
          }
        ],
        options: %{
          xaxis: %{type: :datetime},
          plot_options: %{
            bar: %{horizontal: true, range_bar_group_rows: true, range_bar_overlap: false}
          },
          data_labels: %{enabled: true, formatter: &__MODULE__.days/1}
        }
      }
    ]
  end

  @doc false
  def days([from, to]), do: "#{div(to - from, 86_400_000)} d"
end
