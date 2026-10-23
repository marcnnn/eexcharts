defmodule EexCharts.ScatterTest do
  use ExUnit.Case, async: true

  alias EexCharts.Charts.Scatter
  alias EexCharts.Renderer

  defp render(params),
    do: params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()

  defp markers(html), do: length(String.split(html, "eexcharts-marker")) - 1

  describe "scatter" do
    test "renders one marker per data point from [x, y] pairs" do
      html =
        render(%{
          id: "sc",
          type: :scatter,
          series: [%{name: "A", data: [[1, 10], [2, 20], [3, 15]]}]
        })

      assert html =~ "<svg"
      assert markers(html) == 3
      # default scatter marker size is 6
      assert html =~ ~s(r="6")
    end

    test "accepts a plain list of y values" do
      html = render(%{id: "sc2", type: :scatter, series: [%{name: "A", data: [10, 20, 15]}]})
      assert markers(html) == 3
    end

    test "on_click wires phx-click with index and series on every marker" do
      html =
        render(%{
          id: "sc-click",
          type: :scatter,
          series: [
            %{name: "A", data: [[1, 10], [2, 20]]},
            %{name: "B", data: [[3, 30]]}
          ],
          on_click: "pick"
        })

      assert html =~ ~s(phx-click="pick")
      assert html =~ ~s(cursor="pointer")

      # Both indexes, so a handler can map (series, index) back to an entity.
      assert html =~ ~s(phx-value-series="0")
      assert html =~ ~s(phx-value-index="1")
      assert html =~ ~s(phx-value-series="1")

      # Every marker is a target, not just the first of each series.
      assert length(Regex.scan(~r/phx-click="pick"/, html)) == 3
    end

    test "markers.discrete restyles single points only" do
      html =
        render(%{
          id: "sc-discrete",
          type: :scatter,
          series: [
            %{name: "A", data: [[1, 10], [2, 20]]},
            %{name: "B", data: [[3, 30]]}
          ],
          options: %{
            colors: ["#111111", "#222222"],
            markers: %{
              size: 8,
              stroke_width: 0,
              discrete: [
                %{
                  series_index: 0,
                  data_point_index: 1,
                  fill_color: "#ffffff",
                  stroke_color: "#111111",
                  stroke_width: 2
                }
              ]
            }
          }
        })

      [restyled] = Regex.scan(~r/<circle[^>]*eexcharts-marker-discrete[^>]*>/, html)
      assert hd(restyled) =~ ~s(fill="#ffffff")
      assert hd(restyled) =~ ~s(stroke="#111111")
      assert hd(restyled) =~ ~s(stroke-width="2")
      assert hd(restyled) =~ ~s(data-j="1")

      # The other two keep the series fill.
      assert length(Regex.scan(~r/fill="#111111"/, html)) >= 1
      assert length(Regex.scan(~r/fill="#222222"/, html)) >= 1
    end

    test "markers carry no click attributes without on_click" do
      html =
        render(%{id: "sc-noclick", type: :scatter, series: [%{name: "A", data: [[1, 10]]}]})

      refute html =~ "phx-click"
      refute html =~ ~s(cursor="pointer")
    end

    test "non-circle marker shapes are clickable too" do
      # Circles render as <circle>, everything else as <path>; the click attrs
      # are merged before Marker.render picks the element, so both carry them.
      html =
        render(%{
          id: "sc-shape",
          type: :scatter,
          series: [%{name: "A", data: [[1, 10]]}],
          options: %{markers: %{shape: :triangle}},
          on_click: "pick"
        })

      assert html =~ "<path"
      refute html =~ "<circle"
      assert html =~ ~s(phx-click="pick")
    end

    test "markers carry data-j for the tooltip hook" do
      html =
        render(%{id: "sc3", type: :scatter, series: [%{name: "A", data: [[1, 10], [2, 20]]}]})

      assert html =~ ~s(data-j="0")
      assert html =~ ~s(data-j="1")
    end

    test "no band hover-zones for a value x-axis" do
      html =
        render(%{id: "sc4", type: :scatter, series: [%{name: "A", data: [[1, 10], [2, 20]]}]})

      refute html =~ "eexcharts-zone"
    end

    test "data_range reads the y component" do
      assert Scatter.data_range([%{name: "A", data: [[1, 10], [2, 30], [3, 5]]}]) == {5, 30}
    end

    test "tooltip_value formats an x/y pair" do
      assert Scatter.tooltip_value(%{}, [1, 10]) == "1, 10"
    end
  end

  describe "bubble" do
    test "renders markers whose radius scales with z" do
      html =
        render(%{
          id: "bb",
          type: :bubble,
          series: [%{name: "A", data: [[1, 10, 5], [2, 20, 50], [3, 15, 25]]}]
        })

      assert markers(html) == 3
      # different z -> different radii
      radii =
        Regex.scan(~r/r="([0-9.]+)"/, html) |> Enum.map(&List.last/1) |> Enum.uniq()

      assert length(radii) > 1
    end

    test "respects min/max bubble radius clamps" do
      html =
        render(%{
          id: "bb2",
          type: :bubble,
          series: [%{name: "A", data: [[1, 10, 1], [2, 20, 1000]]}],
          options: %{plot_options: %{bubble: %{min_bubble_radius: 4, max_bubble_radius: 12}}}
        })

      radii =
        Regex.scan(~r/r="([0-9.]+)"/, html)
        |> Enum.map(fn [_, r] -> elem(Float.parse(r), 0) end)

      assert radii != []
      assert Enum.all?(radii, &(&1 >= 4 and &1 <= 12))
    end

    test "tooltip_value includes z for bubbles" do
      assert Scatter.tooltip_value(%{}, [1, 10, 5]) == "1, 10 (5)"
    end
  end
end
