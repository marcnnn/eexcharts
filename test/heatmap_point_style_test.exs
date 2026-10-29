defmodule EexCharts.HeatmapPointStyleTest do
  use ExUnit.Case, async: true

  defp live(series, options \\ %{}) do
    {:safe, io} = EexCharts.render("hp", :heatmap, series, options: options)
    IO.iodata_to_binary(io)
  end

  defp static(series, options), do: EexCharts.to_svg("hp", :heatmap, series, options: options)

  defp tags(svg, tag), do: Regex.scan(~r/<#{tag}\b[^>]*>/, svg) |> List.flatten()

  defp rects(svg), do: svg |> tags("rect") |> Enum.filter(&(&1 =~ "eexcharts-heatmap-rect"))

  defp rect(svg, key), do: svg |> rects() |> Enum.find(&(&1 =~ ~s(data-j="#{key}")))

  defp labels(svg) do
    Regex.scan(~r/<text[^>]*class="eexcharts-datalabel"[^>]*>.*?<\/text>/s, svg)
    |> List.flatten()
  end

  @labels %{data_labels: %{enabled: true}}

  @series [
    %{
      name: "Row A",
      data: [
        %{x: "State 1", y: 10},
        %{x: "State 2", y: 20, fill_color: "#ff6105"},
        %{x: "State 3", y: 30, stroke_color: "#111111"}
      ]
    },
    %{name: "Row B", data: [5, 15, 25]}
  ]

  describe "per-cell paint" do
    test "fill_color replaces the colour scale for that cell only" do
      svg = live(@series)

      assert rect(svg, "0-1") =~ ~s(fill="#ff6105")
      assert rect(svg, "0-1") =~ "eexcharts-point-styled"
      refute rect(svg, "0-0") =~ "#ff6105"
      refute rect(svg, "0-0") =~ "eexcharts-point-styled"
    end

    test "fill_color beats a matching colour range" do
      ranges = [%{from: 0, to: 100, color: "#00A100", name: "all"}]
      svg = live(@series, %{plot_options: %{heatmap: %{color_scale: %{ranges: ranges}}}})

      assert rect(svg, "0-1") =~ ~s(fill="#ff6105")
      assert rect(svg, "1-1") =~ ~s(fill="#)
      refute rect(svg, "1-1") =~ "#ff6105"
    end

    test "stroke_color replaces the separator for that cell" do
      svg = live(@series)

      assert rect(svg, "0-2") =~ ~s(stroke="#111111")
      assert rect(svg, "0-0") =~ ~s(stroke="#fff")
    end

    test "an outline cell has no fill and a stroke in its colour" do
      series = [%{name: "Row A", data: [%{x: "a", y: 1, fill: %{type: :none}}, 2]}]
      svg = live(series)

      assert rect(svg, "0-0") =~ ~s(fill="none")
      # The outline takes the cell's scale colour, not the white separator.
      refute rect(svg, "0-0") =~ ~s(stroke="#fff")
    end

    test "a pattern cell links a pattern from <defs>" do
      point = %{x: "a", y: 1, fill: %{type: :pattern, pattern: %{style: :slanted_lines}}}
      svg = live([%{name: "Row A", data: [point, 2]}])

      assert svg =~ ~r/<pattern [^>]*id="hp-pattern-0"/
      assert rect(svg, "0-0") =~ ~s|fill="url(#hp-pattern-0)"|
    end

    test "without categories the x of map points names the columns" do
      svg = live(@series)

      assert svg =~ ">State 1</text>"
      assert svg =~ ">State 3</text>"
    end

    test "the tooltip marker shows the cell's own colour" do
      svg = live(@series)

      assert svg =~ ~r/data-j="0-1".*?background:#ff6105/s
    end

    test "map points on a numeric x-axis keep their paint" do
      series = [%{name: "Row A", data: [%{x: 1, y: 3}, %{x: 2, y: 4, fill_color: "#123456"}]}]
      svg = live(series, %{xaxis: %{type: :numeric}})

      assert rect(svg, "0-1") =~ ~s(fill="#123456")
    end
  end

  describe "per-cell labels" do
    test "a string label replaces the value" do
      series = [%{name: "Row A", data: [%{x: "a", y: 7, label: "seven"}, 8]}]
      [first, second] = live(series, @labels) |> labels()

      assert first =~ ">seven</text>"
      assert second =~ ">8</text>"
    end

    test "lines are centred on the cell and may hold styled segments" do
      label = ["1", [%{text: "Row J", font_weight: 400}]]
      series = [%{name: "Row A", data: [%{x: "a", y: 1, label: label}]}]
      [text] = live(series, @labels) |> labels()

      assert text =~ ~s(dominant-baseline="central")
      # Two lines: the first moves up half a line so the block is centred.
      assert text =~ ~s(dy="-0.6em")
      assert text =~ ~s(dy="1.2em")
      assert text =~ ~s(font-weight="400")
      assert text =~ "Row J"
    end

    test "labels follow data_labels.enabled" do
      series = [%{name: "Row A", data: [%{x: "a", y: 1, label: "one"}]}]

      refute live(series) =~ "one</text>"
      assert live(series, @labels) =~ "one</text>"
    end

    test "a label on a light fill_color turns dark, on a dark one stays white" do
      series = [
        %{
          name: "Row A",
          data: [%{x: "a", y: 1, fill_color: "#e8e8e8"}, %{x: "b", y: 2, fill_color: "#2a2018"}]
        }
      ]

      [light, dark] = live(series, @labels) |> labels()

      assert light =~ ~s(fill="#373d3f")
      assert dark =~ ~s(fill="#fff")
    end

    test "on an outline cell the label takes the outline colour" do
      point = %{x: "a", y: 0, fill: %{type: :none}, stroke_color: "#d9d9d9", label: "-"}
      [text] = live([%{name: "Row A", data: [point]}], @labels) |> labels()

      assert text =~ ~s(fill="#d9d9d9")
    end
  end

  describe "themes" do
    test "dark: unstyled cells use palette4, labels on own fills stay legible" do
      svg = live(@series, Map.put(@labels, :theme, %{mode: :dark}))

      assert rect(svg, "0-1") =~ ~s(fill="#ff6105")
      # Scale cells follow the dark palette (palette4), not palette1.
      assert rect(svg, "1-2") =~ "#D7F790"
      refute rect(live(@series), "1-2") =~ "#D7F790"

      light_fill = [%{name: "Row A", data: [%{x: "a", y: 1, fill_color: "#e8e8e8"}]}]
      [text] = live(light_fill, Map.put(@labels, :theme, %{mode: :dark})) |> labels()
      assert text =~ ~s(fill="#373d3f")
    end

    test "daisy live: var() fills and separators reach the cells" do
      series = [
        %{name: "Row A", data: [%{x: "a", y: 1, fill_color: "var(--color-error, #ff5861)"}, 2]}
      ]

      svg = live(series, Map.put(@labels, :theme, %{mode: :daisy}))

      assert rect(svg, "0-0") =~ ~s|fill="var(--color-error, #ff5861)"|
      assert rect(svg, "0-1") =~ ~s|stroke="var(--color-base-100, #fff)"|

      # A var() fill cannot be measured: its label keeps the on-mark colour.
      [on_var, _] = labels(svg)
      assert on_var =~ "var(--color-primary-content"
    end

    test "daisy live: a hex fill_color picks its label from the fill" do
      series = [%{name: "Row A", data: [%{x: "a", y: 1, fill_color: "#2a2018"}]}]
      [text] = live(series, Map.put(@labels, :theme, %{mode: :daisy})) |> labels()

      assert text =~ ~s(fill="#fff")
    end

    test "daisy static: no var() is left" do
      series = [
        %{
          name: "Row A",
          data: [
            %{x: "a", y: 1, fill_color: "var(--color-error, #ff5861)", label: ["1", "Row J"]},
            %{x: "b", y: 2, stroke_color: "var(--color-base-content, #373d3f)"}
          ]
        }
      ]

      svg = static(series, Map.put(@labels, :theme, %{mode: :daisy}))

      refute svg =~ "var("
      [own_fill, own_stroke] = rects(svg)
      assert own_fill =~ ~s(fill="#ff5861")
      assert own_stroke =~ ~s(stroke="#373d3f")
    end
  end
end
