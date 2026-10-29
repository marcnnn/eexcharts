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
