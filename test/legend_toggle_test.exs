defmodule EexCharts.LegendToggleTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> IO.iodata_to_binary()
  end

  @series [
    %{name: "Alpha", data: [10, 20, 30]},
    %{name: "Beta", data: [40, 50, 60]},
    %{name: "Gamma", data: [70, 80, 90]}
  ]

  test "on_legend_click adds phx-click with the series index" do
    html =
      render(%{
        id: "lg1",
        type: :line,
        series: @series,
        on_legend_click: "toggle-series"
      })

    assert html =~ ~s(phx-click="toggle-series")
    assert html =~ ~s(phx-value-series="2")
    assert html =~ ~s(class="eexcharts-legend-item")
  end

  test "hidden_series removes the series from the chart but keeps its legend item dimmed" do
    html =
      render(%{
        id: "lg2",
        type: :line,
        series: @series,
        hidden_series: [1],
        on_legend_click: "toggle-series"
      })

    # Legend still lists all three names, the hidden one dimmed.
    assert html =~ "Alpha"
    assert html =~ "Beta"
    assert html =~ "Gamma"
    assert html =~ ~s(opacity="0.4")

    # Beta's values are gone from the tooltips.
    refute html =~ "Beta: "
    assert html =~ "Alpha: "
  end

  test "remaining series keep their original palette colors" do
    html =
      render(%{
        id: "lg3",
        type: :line,
        series: @series,
        hidden_series: [0]
      })

    # Series 1 (Beta) keeps green, series 2 (Gamma) keeps yellow —
    # blue (#008FFB) is only in the legend marker of the hidden series.
    assert html =~ ~s(stroke="#00E396")
    assert html =~ ~s(stroke="#FEB019")
    refute html =~ ~s(stroke="#008FFB")
  end

  test "hiding a series rescales the y axis" do
    with_gamma = render(%{id: "lg4", type: :line, series: @series})
    without_gamma = render(%{id: "lg5", type: :line, series: @series, hidden_series: [2]})

    # Gamma's 90 pushes the nice-scale max to 100; without it the max drops.
    assert with_gamma =~ ">100</text>"
    refute without_gamma =~ ">100</text>"
    assert without_gamma =~ ">60</text>"
  end

  test "pie slices can be hidden with stable colors and expanding remainder" do
    html =
      render(%{
        id: "lg6",
        type: :pie,
        series: [25, 25, 50],
        labels: ~w(A B C),
        hidden_series: [0]
      })

    # Slice B keeps green; percentages recompute over the visible total.
    assert html =~ ~s(fill="#00E396")
    assert html =~ "33.3%"
    assert html =~ "66.7%"
  end

  test "bar charts widen when a series is hidden" do
    all = render(%{id: "lg7", type: :bar, series: @series})
    one_hidden = render(%{id: "lg8", type: :bar, series: @series, hidden_series: [2]})

    count_bars = fn html -> length(String.split(html, ~s(class="eexcharts-bar"))) - 1 end
    assert count_bars.(all) == 9
    assert count_bars.(one_hidden) == 6
  end

  describe "html legend" do
    defp html_legend(extra \\ %{}) do
      render(
        Map.merge(
          %{
            id: "lgh",
            type: :line,
            series: @series,
            options: %{legend: %{html: true}}
          },
          extra
        )
      )
    end

    test "renders as HTML in a foreignObject instead of SVG text" do
      html = html_legend()

      assert html =~ ~s(<foreignObject)
      assert html =~ "eexcharts-legend--html"
      assert html =~ ~s(class="eexcharts-legend-marker")
      assert html =~ ~s(class="eexcharts-legend-text")
      # The browser lays the items out, so they must be flex children.
      assert html =~ "display:flex"
      # Without this the host page's line-height leaks in and the rows grow.
      assert html =~ "line-height:normal"
      refute html =~ ~s(class="eexcharts-legend-text" x=)
    end

    test "keeps the SVG legend's click and hidden-series semantics" do
      html = html_legend(%{on_legend_click: "toggle-series", hidden_series: [1]})

      assert html =~ ~s(phx-click="toggle-series")
      assert html =~ ~s(phx-value-series="2")
      assert html =~ "cursor:pointer"
      assert html =~ "opacity:0.4"
    end

    test "is off by default" do
      refute render(%{id: "lgs", type: :line, series: @series}) =~ "<foreignObject"
    end
  end
end
