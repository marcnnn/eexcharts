defmodule EexCharts.BoxPlotTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  test "renders split lower/upper boxes per data point" do
    html =
      render(%{
        id: "bp1",
        type: :box_plot,
        series: [
          %{
            name: "box",
            data: [
              [54, 66, 69, 75, 88],
              [43, 65, 69, 76, 81]
            ]
          }
        ],
        categories: ~w(a b)
      })

    assert html =~ "<svg"
    assert length(String.split(html, ~s(class="eexcharts-boxplot-lower"))) == 3
    assert length(String.split(html, ~s(class="eexcharts-boxplot-upper"))) == 3
  end

  test "uses configured lower and upper colors" do
    html =
      render(%{
        id: "bp2",
        type: :box_plot,
        series: [%{name: "box", data: [[40, 45, 52, 60, 65]]}]
      })

    # defaults: lower #008FFB, upper #00E396
    assert html =~ "#008FFB"
    assert html =~ "#00E396"
  end

  test "accepts %{x:, y:} map data with five numbers" do
    html =
      render(%{
        id: "bp3",
        type: :box_plot,
        series: [%{name: "box", data: [%{x: "Jan", y: [40, 45, 52, 60, 65]}]}],
        categories: ["Jan"]
      })

    assert html =~ ~s(class="eexcharts-boxplot-lower")
  end

  test "tooltip shows the five-number summary" do
    html =
      render(%{
        id: "bp4",
        type: :box_plot,
        series: [%{name: "box", data: [[40, 45, 52, 60, 65]]}],
        categories: ["Jan"]
      })

    assert html =~ "Min: 40 Q1: 45 Median: 52 Q3: 60 Max: 65"
  end

  test "tooltip respects y_formatter" do
    html =
      render(%{
        id: "bp5",
        type: :box_plot,
        series: [%{name: "box", data: [[40, 45, 52, 60, 65]]}],
        categories: ["Jan"],
        options: %{tooltip: %{y_formatter: fn v -> "#{v}k" end}}
      })

    assert html =~ "Min: 40k Q1: 45k Median: 52k Q3: 60k Max: 65k"
  end

  test "default stroke color is applied" do
    html =
      render(%{
        id: "bp6",
        type: :box_plot,
        series: [%{name: "box", data: [[40, 45, 52, 60, 65]]}]
      })

    assert html =~ "#24292e"
  end

  test "nil points are skipped" do
    html =
      render(%{
        id: "bp7",
        type: :box_plot,
        series: [%{name: "box", data: [[40, 45, 52, 60, 65], nil]}],
        categories: ~w(a b)
      })

    assert length(String.split(html, ~s(class="eexcharts-boxplot-lower"))) == 2
  end
end
