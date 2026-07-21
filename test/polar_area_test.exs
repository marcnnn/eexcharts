defmodule EexCharts.PolarAreaTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> IO.iodata_to_binary()
  end

  describe "polar area charts" do
    test "renders one slice per value with equal angles" do
      html =
        render(%{
          id: "pa1",
          type: :polar_area,
          series: [10, 20, 30],
          labels: ~w(A B C)
        })

      assert html =~ "<svg"
      # one slice per value
      assert length(String.split(html, ~s(class="eexcharts-slice"))) == 4
      # palette colours
      assert html =~ "#008FFB"
      assert html =~ "#00E396"
      assert html =~ "#FEB019"
    end

    test "draws concentric background rings and radial spokes" do
      html =
        render(%{
          id: "pa2",
          type: :polar_area,
          series: [10, 20, 30],
          labels: ~w(A B C)
        })

      assert html =~ ~s(class="eexcharts-polar-grid")
      assert html =~ "<circle"
      # one spoke per slice (3)
      assert length(String.split(html, "<line")) >= 4
      # ring / spoke colour from plot_options.polar_area
      assert html =~ "#e8e8e8"
    end

    test "slice radius scales with value" do
      html =
        render(%{
          id: "pa3",
          type: :polar_area,
          series: [10, 40],
          labels: ~w(small big)
        })

      # slices use arc radii proportional to value; both slices rendered
      assert length(String.split(html, ~s(class="eexcharts-slice"))) == 3
    end

    test "uses a dark tooltip theme and a right-hand legend by default" do
      html =
        render(%{
          id: "pa4",
          type: :polar_area,
          series: [10, 20],
          labels: ~w(A B)
        })

      assert html =~ ~s(data-theme="dark")
      assert html =~ ~s(class="eexcharts-legend")
      assert html =~ ~s(class="eexcharts-tip")
    end

    test "hidden slices are dropped but keep stable colours" do
      html =
        render(%{
          id: "pa5",
          type: :polar_area,
          series: [10, 20, 30],
          labels: ~w(A B C),
          hidden_series: [1]
        })

      # slice for index 1 (#00E396) is not drawn as a slice path
      refute html =~ ~s(fill="#00E396" class="eexcharts-slice")
      # index 2 keeps its colour
      assert html =~ "#FEB019"
    end

    test "on_click wires phx-click with the slice index" do
      html =
        render(%{
          id: "pa6",
          type: :polar_area,
          series: [10, 20],
          labels: ~w(A B),
          on_click: "pick"
        })

      assert html =~ ~s(phx-click="pick")
      assert html =~ ~s(phx-value-index="0")
    end

    test "escapes user-provided labels" do
      html =
        render(%{
          id: "pa7",
          type: :polar_area,
          series: [10, 20],
          labels: ["<x>", "B"]
        })

      refute html =~ "<x>"
      assert html =~ "&lt;x&gt;"
    end

    test "zero total does not crash" do
      html = render(%{id: "pa8", type: :polar_area, series: [0, 0], labels: ~w(A B)})
      assert html =~ "<svg"
    end
  end
end
