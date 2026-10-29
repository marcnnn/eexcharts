defmodule Dev.ChartExamples.HeatmapTable do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @grey "#e8e8e8"
  @dark "#2a2018"
  @orange "#ff6105"

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
      }
    ]
  end

  defp cell(x, y), do: %{x: x, y: y, fill_color: @grey}

  # A flagged cell: its own colour and a second, lighter label line.
  defp cell(x, y, color, note),
    do: %{x: x, y: y, fill_color: color, label: ["#{y}", [%{text: note, font_weight: 400}]]}

  # Nothing moved here: an outline cell with a dot.
  defp empty(x), do: %{x: x, y: 0, fill: %{type: :none}, stroke_color: "#d9d9d9", label: "·"}
end
