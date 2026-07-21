defmodule EexCharts.RangeBarTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> IO.iodata_to_binary()
  end

  test "renders one bar per range value" do
    html =
      render(%{
        id: "r1",
        type: :range_bar,
        series: [%{name: "range", data: [[1, 4], [3, 6], [2, 5]]}],
        categories: ~w(a b c)
      })

    assert html =~ "<svg"
    assert length(String.split(html, ~s(class="eexcharts-bar"))) == 4
  end

  test "accepts %{x:, y: [from, to]} map data" do
    html =
      render(%{
        id: "r2",
        type: :range_bar,
        series: [%{name: "range", data: [%{x: "Jan", y: [10, 40]}]}],
        categories: ["Jan"]
      })

    assert html =~ ~s(class="eexcharts-bar")
  end

  test "tooltip renders 'from – to'" do
    html =
      render(%{
        id: "r3",
        type: :range_bar,
        series: [%{name: "range", data: [[40, 65]]}],
        categories: ["Jan"]
      })

    assert html =~ "40 – 65"
  end

  test "tooltip respects y_formatter" do
    html =
      render(%{
        id: "r4",
        type: :range_bar,
        series: [%{name: "range", data: [[40, 65]]}],
        categories: ["Jan"],
        options: %{tooltip: %{y_formatter: fn v -> "$#{v}" end}}
      })

    assert html =~ "$40 – $65"
  end

  test "border_radius rounds the bar ends" do
    html =
      render(%{
        id: "r5",
        type: :range_bar,
        series: [%{name: "range", data: [[10, 40]]}],
        options: %{plot_options: %{bar: %{border_radius: 4}}}
      })

    assert html =~ " A 4 4 "
  end

  test "horizontal layout does not crash and keeps bars" do
    html =
      render(%{
        id: "r6",
        type: :range_bar,
        series: [%{name: "range", data: [[10, 40], [20, 55]]}],
        categories: ~w(a b),
        options: %{plot_options: %{bar: %{horizontal: true}}}
      })

    assert html =~ ~s(class="eexcharts-bar")
  end

  test "nil points are skipped" do
    html =
      render(%{
        id: "r7",
        type: :range_bar,
        series: [%{name: "range", data: [[10, 40], nil, [20, 55]]}],
        categories: ~w(a b c)
      })

    assert length(String.split(html, ~s(class="eexcharts-bar"))) == 3
  end

  test "on_click adds phx bindings" do
    html =
      render(%{
        id: "r8",
        type: :range_bar,
        series: [%{name: "range", data: [[10, 40]]}],
        on_click: "range-clicked"
      })

    assert html =~ ~s(phx-click="range-clicked")
    assert html =~ ~s(phx-value-index="0")
    assert html =~ ~s(phx-value-series="0")
  end
end
