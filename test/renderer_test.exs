defmodule EexCharts.RendererTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> IO.iodata_to_binary()
  end

  describe "line charts" do
    test "renders an svg with one path per series" do
      html =
        render(%{
          id: "t1",
          type: :line,
          series: [
            %{name: "A", data: [10, 20, 15, 30]},
            %{name: "B", data: [5, 15, 25, 10]}
          ],
          categories: ~w(a b c d)
        })

      assert html =~ ~s(id="t1")
      assert html =~ "<svg"
      assert html =~ ~s(phx-hook="EexCharts")
      assert html =~ "#008FFB"
      assert html =~ "#00E396"
      # both series lines present
      assert length(String.split(html, ~s(stroke-linejoin="round"))) >= 3
    end

    test "smooth curve emits cubic beziers" do
      html =
        render(%{
          id: "t2",
          type: :line,
          series: [%{name: "A", data: [1, 5, 2]}],
          options: %{stroke: %{curve: :smooth}}
        })

      assert html =~ " C "
    end

    test "nil values split the line into segments" do
      html =
        render(%{
          id: "t3",
          type: :line,
          series: [%{name: "A", data: [1, 2, nil, 4, 5]}]
        })

      # two segments -> two "M" line path starts (plus no crash)
      assert html =~ "<path"
    end

    test "escapes user-provided text" do
      html =
        render(%{
          id: "t4",
          type: :line,
          series: [%{name: "<script>alert(1)</script>", data: [1, 2]}],
          categories: ["<b>x</b>", "y"]
        })

      refute html =~ "<script>alert(1)</script>"
      assert html =~ "&lt;script&gt;"
      refute html =~ "<b>x</b>"
    end

    test "renders one tooltip per data point with all series rows" do
      html =
        render(%{
          id: "t5",
          type: :line,
          series: [%{name: "A", data: [1, 2, 3]}, %{name: "B", data: [4, 5, 6]}],
          categories: ~w(Jan Feb Mar)
        })

      assert length(String.split(html, ~s(class="eexcharts-tip" ))) == 4
      assert html =~ "Jan"
      assert html =~ "A: "
      assert html =~ "B: "
    end
  end

  describe "area charts" do
    test "renders gradient fills closed to the baseline" do
      html =
        render(%{
          id: "a1",
          type: :area,
          series: [%{name: "A", data: [10, 40, 25]}]
        })

      assert html =~ "linearGradient"
      assert html =~ "url(#a1-grad-0)"
      assert html =~ " Z"
    end
  end

  describe "bar charts" do
    test "renders one bar per value" do
      html =
        render(%{
          id: "b1",
          type: :bar,
          series: [%{name: "A", data: [10, 20, 30]}],
          categories: ~w(x y z)
        })

      assert length(String.split(html, ~s(class="eexcharts-bar"))) == 4
    end

    test "stacked bars and border radius render" do
      html =
        render(%{
          id: "b2",
          type: :bar,
          series: [%{name: "A", data: [10, 20]}, %{name: "B", data: [5, 8]}],
          options: %{chart: %{stacked: true}, plot_options: %{bar: %{border_radius: 4}}}
        })

      assert html =~ " A 4 4 "
    end

    test "horizontal bars swap the axes" do
      html =
        render(%{
          id: "b3",
          type: :bar,
          series: [%{name: "A", data: [400, 430]}],
          categories: ["South Korea", "Canada"],
          options: %{plot_options: %{bar: %{horizontal: true}}}
        })

      assert html =~ "South Korea"
      assert html =~ ~s(class="eexcharts-bar")
    end

    test "on_click adds phx-click bindings" do
      html =
        render(%{
          id: "b4",
          type: :bar,
          series: [%{name: "A", data: [1, 2]}],
          on_click: "bar-clicked"
        })

      assert html =~ ~s(phx-click="bar-clicked")
      assert html =~ ~s(phx-value-index="0")
    end
  end

  describe "pie and donut charts" do
    test "pie renders one slice per value with percentage labels" do
      html =
        render(%{
          id: "p1",
          type: :pie,
          series: [25, 25, 50],
          labels: ~w(A B C)
        })

      assert length(String.split(html, ~s(class="eexcharts-slice"))) == 4
      assert html =~ "25%"
      assert html =~ "50%"
      assert html =~ ~s(data-theme="dark")
    end

    test "donut renders inner arcs and center total" do
      html =
        render(%{
          id: "p2",
          type: :donut,
          series: [30, 70],
          labels: ~w(A B),
          options: %{
            plot_options: %{
              pie: %{donut: %{labels: %{show: true, total: %{show: true}}}}
            }
          }
        })

      assert html =~ "Total"
      assert html =~ "100"
    end

    test "handles a full-circle single slice" do
      html = render(%{id: "p3", type: :pie, series: [42], labels: ["only"]})
      assert html =~ ~s(class="eexcharts-slice")
    end

    test "zero total does not crash" do
      html = render(%{id: "p4", type: :pie, series: [0, 0], labels: ~w(A B)})
      assert html =~ "<svg"
    end
  end

  describe "edge cases" do
    test "empty series renders an empty chart" do
      html = render(%{id: "e1", type: :line, series: []})
      assert html =~ "<svg"
    end

    test "single data point" do
      html = render(%{id: "e2", type: :line, series: [%{name: "A", data: [5]}]})
      assert html =~ "<svg"
    end

    test "negative values render below the zero baseline" do
      html =
        render(%{
          id: "e3",
          type: :bar,
          series: [%{name: "A", data: [10, -5, 8]}]
        })

      assert html =~ ~s(class="eexcharts-bar")
    end

    test "bare number list becomes a single series" do
      html = render(%{id: "e4", type: :line, series: [1, 2, 3]})
      assert html =~ "series-1"
    end
  end
end
