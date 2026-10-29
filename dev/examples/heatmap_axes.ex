defmodule Dev.ChartExamples.HeatmapAxes do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @day 86_400_000
  # 2024-01-01T00:00:00Z
  @t0 1_704_067_200_000

  def examples do
    [
      %{
        id: "hm1",
        title: "Heatmap - numeric x-axis with a gap",
        group: :heatmap,
        type: :heatmap,
        series:
          for {name, k} <- [{"North", 1}, {"East", 2}, {"South", 3}, {"West", 4}] do
            %{
              name: name,
              # Hours 0-23, but the sensors were offline from 09:00 to 11:00.
              data:
                for h <- 0..23, h not in 9..11 do
                  %{x: h, y: rem(h * 7 + k * 11, 40) + 5}
                end
            }
          end,
        options: %{
          xaxis: %{type: :numeric},
          data_labels: %{enabled: false}
        }
      },
      %{
        id: "hm2",
        title: "Heatmap - datetime x-axis, gradient legend",
        group: :heatmap,
        type: :heatmap,
        series:
          for {name, k} <- [{"api", 3}, {"web", 5}, {"worker", 7}] do
            %{
              name: name,
              # Eight weeks of daily load; day 20-26 is a missing week.
              data:
                for d <- 0..55, d not in 20..26 do
                  [@t0 + d * @day, rem(d * k + k * k, 23) * 4 + 8]
                end
            }
          end,
        options: %{
          colors: ["#00A100"],
          xaxis: %{type: :datetime},
          legend: %{gradient: true}
        }
      },
      %{
        id: "hm3",
        title: "Heatmap - vertical gradient legend, negative values",
        group: :heatmap,
        type: :heatmap,
        series:
          for {name, k} <- Enum.with_index(~w(2019 2020 2021 2022 2023)) do
            %{
              name: name,
              data: Enum.map(0..11, fn m -> rem(m * 5 + k * 4, 21) - 8 end)
            }
          end,
        categories: ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec),
        options: %{
          colors: ["#775DD0"],
          legend: %{gradient: %{position: :right}},
          data_labels: %{enabled: true}
        }
      },
      %{
        id: "hm4",
        title: "Heatmap - irregular numeric spacing, top gradient legend",
        group: :heatmap,
        type: :heatmap,
        series:
          for {name, k} <- [{"Low", 1}, {"Mid", 2}, {"High", 3}] do
            %{
              name: name,
              data: Enum.map([0, 1, 2, 3, 5, 7, 8, 9, 10, 14], fn x -> [x, x * k + 3 * k] end)
            }
          end,
        options: %{
          colors: ["#FF4560"],
          xaxis: %{type: :numeric},
          legend: %{gradient: %{position: :top, length: 240}}
        }
      }
    ]
  end
end
