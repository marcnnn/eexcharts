defmodule Dev.ChartExamples.LevelMeter do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @columns ~w(North East South West Up Down)

  @levels [
    {"Row A", [3, 2, 4, 4, 4, 4]},
    {"Row B", [3, 3, 4, 3, 3, 4]},
    {"Row C", [2, 3, 3, 3, 3, 3]},
    {"Row D", [2, 2, 3, 3, 2, 2]},
    {"Row E", [2, 2, 2, 2, 3, 2]}
  ]

  def examples do
    [
      %{
        id: "lm1",
        title: "Level matrix with target and average row",
        group: :level_meter,
        type: :level_meter,
        series: matrix_series(),
        categories: @columns,
        width: 820,
        height: 340,
        options: %{
          plot_options: %{
            level_meter: %{
              target: 3,
              value_label: %{formatter: &__MODULE__.level/1}
            }
          }
        }
      },
      %{
        id: "lm2",
        title: "Level list with previous values",
        group: :level_meter,
        type: :level_meter,
        series: [
          %{
            name: "Level",
            data: [
              %{x: "Item 01", y: 3, previous: 2},
              %{x: "Item 02", y: 4, previous: 3},
              %{x: "Item 03", y: 2, previous: 4},
              %{x: "Item 04", y: 3.5, previous: 3},
              %{x: "Item 05", y: 1}
            ]
          }
        ],
        width: 420,
        height: 260,
        options: %{
          title: %{text: "Since last review"},
          plot_options: %{
            level_meter: %{
              target: 3,
              gained_color: "#858587",
              value_label: %{formatter: &__MODULE__.level/1}
            }
          }
        }
      },
      %{
        id: "lm3",
        title: "Fractional means, distributed colours",
        group: :level_meter,
        type: :level_meter,
        series: [
          %{name: "North", data: [%{x: "Q1", y: 2.4}, %{x: "Q2", y: 3.2}, %{x: "Q3", y: 4.7}]},
          %{name: "South", data: [%{x: "Q1", y: 1.5}, %{x: "Q2", y: 2.9}, %{x: "Q3", y: 3.0}]},
          %{
            name: "East",
            data: [
              %{x: "Q1", y: 0.6},
              %{x: "Q2", y: 4.1, fill_color: "#775DD0"},
              %{x: "Q3", y: nil}
            ]
          }
        ],
        width: 560,
        height: 220,
        options: %{
          plot_options: %{
            level_meter: %{segments: 6, distributed: true, radius: 0, gap: 2}
          }
        }
      }
    ]
  end

  # Whole levels read "L3"; the average row keeps its decimal.
  def level(v) when is_integer(v), do: "L#{v}"
  def level(v), do: :erlang.float_to_binary(v / 1, decimals: 1)

  defp matrix_series do
    rows = Enum.map(@levels, fn {name, values} -> %{name: name, data: values} end)

    average =
      @levels
      |> Enum.map(&elem(&1, 1))
      |> Enum.zip_with(fn col -> Float.round(Enum.sum(col) / length(col), 1) end)

    rows ++ [%{name: "Average", summary: true, data: average}]
  end
end
