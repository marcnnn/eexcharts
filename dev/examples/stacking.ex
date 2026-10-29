defmodule Dev.ChartExamples.Stacking do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

  def examples do
    [
      %{
        id: "sk1",
        title: "Stacked area (smooth)",
        group: :area,
        type: :area,
        series: [
          %{name: "South", data: [31, 40, 28, 51, 42, 60, 55, 70]},
          %{name: "North", data: [11, 32, 45, 32, 34, 52, 41, 38]},
          %{name: "Central", data: [15, 11, 32, 18, 9, 24, 30, 22]}
        ],
        categories: Enum.take(@months, 8),
        options: %{chart: %{stacked: true}, title: %{text: "Stacked area"}}
      },
      %{
        id: "sk2",
        title: "Stacked line with markers",
        group: :area,
        type: :line,
        series: [
          %{name: "Email", data: [120, 132, 101, 134, 90, 230, 210]},
          %{name: "Ads", data: [220, 182, 191, 234, 290, 330, 310]},
          %{name: "Video", data: [150, 232, 201, 154, 190, 330, 410]}
        ],
        categories: ~w(Mon Tue Wed Thu Fri Sat Sun),
        options: %{
          chart: %{stacked: true},
          stroke: %{curve: :straight, width: 3},
          markers: %{size: 4}
        }
      },
      %{
        id: "sk3",
        title: "100% stacked area",
        group: :area,
        type: :area,
        series: [
          %{name: "Coal", data: [44, 41, 38, 33, 30, 26, 22, 18]},
          %{name: "Gas", data: [22, 24, 25, 27, 28, 27, 26, 24]},
          %{name: "Wind", data: [5, 8, 11, 15, 19, 24, 29, 34]},
          %{name: "Solar", data: [1, 2, 4, 7, 10, 14, 19, 25]}
        ],
        categories: ~w(2017 2018 2019 2020 2021 2022 2023 2024),
        options: %{
          chart: %{stacked: true, stack_type: "100%"},
          fill: %{type: :solid, opacity: 0.8},
          stroke: %{width: 2}
        }
      },
      %{
        id: "sk4",
        title: "Stacked stepline area with a gap value",
        group: :area,
        type: :area,
        series: [
          %{name: "Queued", data: [4, 6, 6, 9, nil, 7, 5, 8]},
          %{name: "Running", data: [3, 3, 5, 4, 6, 8, 7, 4]}
        ],
        options: %{
          chart: %{stacked: true},
          stroke: %{curve: :stepline, width: 2},
          fill: %{type: :solid, opacity: 0.4}
        }
      },
      %{
        id: "sk5",
        title: "100% stacked line (smooth)",
        group: :area,
        type: :line,
        series: [
          %{name: "Chrome", data: [52, 58, 61, 63, 64, 65]},
          %{name: "Safari", data: [18, 19, 19, 20, 19, 18]},
          %{name: "Other", data: [30, 23, 20, 17, 17, 17]}
        ],
        categories: ~w(2019 2020 2021 2022 2023 2024),
        options: %{
          chart: %{stacked: true, stack_type: "100%"},
          stroke: %{curve: :smooth, width: 3}
        }
      },
      %{
        id: "sk6",
        title: "Streamgraph (wiggle, inside-out order)",
        group: :streamgraph,
        type: :streamgraph,
        series: stream_series(),
        categories: @months,
        options: %{
          title: %{text: "Listening by genre"},
          plot_options: %{streamgraph: %{order: :inside_out}}
        }
      },
      %{
        id: "sk7",
        title: "Streamgraph (silhouette)",
        group: :streamgraph,
        type: :streamgraph,
        series: stream_series(),
        categories: @months,
        options: %{plot_options: %{streamgraph: %{offset: :silhouette}}}
      }
    ]
  end

  # Gaussian bumps peaking at different months, so the layers swell and fade
  # in turn. Rounded to one decimal to keep the goldens readable.
  defp stream_series do
    [
      {"Rock", 2.0, 30, 3.0},
      {"Pop", 5.0, 42, 2.5},
      {"Jazz", 8.5, 18, 2.0},
      {"Electronic", 10.0, 36, 2.2},
      {"Hip-hop", 6.5, 28, 1.8}
    ]
    |> Enum.map(fn {name, peak, height, width} ->
      data =
        Enum.map(0..11, fn m ->
          Float.round(4 + height * :math.exp(-:math.pow((m - peak) / width, 2)), 1)
        end)

      %{name: name, data: data}
    end)
  end
end
