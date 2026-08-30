defmodule EexCharts.HeatmapTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  defp base_params(extra \\ %{}) do
    Map.merge(
      %{
        id: "hm",
        type: :heatmap,
        series: [
          %{name: "R1", data: [0, 15, 30]},
          %{name: "R2", data: [30, 0, 15]}
        ],
        categories: ~w(Mon Tue Wed)
      },
      extra
    )
  end

  test "renders an svg container with the hook and per-cell rects" do
    html = render(base_params())

    assert html =~ ~s(id="hm")
    assert html =~ "<svg"
    assert html =~ ~s(phx-hook="EexCharts")
    assert html =~ "eexcharts-heatmap-rect"

    # 2 series x 3 categories = 6 cells
    assert length(String.split(html, "eexcharts-heatmap-rect")) == 7
  end

  test "cells carry composite series-cell data-j keys" do
    html = render(base_params())

    # series 0 (R1), cells 0..2 and series 1 (R2), cells 0..2
    assert html =~ ~s(data-j="0-0")
    assert html =~ ~s(data-j="0-2")
    assert html =~ ~s(data-j="1-0")
    assert html =~ ~s(data-j="1-2")
  end

  test "shade intensity normalizes against the global value range" do
    # global min=0, max=30, total=30. value 30 -> percent 100 -> shade 0 -> pure
    # base color; value 0 -> percent 0 -> shade 1 -> white.
    html = render(base_params())

    assert html =~ "#008FFB"
    assert String.downcase(html) =~ "#ffffff"
  end

  test "distinct series use distinct base hues" do
    html = render(base_params())
    # second series base color from the default palette
    assert html =~ "#00E396"
  end

  test "renders per-cell tooltips with category, series name and value" do
    html = render(base_params())

    assert html =~ "eexcharts-tip"
    # one tip per cell (6) sharing the composite key
    assert html =~ ~s(data-j="1-2")
    assert html =~ "Wed"
    assert html =~ "R2"
  end

  test "data labels appear inside cells when enabled" do
    html =
      render(base_params(%{options: %{data_labels: %{enabled: true}}}))

    assert html =~ "eexcharts-datalabel"
    assert html =~ ">30<"
  end

  test "color_scale ranges drive cell color and legend items" do
    html =
      render(
        base_params(%{
          options: %{
            plot_options: %{
              heatmap: %{
                color_scale: %{
                  ranges: [
                    %{from: 0, to: 10, color: "#00FF00", name: "low"},
                    %{from: 11, to: 30, color: "#FF0000", name: "high"}
                  ]
                }
              }
            }
          }
        })
      )

    # legend renders one swatch per range with its name
    assert html =~ "low"
    assert html =~ "high"
    assert html =~ "eexcharts-legend"
  end

  test "series names render as left axis labels by default" do
    html = render(base_params())

    assert html =~ "eexcharts-yaxis-labels"
    assert html =~ ">R1<"
    assert html =~ ">R2<"
  end

  test "category labels render along the bottom" do
    html = render(base_params())

    assert html =~ "eexcharts-xaxis-labels"
    assert html =~ ">Mon<"
  end

  test "on_click wires phx-click with cell index and series" do
    html = render(base_params(%{on_click: "cell_clicked"}))

    assert html =~ ~s(phx-click="cell_clicked")
    assert html =~ ~s(phx-value-index=)
    assert html =~ ~s(phx-value-series=)
  end

  test "escapes user-provided series and category text" do
    html =
      render(%{
        id: "hm-esc",
        type: :heatmap,
        series: [%{name: "<script>x</script>", data: [1, 2]}],
        categories: ["<b>a</b>", "b"]
      })

    refute html =~ "<script>x</script>"
    assert html =~ "&lt;script&gt;"
    refute html =~ "<b>a</b>"
  end

  test "hidden series are excluded and remaining colors stay stable" do
    html =
      render(base_params(%{hidden_series: [0]}))

    # only 3 cells remain (series 1)
    assert length(String.split(html, "eexcharts-heatmap-rect")) == 4
    # series 1 keeps its original palette color
    assert html =~ "#00E396"
  end

  test "handles negative values without crashing" do
    html =
      render(%{
        id: "hm-neg",
        type: :heatmap,
        series: [%{name: "R", data: [-10, 0, 20]}],
        categories: ~w(a b c)
      })

    assert html =~ "<svg"
    assert html =~ "eexcharts-heatmap-rect"
  end

  test "tolerates ragged/nil data (no cell for nil)" do
    html =
      render(%{
        id: "hm-ragged",
        type: :heatmap,
        series: [
          %{name: "R1", data: [1, nil, 3]},
          %{name: "R2", data: [4, 5]}
        ],
        categories: ~w(a b c)
      })

    # R1 has 2 cells (nil dropped), R2 has 2 cells = 4 total
    assert length(String.split(html, "eexcharts-heatmap-rect")) == 5
  end
end
