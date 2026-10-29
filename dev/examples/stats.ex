defmodule Dev.ChartExamples.Stats do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.
  #
  # Samples come from `sample/4`: an integer hash turned into roughly normal
  # values (Irwin-Hall, the sum of four uniforms) and rounded to one decimal.
  # Integer arithmetic keeps them bit-identical on every platform, which a
  # `sin`-based hash would not.

  import Bitwise

  def examples do
    [
      %{
        id: "st1",
        title: "Histogram (automatic bins)",
        group: :histogram,
        type: :histogram,
        series: [%{name: "Response time", data: sample(240, 120, 18, 1)}],
        options: %{xaxis: %{title: %{text: "Response time (ms)"}}}
      },
      %{
        id: "st2",
        title: "Overlaid histograms (bin width, probability)",
        group: :histogram,
        type: :histogram,
        series: [
          %{name: "Before", data: sample(300, 62, 9, 2)},
          %{name: "After", data: sample(300, 48, 7, 3)}
        ],
        options: %{
          plot_options: %{histogram: %{bin_width: 5, normalize: :probability}},
          yaxis: %{decimals_in_float: 2}
        }
      },
      %{
        id: "st3",
        title: "Cumulative histogram (percent, outlined)",
        group: :histogram,
        type: :histogram,
        series: [%{name: "Orders", data: sample(180, 35, 11, 4)}],
        options: %{
          plot_options: %{histogram: %{bins: :sturges, normalize: :percent, cumulative: true}},
          stroke: %{width: 1, colors: ["#fff"]},
          yaxis: %{max: 100}
        }
      },
      %{
        id: "st4",
        title: "Density histogram (fixed bin count)",
        group: :histogram,
        type: :histogram,
        series: [%{name: "Height", data: sample(200, 171, 8, 5) ++ sample(120, 158, 6, 6)}],
        options: %{
          plot_options: %{histogram: %{bins: 16, normalize: :density}},
          stroke: %{width: 1, colors: ["#fff"]},
          yaxis: %{decimals_in_float: 3}
        }
      },
      %{
        id: "st5",
        title: "Violin (inner box)",
        group: :violin,
        type: :violin,
        series: [
          %{
            name: "Score",
            data: [
              %{x: "Control", y: sample(80, 55, 10, 7)},
              %{x: "Variant A", y: sample(80, 63, 7, 8)},
              %{x: "Variant B", y: sample(50, 48, 6, 9) ++ sample(40, 70, 5, 10)}
            ]
          }
        ]
      },
      %{
        id: "st6",
        title: "Grouped violins (median line, count scale)",
        group: :violin,
        type: :violin,
        series: [
          %{
            name: "2024",
            data: [sample(60, 30, 5, 11), sample(90, 38, 6, 12), sample(40, 45, 8, 13)]
          },
          %{
            name: "2025",
            data: [sample(70, 33, 4, 14), sample(60, 41, 7, 15), sample(80, 50, 6, 16)]
          }
        ],
        categories: ~w(North Central South),
        options: %{plot_options: %{violin: %{inner: :median, scale: :count}}}
      },
      %{
        id: "st7",
        title: "Raincloud",
        group: :violin,
        type: :violin,
        series: [
          %{
            name: "Reaction time",
            data: [
              %{x: "Rested", y: sample(60, 310, 30, 17)},
              %{x: "Tired", y: sample(60, 360, 45, 18)},
              %{x: "Caffeine", y: sample(60, 295, 25, 19)}
            ]
          }
        ],
        options: %{plot_options: %{violin: %{raincloud: true}}}
      },
      %{
        id: "st8",
        title: "Box plot from raw observations",
        group: :box_plot,
        type: :box_plot,
        series: [
          %{
            name: "Latency",
            data: [
              %{x: "eu-west", observations: sample(60, 42, 6, 20) ++ [71.0, 75.5, 18.0]},
              %{x: "us-east", observations: sample(60, 55, 9, 21) ++ [92.0]},
              %{x: "ap-south", observations: sample(60, 68, 12, 22)},
              %{x: "sa-east", observations: sample(60, 50, 5, 23) ++ [27.0, 80.0]}
            ]
          }
        ],
        categories: ~w(eu-west us-east ap-south sa-east)
      }
    ]
  end

  # `n` roughly normal values with mean `mu` and standard deviation `sd`.
  defp sample(n, mu, sd, seed) do
    Enum.map(0..(n - 1), fn i ->
      u = Enum.sum(for k <- 0..3, do: uniform(seed * 100_003 + i * 4 + k))
      # Irwin-Hall(4): mean 2, variance 4/12.
      Float.round(mu + sd * (u - 2) / 0.5773502691896258, 1)
    end)
  end

  # MurmurHash3 finalizer: a well-mixed integer in [0, 2^32), scaled to [0, 1).
  defp uniform(i) do
    h = (i + 1) * 0x9E3779B1 &&& 0xFFFFFFFF
    h = bxor(h, h >>> 16) * 0x85EBCA6B &&& 0xFFFFFFFF
    h = bxor(h, h >>> 13) * 0xC2B2AE35 &&& 0xFFFFFFFF
    bxor(h, h >>> 16) / 0x100000000
  end
end
