defmodule Dev.ChartExamples.Sparkline do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  @values [9, 3, 20, 22, 28, 30, 27, 28, 30, 29, 24, 19, 23, 13, 26, 30]
  @flags [:low, :low, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :ok, :mid, :ok, :ok, :low, :ok, :ok]
  @flag_colors %{ok: "#008FFB", mid: "#A5978B", low: "#FF4560"}

  def examples do
    [
      %{
        id: "sp1",
        title: "Sparkline columns, one colour per point (distributed)",
        group: :bar,
        type: :bar,
        series: [%{name: "Series 1", data: @values}],
        width: 160,
        height: 24,
        options: %{
          chart: %{sparkline: %{enabled: true}},
          plot_options: %{bar: %{distributed: true}},
          colors: Enum.map(@flags, &@flag_colors[&1])
        }
      },
      %{
        id: "sp2",
        title: "Sparkline columns with per-point fill_color",
        group: :bar,
        type: :bar,
        series: [
          %{
            name: "Series 1",
            data:
              @values
              |> Enum.zip(@flags)
              |> Enum.with_index(1)
              |> Enum.map(fn
                {{v, :ok}, i} -> %{x: item(i), y: v}
                {{v, flag}, i} -> %{x: item(i), y: v, fill_color: @flag_colors[flag]}
              end)
          }
        ],
        width: 120,
        height: 32,
        options: %{
          chart: %{sparkline: %{enabled: true}},
          # The nice scale would top out at 40; let the tallest bar fill.
          yaxis: %{max: 30}
        }
      },
      %{
        id: "sp3",
        title: "Sparkline line with a reference line and values below the points",
        group: :line,
        type: :line,
        series: [%{name: "Series 1", data: [58, 67, 75]}],
        categories: ["Jan", "Feb", "Mar"],
        width: 480,
        height: 110,
        options: %{
          chart: %{sparkline: %{enabled: true}},
          stroke: %{width: 2},
          markers: %{size: 4, stroke_width: 0},
          # Room for the annotation label above and the values below.
          grid: %{padding: %{top: 24, bottom: 30}},
          yaxis: %{min: 50, max: 80},
          annotations: %{
            yaxis: [
              %{
                y: 80,
                stroke_dash_array: 4,
                # Plain text, no pill: the label sits on the page.
                label: %{
                  text: "Reference 80",
                  text_anchor: :end,
                  position: :right,
                  border_width: 0,
                  style: %{background: "transparent", font_size: 12}
                }
              }
            ]
          },
          data_labels: %{
            enabled: true,
            background: %{enabled: false},
            style: %{font_weight: 400},
            formatter: &__MODULE__.month_value/2,
            # Below the point; the outer labels move inwards so they end at
            # the plot edge instead of being cut in half.
            offset_y: 24,
            offset_x: &__MODULE__.edge_inset/2
          }
        }
      },
      %{
        id: "sp4",
        title: "Area sparkline",
        group: :area,
        type: :area,
        series: [%{name: "Series 1", data: [12, 14, 9, 17, 21, 18, 24, 22, 27, 25, 31, 29]}],
        width: 160,
        height: 32,
        options: %{chart: %{sparkline: %{enabled: true}}, stroke: %{width: 2}}
      },
      %{
        id: "sp5",
        title: "Radial bar sparkline",
        group: :radial_bar,
        type: :radial_bar,
        series: [68],
        labels: ["Series 1"],
        width: 48,
        height: 48,
        options: %{
          chart: %{sparkline: %{enabled: true}},
          plot_options: %{
            radial_bar: %{hollow: %{size: "45%"}, data_labels: %{show: false}}
          }
        }
      }
    ]
  end

  @doc false
  def month_value(v, %{data_point_index: j}), do: "#{Enum.at(["Jan", "Feb", "Mar"], j)} · #{v}"

  # Moves the first and last label inwards by about half its width.
  @doc false
  def edge_inset(_v, %{data_point_index: 0}), do: 24
  def edge_inset(_v, %{data_point_index: 2}), do: -24
  def edge_inset(_v, _ctx), do: 0

  defp item(i), do: "Item " <> String.pad_leading(Integer.to_string(i), 2, "0")
end
