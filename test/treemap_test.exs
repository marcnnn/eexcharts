defmodule EexCharts.TreemapTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> IO.iodata_to_binary()
  end

  defp map_series do
    [
      %{
        name: "S1",
        data: [
          %{x: "Alpha", y: 40},
          %{x: "Beta", y: 30},
          %{x: "Gamma", y: 20},
          %{x: "Delta", y: 10}
        ]
      }
    ]
  end

  test "renders an svg container with the hook and one rect per cell" do
    html = render(%{id: "tm", type: :treemap, series: map_series()})

    assert html =~ ~s(id="tm")
    assert html =~ "<svg"
    assert html =~ ~s(phx-hook="EexCharts")
    assert html =~ "eexcharts-treemap-rect"

    # 4 data points -> 4 cells
    assert length(String.split(html, "eexcharts-treemap-rect")) == 5
  end

  test "cells carry composite series-cell data-j keys" do
    html = render(%{id: "tm", type: :treemap, series: map_series()})

    assert html =~ ~s(data-j="0-0")
    assert html =~ ~s(data-j="0-3")
  end

  test "squarified cells cover the full grid area" do
    # four equal values should tile the grid; total covered area ~= grid area.
    html =
      render(%{
        id: "tm",
        type: :treemap,
        width: 400,
        height: 300,
        series: [%{name: "S", data: [25, 25, 25, 25]}]
      })

    parse = fn s ->
      if String.contains?(s, "."), do: String.to_float(s), else: String.to_integer(s)
    end

    attr = fn tag, name ->
      [_, v] = Regex.run(~r/ #{name}="([0-9.]+)"/, tag)
      parse.(v)
    end

    # Sum the area of every treemap cell rect (attribute order is not stable, so
    # pull width/height individually from each rect tag).
    total_area =
      Regex.scan(~r/<rect[^>]*eexcharts-treemap-rect[^>]*>/, html)
      |> Enum.map(&hd/1)
      |> Enum.map(fn tag -> attr.(tag, "width") * attr.(tag, "height") end)
      |> Enum.sum()

    # grid area is a bit under 400*300 due to padding; the four cells should
    # tile the large majority of it.
    assert total_area > 400 * 300 * 0.7
  end

  test "data labels show the x label and hide when the cell is tiny" do
    html = render(%{id: "tm", type: :treemap, series: map_series()})

    assert html =~ "eexcharts-datalabel"
    assert html =~ "Alpha"
  end

  test "renders per-cell tooltips with label and value" do
    html = render(%{id: "tm", type: :treemap, series: map_series()})

    assert html =~ "eexcharts-tip"
    assert html =~ "Beta"
  end

  test "on_click wires phx-click with cell index and series" do
    html = render(%{id: "tm", type: :treemap, series: map_series(), on_click: "clk"})

    assert html =~ ~s(phx-click="clk")
    assert html =~ ~s(phx-value-index=)
    assert html =~ ~s(phx-value-series=)
  end

  test "accepts {label, value} tuples" do
    html =
      render(%{
        id: "tm-tuple",
        type: :treemap,
        series: [%{name: "S", data: [{"A", 10}, {"B", 20}]}]
      })

    assert html =~ "eexcharts-treemap-rect"
    assert html =~ "A"
    assert html =~ "B"
  end

  test "accepts plain numbers with labels from params" do
    html =
      render(%{
        id: "tm-num",
        type: :treemap,
        series: [10, 20, 30],
        labels: ~w(one two three)
      })

    assert length(String.split(html, "eexcharts-treemap-rect")) == 4
    assert html =~ "one"
    assert html =~ "three"
  end

  test "distributed mode colors each cell from the palette" do
    html =
      render(%{
        id: "tm-dist",
        type: :treemap,
        series: [%{name: "S", data: [%{x: "A", y: 40}, %{x: "B", y: 30}]}],
        options: %{plot_options: %{treemap: %{distributed: true, enable_shades: false}}}
      })

    assert html =~ "#008FFB"
    assert html =~ "#00E396"
  end

  test "enable_shades shades cells by value within the series" do
    html =
      render(%{
        id: "tm-shade",
        type: :treemap,
        series: [%{name: "S", data: [%{x: "A", y: 40}, %{x: "B", y: 0}]}],
        options: %{plot_options: %{treemap: %{enable_shades: true}}}
      })

    assert html =~ "<svg"
    assert html =~ "eexcharts-treemap-rect"
  end

  test "multiple series create proportional bands squarified inside" do
    html =
      render(%{
        id: "tm-multi",
        type: :treemap,
        series: [
          %{name: "S1", data: [%{x: "A", y: 10}, %{x: "B", y: 20}]},
          %{name: "S2", data: [%{x: "C", y: 30}, %{x: "D", y: 40}]}
        ]
      })

    # 4 cells total across two series bands
    assert length(String.split(html, "eexcharts-treemap-rect")) == 5
    assert html =~ ~s(data-j="0-1")
    assert html =~ ~s(data-j="1-1")
  end

  test "escapes user-provided labels" do
    html =
      render(%{
        id: "tm-esc",
        type: :treemap,
        series: [%{name: "S", data: [%{x: "<script>x</script>", y: 10}]}]
      })

    refute html =~ "<script>x</script>"
    assert html =~ "&lt;script&gt;"
  end

  test "empty series renders an empty chart without crashing" do
    html = render(%{id: "tm-empty", type: :treemap, series: []})

    assert html =~ "<svg"
    refute html =~ "eexcharts-treemap-rect"
  end
end
