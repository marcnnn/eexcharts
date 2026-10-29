defmodule EexCharts.HeatmapRowsAxisTest do
  use ExUnit.Case, async: true

  defp live(series, options, opts \\ []) do
    {:safe, io} = EexCharts.render("hr", :heatmap, series, [options: options] ++ opts)
    IO.iodata_to_binary(io)
  end

  defp tags(svg, tag), do: Regex.scan(~r/<#{tag}\b[^>]*>/, svg) |> List.flatten()

  defp attr(tag, name) do
    [_, v] = Regex.run(~r/\s#{name}="([^"]*)"/, tag)
    v
  end

  defp num(tag, name), do: tag |> attr(name) |> Float.parse() |> elem(0)

  defp rect_y(svg, key) do
    svg |> tags("rect") |> Enum.find(&(&1 =~ ~s(data-j="#{key}"))) |> num("y")
  end

  defp group(svg, class) do
    [g] = Regex.run(~r/<g class="#{class}">.*?<\/g>/s, svg)
    g
  end

  defp text_ys(svg, class), do: svg |> group(class) |> tags("text") |> Enum.map(&num(&1, "y"))

  defp grid_top(svg) do
    svg
    |> tags("rect")
    |> Enum.filter(&(&1 =~ "heatmap-rect"))
    |> Enum.map(&num(&1, "y"))
    |> Enum.min()
  end

  @series [
    %{name: "Row A", data: [1, 2, 3]},
    %{name: "Row B", data: [4, 5, 6]},
    %{name: "Row C", data: [7, 8, 9]}
  ]

  @cats [categories: ["Item 01", "Item 02", "Item 03"]]

  describe "reverse_rows" do
    test "default keeps ApexCharts' order: the first series is the bottom row" do
      svg = live(@series, %{}, @cats)

      assert rect_y(svg, "0-0") > rect_y(svg, "2-0")
    end

    test "true draws the first series on top, labels follow" do
      svg = live(@series, %{plot_options: %{heatmap: %{reverse_rows: true}}}, @cats)

      assert rect_y(svg, "0-0") < rect_y(svg, "1-0")
      assert rect_y(svg, "1-0") < rect_y(svg, "2-0")

      labels =
        svg |> group("eexcharts-yaxis-labels") |> then(&Regex.scan(~r/>([^<]+)<\/text>/, &1))

      assert Enum.map(labels, &List.last/1) == ["Row A", "Row B", "Row C"]

      [ya, yb, yc] = text_ys(svg, "eexcharts-yaxis-labels")
      assert ya < yb and yb < yc
      # Each label is centred on its row.
      row_h = rect_y(svg, "1-0") - rect_y(svg, "0-0")
      assert_in_delta ya, rect_y(svg, "0-0") + row_h / 2, 0.01
    end

    test "clicks and tooltips keep the series index of the row they sit on" do
      opts = %{plot_options: %{heatmap: %{reverse_rows: true}}}
      svg = live(@series, opts, @cats ++ [on_click: "cell"])

      top = svg |> tags("rect") |> Enum.min_by(&num(&1, "y"))
      assert attr(top, "phx-value-series") == "0"
      assert attr(top, "data-j") =~ ~r/^0-/
      assert svg =~ ~r/data-j="0-0" hidden.*?Row A/s
    end

    test "hidden series close the gap from the top" do
      opts = %{plot_options: %{heatmap: %{reverse_rows: true}}}
      svg = live(@series, opts, @cats ++ [hidden_series: [0]])

      assert rect_y(svg, "1-0") < rect_y(svg, "2-0")
      refute svg =~ ~s(data-j="0-0")
    end
  end

  describe "xaxis.position :top" do
    test "category labels sit above the plot and the bottom band is released" do
      bottom = live(@series, %{}, @cats)
      top = live(@series, %{xaxis: %{position: :top}}, @cats)

      assert Enum.all?(text_ys(top, "eexcharts-xaxis-labels"), &(&1 < grid_top(top)))
      assert Enum.all?(text_ys(bottom, "eexcharts-xaxis-labels"), &(&1 > grid_top(bottom)))

      # Same plot height either way: the axis band only moves.
      assert_in_delta grid_top(top) - grid_top(bottom), 24, 0.01
    end

    test "a top legend stays above the axis labels" do
      ranges = [%{from: 0, to: 5, color: "#FF4560"}, %{from: 6, to: 9, color: "#00A100"}]

      options = %{
        xaxis: %{position: :top},
        plot_options: %{heatmap: %{color_scale: %{ranges: ranges}}}
      }

      svg = live(@series, options, @cats)
      legend_ys = svg |> group("eexcharts-legend") |> tags("text") |> Enum.map(&num(&1, "y"))
      label_top = Enum.min(text_ys(svg, "eexcharts-xaxis-labels")) - 12

      assert Enum.max(legend_ys) < label_top
    end

    test "value-axis ticks hang from the top edge of the plot" do
      series = [%{name: "Row A", data: for(x <- 0..10, do: %{x: x, y: x})}]
      svg = live(series, %{xaxis: %{type: :numeric, position: :top}})

      top = grid_top(svg)
      ticks = svg |> group("eexcharts-xaxis-ticks") |> tags("line")

      assert ticks != []
      assert Enum.all?(ticks, &(num(&1, "y2") == top))
      assert Enum.all?(text_ys(svg, "eexcharts-xaxis-labels"), &(&1 < top - 6))
    end
  end

  describe "themes" do
    @opts %{xaxis: %{position: :top}, plot_options: %{heatmap: %{reverse_rows: true}}}

    test "dark: top labels use the dark fore colour" do
      svg = live(@series, Map.put(@opts, :theme, %{mode: :dark}), @cats)

      assert group(svg, "eexcharts-xaxis-labels") =~ ~s(fill="#f6f7f8")
    end

    test "daisy: top labels follow base-content live and resolve statically" do
      opts = Map.put(@opts, :theme, %{mode: :daisy})

      assert group(live(@series, opts, @cats), "eexcharts-xaxis-labels") =~
               "var(--color-base-content"

      static = EexCharts.to_svg("hr", :heatmap, @series, [options: opts] ++ @cats)
      refute static =~ "var("
      assert static =~ "Item 01"
    end
  end
end
