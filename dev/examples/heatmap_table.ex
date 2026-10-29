defmodule Dev.ChartExamples.HeatmapTable do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @grey "#e8e8e8"
  @dark "#2a2018"
  @orange "#ff6105"

  @months for j <- 1..12, do: String.pad_leading("#{j}", 2, "0")

  @table [
    {"Row A", [60, 52, 84, 87, 86, 94, 69, 75, 83, 73, 90, 59]},
    {"Row B", [51, 35, 68, 65, 80, 85, 76, 75, 81, 70, 78, 70]},
    {"Row C", [52, 24, 74, 79, 66, 93, 67, 69, 83, 58, 39, 62]},
    {"Row D", [38, 20, 44, 49, 41, 65, 60, 40, 68, 39, 57, 34]},
    {"Row E", [71, 52, 97, 100, 98, 92, 82, 94, 95, 91, 87, 80]},
    {"Row F", [58, 43, 76, 91, 87, 85, 100, 92, 89, 81, 94, 84]},
    {"Row G", [49, 18, 70, 67, 61, 85, 59, 71, 69, 62, 80, 55]},
    {"Row H", [59, 33, 87, 97, 74, 89, 83, 74, 99, 73, 88, 69]},
    {"Row I", [63, 30, 71, 80, 78, 93, 74, 94, 82, 92, 79, 83]},
    {"Row J", [35, 8, 63, 70, 92, 100, 85, 91, 100, 93, 85, 57]}
  ]

  # Discrete bands, darkest first as in the legend.
  @ranges [
    %{from: 85, to: 100, color: @dark, fore_color: "#ffffff", name: "85-100"},
    %{from: 60, to: 84.99, color: "#b8b8b8", fore_color: @dark, name: "60-84"},
    %{from: 40, to: 59.99, color: "#efefef", fore_color: @dark, name: "40-59"},
    %{from: 0, to: 39.99, color: @orange, fore_color: @dark, name: "Below 40"}
  ]

  def examples do
    [
      %{
        id: "ht1",
        title: "Heatmap - per-cell colours and two-line labels",
        group: :heatmap,
        type: :heatmap,
        # Series 0 is the bottom row, so "State 3" comes first.
        series: [
          %{name: "State 3", data: [empty("State 1"), empty("State 2"), cell("State 3", 2)]},
          %{
            name: "State 2",
            data: [
              cell("State 1", 1, @orange, "Row J"),
              cell("State 2", 3),
              cell("State 3", 1, @dark, "Row E")
            ]
          },
          %{
            name: "State 1",
            data: [cell("State 1", 3), cell("State 2", 1, @dark, "Row C"), empty("State 3")]
          }
        ],
        options: %{
          chart: %{width: 460, height: 300},
          data_labels: %{enabled: true, style: %{font_size: 14, font_weight: 700}},
          legend: %{show: false}
        }
      },
      %{
        id: "ht2",
        title: "Heatmap - rows top to bottom, x-axis on top",
        group: :heatmap,
        type: :heatmap,
        series:
          for {name, k} <- Enum.with_index(["Row A", "Row B", "Row C", "Row D", "Row E"]) do
            %{name: name, data: for(j <- 0..7, do: rem(j * 13 + k * 29, 70) + 20)}
          end,
        categories: for(j <- 1..8, do: "Item 0#{j}"),
        options: %{
          chart: %{width: 640, height: 320},
          data_labels: %{enabled: true},
          xaxis: %{position: :top},
          plot_options: %{
            heatmap: %{
              reverse_rows: true,
              color_scale: %{
                ranges: [
                  %{from: 0, to: 49, color: "#FF4560", name: "Below 50"},
                  %{from: 50, to: 74, color: "#FEB019", name: "50-74"},
                  %{from: 75, to: 100, color: "#00A100", name: "75-100"}
                ]
              }
            }
          }
        }
      },
      %{
        id: "ht3",
        title: "Heatmap - numeric x-axis on top, gradient legend",
        group: :heatmap,
        type: :heatmap,
        series:
          for {name, k} <- Enum.with_index(["Group 1", "Group 2", "Group 3"]) do
            %{name: name, data: for(h <- 0..23, do: %{x: h, y: rem(h * 5 + k * 17, 31) + 2})}
          end,
        options: %{
          chart: %{width: 640, height: 260},
          colors: ["#00A100"],
          xaxis: %{type: :numeric, position: :top},
          legend: %{gradient: %{position: :top}},
          plot_options: %{heatmap: %{reverse_rows: true}}
        }
      },
      %{
        id: "ht4",
        title: "Heatmap table - groups, summary row, marked columns",
        group: :heatmap,
        type: :heatmap,
        series: for({name, data} <- @table, do: %{name: name, data: data}),
        categories: @months,
        options: %{
          chart: %{width: 760, height: 500},
          data_labels: %{enabled: true, style: %{font_size: 13, font_weight: 400}},
          legend: %{position: :bottom},
          xaxis: %{
            position: :top,
            marked: ["05", "06", "07", "09", "10", "11"],
            marked_bar: %{name: "Marked column"}
          },
          plot_options: %{
            heatmap: %{
              reverse_rows: true,
              enable_shades: false,
              row_groups: [
                %{name: "Group 1", rows: 4},
                %{name: "Group 2", rows: 3},
                %{name: "Group 3", rows: 3}
              ],
              summary_rows: [%{name: "Summary row", data: column_means(@table)}],
              color_scale: %{ranges: @ranges}
            }
          }
        }
      },
      %{
        id: "ht5",
        title: "Heatmap table - many rows without data labels",
        group: :heatmap,
        type: :heatmap,
        series:
          for r <- 1..36 do
            %{
              name: "Item #{String.pad_leading("#{r}", 2, "0")}",
              data: for(j <- 1..24, do: rem(r * 37 + j * 11 + r * j, 93) + 8)
            }
          end,
        categories: for(j <- 1..24, do: String.pad_leading("#{j}", 2, "0")),
        options: %{
          chart: %{width: 760, height: 640},
          legend: %{position: :bottom},
          xaxis: %{position: :top, marked: ["06", "07", "18"]},
          plot_options: %{
            heatmap: %{
              reverse_rows: true,
              enable_shades: false,
              radius: 1,
              group_gap: 8,
              row_groups: for(g <- 1..4, do: %{name: "Group #{g}", rows: 9}),
              summary_rows: [
                %{name: "Summary row", data: for(j <- 1..24, do: 40 + rem(j * 7, 50))}
              ],
              color_scale: %{ranges: @ranges}
            }
          }
        }
      }
    ]
  end

  defp column_means(rows) do
    rows
    |> Enum.map(&elem(&1, 1))
    |> Enum.zip_with(&round(Enum.sum(&1) / length(&1)))
  end

  defp cell(x, y), do: %{x: x, y: y, fill_color: @grey}

  # A flagged cell: its own colour and a second, lighter label line.
  defp cell(x, y, color, note),
    do: %{x: x, y: y, fill_color: color, label: ["#{y}", [%{text: note, font_weight: 400}]]}

  # Nothing moved here: an outline cell with a dot.
  defp empty(x), do: %{x: x, y: 0, fill: %{type: :none}, stroke_color: "#d9d9d9", label: "·"}
end
