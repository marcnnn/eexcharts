defmodule EexCharts.RadarTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  describe "radar charts" do
    test "renders a concentric polygon grid and spokes for the categories" do
      html =
        render(%{
          id: "rd1",
          type: :radar,
          series: [%{name: "S1", data: [80, 50, 30, 40, 100]}],
          categories: ~w(Jan Feb Mar Apr May)
        })

      assert html =~ "<svg"
      assert html =~ ~s(class="eexcharts-radar-grid")
      # grid polygons present
      assert html =~ "<polygon"
      # one spoke line per category (5)
      assert length(String.split(html, "<line")) >= 6
      # perimeter category labels
      assert html =~ "Jan"
      assert html =~ "May"
    end

    test "each series is a closed polygon with vertex markers" do
      html =
        render(%{
          id: "rd2",
          type: :radar,
          series: [
            %{name: "A", data: [10, 20, 30]},
            %{name: "B", data: [30, 20, 10]}
          ],
          categories: ~w(x y z)
        })

      assert html =~ ~s(class="eexcharts-radar-area")
      # path is closed
      assert html =~ " Z"
      # markers (size 5) per vertex
      assert html =~ ~s(class="eexcharts-marker")
      assert html =~ ~s(r="5")
      # both series colours
      assert html =~ "#008FFB"
      assert html =~ "#00E396"
      # faint fill
      assert html =~ ~s(fill-opacity="0.2")
    end

    test "tooltips are keyed per category and list visible series" do
      html =
        render(%{
          id: "rd3",
          type: :radar,
          series: [
            %{name: "S1", data: [80, 50]},
            %{name: "S2", data: [20, 30]}
          ],
          categories: ~w(One Two)
        })

      assert html =~ ~s(class="eexcharts-tip" data-j="0")
      assert html =~ ~s(class="eexcharts-tip" data-j="1")
      assert html =~ "One"
      assert html =~ "Two"
      # both series appear in a tooltip
      assert html =~ "S1"
      assert html =~ "S2"
    end

    test "markers carry data-j (category index) for tooltip matching" do
      html =
        render(%{
          id: "rd4",
          type: :radar,
          series: [%{name: "S1", data: [1, 2, 3, 4]}],
          categories: ~w(a b c d)
        })

      for j <- 0..3 do
        assert html =~ ~s(data-j="#{j}")
      end
    end

    test "hidden series are excluded but keep stable colours and a legend entry" do
      html =
        render(%{
          id: "rd5",
          type: :radar,
          series: [
            %{name: "S1", data: [10, 20, 30]},
            %{name: "S2", data: [30, 20, 10]}
          ],
          categories: ~w(x y z),
          hidden_series: [0],
          on_legend_click: "toggle"
        })

      # legend still lists both, hidden one dimmed
      assert html =~ "S1"
      assert html =~ "S2"
      assert html =~ ~s(opacity="0.4")
      # visible series (index 1) keeps its palette colour #00E396
      assert html =~ ~s(class="eexcharts-radar-area")
      assert html =~ "#00E396"
      assert html =~ ~s(phx-click="toggle")
    end

    test "on_click wires phx-click with index and series on markers" do
      html =
        render(%{
          id: "rd6",
          type: :radar,
          series: [%{name: "S1", data: [10, 20]}],
          categories: ~w(a b),
          on_click: "pick"
        })

      assert html =~ ~s(phx-click="pick")
      assert html =~ ~s(phx-value-index="1")
      assert html =~ ~s(phx-value-series="0")
    end

    test "falls back to xaxis categories and synthesises labels when missing" do
      html =
        render(%{
          id: "rd7",
          type: :radar,
          series: [%{name: "S1", data: [5, 10, 15]}]
        })

      # no categories supplied -> spokes still drawn, no crash
      assert html =~ ~s(class="eexcharts-radar-grid")
      assert html =~ ~s(class="eexcharts-radar-area")
    end

    test "escapes user-provided category text" do
      html =
        render(%{
          id: "rd8",
          type: :radar,
          series: [%{name: "S1", data: [1, 2]}],
          categories: ["<b>", "ok"]
        })

      refute html =~ "<b>ok"
      assert html =~ "&lt;b&gt;"
    end
  end
end
