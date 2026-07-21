defmodule EexCharts.RadialBarTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> IO.iodata_to_binary()
  end

  describe "radial bar charts" do
    test "renders a track and a stroked value arc per series" do
      html =
        render(%{
          id: "rb1",
          type: :radial_bar,
          series: [70, 45],
          labels: ~w(A B)
        })

      assert html =~ "<svg"
      # one gray track per ring, one value arc per ring
      assert length(String.split(html, ~s(class="eexcharts-radialbar-track"))) == 3
      assert length(String.split(html, ~s(class="eexcharts-radialbar-arc"))) == 3

      # value arcs are stroked (no fill), coloured by the palette
      assert html =~ ~s(fill="none")
      assert html =~ "#008FFB"
      assert html =~ "#00E396"
      # track colour
      assert html =~ "#f2f2f2"
    end

    test "arcs carry data-j for tooltip matching by original index" do
      html = render(%{id: "rb2", type: :radial_bar, series: [50, 25, 80]})

      assert html =~ ~s(data-j="0")
      assert html =~ ~s(data-j="1")
      assert html =~ ~s(data-j="2")
    end

    test "a single series renders centre name and value labels" do
      html =
        render(%{
          id: "rb3",
          type: :radial_bar,
          series: [%{name: "Progress", data: [67]}]
        })

      assert html =~ "Progress"
      assert html =~ "67%"
      assert html =~ ~s(class="eexcharts-radialbar-value")
    end

    test "values above 100 are clamped to a full sweep" do
      html = render(%{id: "rb4", type: :radial_bar, series: [150]})
      # no crash, arc still rendered
      assert html =~ ~s(class="eexcharts-radialbar-arc")
    end

    test "tooltip and legend are disabled by default" do
      html = render(%{id: "rb5", type: :radial_bar, series: [40, 60], labels: ~w(A B)})

      refute html =~ ~s(class="eexcharts-tooltip")
      refute html =~ ~s(class="eexcharts-legend")
    end

    test "legend renders when the user enables it" do
      html =
        render(%{
          id: "rb6",
          type: :radial_bar,
          series: [40, 60],
          labels: ~w(Alpha Beta),
          on_legend_click: "toggle",
          options: %{legend: %{show: true}}
        })

      assert html =~ ~s(class="eexcharts-legend")
      assert html =~ "Alpha"
      assert html =~ "Beta"
      assert html =~ ~s(phx-click="toggle")
    end

    test "tooltip renders when enabled" do
      html =
        render(%{
          id: "rb7",
          type: :radial_bar,
          series: [%{name: "Done", data: [88]}],
          options: %{tooltip: %{enabled: true}}
        })

      assert html =~ ~s(class="eexcharts-tooltip")
      assert html =~ ~s(class="eexcharts-tip")
      assert html =~ "88%"
    end

    test "on_click wires phx-click with index and series" do
      html =
        render(%{
          id: "rb8",
          type: :radial_bar,
          series: [30, 70],
          on_click: "pick"
        })

      assert html =~ ~s(phx-click="pick")
      assert html =~ ~s(phx-value-index="0")
      assert html =~ ~s(phx-value-series="1")
      assert html =~ ~s(cursor="pointer")
    end

    test "hidden series are dropped from drawing but keep stable colours" do
      html =
        render(%{
          id: "rb9",
          type: :radial_bar,
          series: [10, 20, 30],
          hidden_series: [1]
        })

      # ring 1 (colour #00E396) is not drawn, ring 2 keeps #FEB019
      refute html =~ ~s(data-j="1")
      assert html =~ ~s(data-j="0")
      assert html =~ ~s(data-j="2")
      assert html =~ "#FEB019"
      refute html =~ "#00E396"
    end

    test "escapes user-provided labels" do
      html =
        render(%{
          id: "rb10",
          type: :radial_bar,
          series: [%{name: "<script>", data: [50]}]
        })

      refute html =~ "<script>"
      assert html =~ "&lt;script&gt;"
    end
  end
end
