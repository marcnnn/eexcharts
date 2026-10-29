defmodule EexCharts.LevelMeterTest do
  use ExUnit.Case, async: true

  alias EexCharts.Charts.LevelMeter
  alias EexCharts.Config

  defp static(series, opts \\ []), do: EexCharts.to_svg("lm", :level_meter, series, opts)

  defp live(series, opts) do
    "lm" |> EexCharts.render(:level_meter, series, opts) |> Phoenix.HTML.safe_to_string()
  end

  defp lm(options), do: [options: %{plot_options: %{level_meter: options}}]

  defp geo(series, options \\ %{}, params \\ %{}) do
    cfg = Config.build(:level_meter, %{plot_options: %{level_meter: options}})
    LevelMeter.geometry(cfg, Map.merge(%{series: series}, params))
  end

  defp tags(svg, class),
    do: Regex.scan(~r/<rect[^>]*class="#{class}[^"]*"[^>]*>/, svg) |> List.flatten()

  defp attr(tag, name), do: Regex.run(~r/ #{name}="([^"]*)"/, tag) |> List.last()

  defp num(tag, name), do: tag |> attr(name) |> Float.parse() |> elem(0)

  @one [%{name: "Level", data: [%{x: "Item 01", y: 3}]}]

  describe "segments" do
    test "a whole value fills that many segments; empty ones are track rects" do
      svg = static(@one)
      assert length(tags(svg, "eexcharts-level-meter-fill")) == 3
      assert length(tags(svg, "eexcharts-level-meter-track")) == 2
    end

    test "segments option sets the count" do
      svg = static(@one, lm(%{segments: 8}))
      assert length(tags(svg, "eexcharts-level-meter-track")) == 5
    end

    test "a fractional value fills the partial segment with an inner rect over its track" do
      %{cells: [cell], seg_w: w} = geo([%{name: "L", data: [2.4]}])
      third = Enum.at(cell.segments, 2)
      assert_in_delta third.kept, 0.4, 1.0e-9

      svg = static([%{name: "L", data: [2.4]}])
      [partial] = tags(svg, "eexcharts-level-meter-fill eexcharts-level-meter-partial")
      assert_in_delta num(partial, "width"), 0.4 * w, 1.0e-6
      # the partial segment still has its track, so 3 tracks for 2.4 of 5
      assert length(tags(svg, "eexcharts-level-meter-track")) == 3
    end

    test "values are clamped to 0..segments" do
      svg = static([%{name: "L", data: [9, -2]}])
      assert length(tags(svg, "eexcharts-level-meter-fill")) == 5
      assert length(tags(svg, "eexcharts-level-meter-track")) == 5
    end

    test "a missing point draws nothing" do
      svg = static([%{name: "A", data: [1, nil]}, %{name: "B", data: [2, 2]}])
      assert length(tags(svg, "eexcharts-level-meter-track")) == 4 + 3 + 3
    end
  end

  describe "target" do
    test "a value below the target colours all its filled segments" do
      series = [%{name: "L", data: [2.5, 3]}]
      svg = static(series, lm(%{target: 3, below_target_color: "#ff6105"}))
      fills = tags(svg, "eexcharts-level-meter-fill")

      assert Enum.count(fills, &(attr(&1, "fill") == "#ff6105")) == 3
      assert Enum.count(fills, &(attr(&1, "fill") == "#008FFB")) == 3
      refute Enum.any?(tags(svg, "eexcharts-level-meter-track"), &(&1 =~ "#ff6105"))
    end

    test "the target gap sits after segment `target`" do
      %{cells: [c]} = geo([%{name: "L", data: [1]}], %{target: 3, target_gap: 4, gap: 3})
      [s1, s2, s3, s4, s5] = c.segments
      step = s2.x - s1.x
      assert_in_delta s3.x - s2.x, step, 1.0e-9
      assert_in_delta s4.x - s3.x, step + 4, 1.0e-9
      assert_in_delta s5.x - s4.x, step, 1.0e-9
    end

    test "no gap for a target outside 1..segments - 1" do
      for t <- [0, 5, 7] do
        %{cells: [c]} = geo([%{name: "L", data: [1]}], %{target: t})
        [a, b | _] = c.segments

        steps =
          c.segments |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [p, q] -> q.x - p.x end)

        assert Enum.all?(steps, &(abs(&1 - (b.x - a.x)) < 1.0e-9))
      end
    end

    test "a point target beats the series and plot targets" do
      series = [%{name: "L", target: 2, data: [%{x: "a", y: 2, target: 4}, %{x: "b", y: 2}]}]
      %{cells: [a, b]} = geo(series, %{target: 1})
      assert a.below
      refute b.below
    end
  end

  describe "previous" do
    test "gained segments use gained_color" do
      series = [%{name: "L", data: [%{x: "a", y: 3, previous: 2}]}]
      svg = static(series, lm(%{gained_color: "#858587"}))
      [gained] = tags(svg, "eexcharts-level-meter-fill eexcharts-level-meter-gained")
      assert attr(gained, "fill") == "#858587"
      assert length(tags(svg, "eexcharts-level-meter-fill")) == 3
    end

    test "without gained_color the gain is the row colour at gained_opacity" do
      series = [%{name: "L", data: [%{x: "a", y: 3, previous: 2}]}]

      [gained] =
        series |> static() |> tags("eexcharts-level-meter-fill eexcharts-level-meter-gained")

      assert attr(gained, "fill") == "#008FFB"
      assert attr(gained, "fill-opacity") == "0.45"
    end

    test "a drop outlines the lost segments over the track" do
      series = [%{name: "L", data: [%{x: "a", y: 2, previous: 4}]}]
      svg = static(series)
      lost = Regex.scan(~r/<rect[^>]*eexcharts-level-meter-lost[^>]*>/, svg) |> List.flatten()
      assert length(lost) == 2

      assert Enum.all?(
               lost,
               &(attr(&1, "fill") == "none" and attr(&1, "stroke-dasharray") == "2 2")
             )

      assert length(tags(svg, "eexcharts-level-meter-track")) == 3
    end

    test "the value label shows previous → value" do
      series = [%{name: "L", data: [%{x: "a", y: 3, previous: 2}]}]
      svg = static(series, lm(%{value_label: %{formatter: &"L#{&1}"}}))
      assert svg =~ "L2 → L3"

      svg = static(series, lm(%{value_label: %{show_previous: false}}))
      assert svg =~ ~r/eexcharts-level-meter-value[^>]*>3</
    end
  end

  describe "layout" do
    test "several series form a matrix with row and column labels" do
      series = [
        %{name: "Row A", data: [%{x: "North", y: 3}, %{x: "East", y: 2}]},
        %{name: "Row B", data: [1, 4]}
      ]

      g = geo(series)
      assert g.mode == :matrix
      assert Enum.map(g.columns, & &1.label) == ["North", "East"]
      assert Enum.map(g.rows, & &1.label) == ["Row A", "Row B"]
      assert length(g.cells) == 4

      svg = static(series, categories: ["N", "E"])
      assert svg =~ ">N</text>"
      assert svg =~ ">Row B</text>"
    end

    test "one series is a list: each point is a row" do
      g = geo([%{name: "L", data: [%{x: "Item 01", y: 1}, %{x: "Item 02", y: 2}]}])
      assert g.mode == :list
      assert Enum.map(g.rows, & &1.label) == ["Item 01", "Item 02"]
      [a, b] = g.cells
      assert a.y < b.y
      refute static([3, 2], labels: ["Item 01", "Item 02"]) =~ "column-labels"
    end

    test "layout: :matrix keeps a single series as one row" do
      g = geo([%{name: "Row A", data: [1, 2, 3]}], %{layout: :matrix})
      assert length(g.rows) == 1 and length(g.columns) == 3
    end

    test "a summary series gets a rule and bold labels" do
      series = [%{name: "Row A", data: [1, 2]}, %{name: "Average", summary: true, data: [1.5, 2]}]
      svg = static(series)
      assert svg =~ "eexcharts-level-meter-rule"
      assert svg =~ ~r/font-weight="700"[^>]*>Average</
    end

    test "per-point fill_color wins over the row and below-target colours" do
      series = [%{name: "L", data: [%{x: "a", y: 1, fill_color: "#123456"}]}]
      svg = static(series, lm(%{target: 3}))
      [fill] = tags(svg, "eexcharts-level-meter-fill")
      assert attr(fill, "fill") == "#123456"
    end

    test "distributed colours rows by series" do
      series = [%{name: "A", data: [1, 1]}, %{name: "B", data: [1, 1]}]
      colors = Config.build(:level_meter, %{}).colors || Config.colors(%{})
      svg = static(series, lm(%{distributed: true}))
      assert svg =~ Enum.at(colors, 1)
      refute static(series) =~ Enum.at(colors, 1)
    end

    test "no legend by default" do
      refute static([%{name: "A", data: [1]}, %{name: "B", data: [2]}]) =~ "eexcharts-legend"
    end
  end

  describe "interaction" do
    test "tooltips per cell and on_click carry index and series" do
      series = [
        %{name: "Row A", data: [%{x: "North", y: 3, previous: 2}]},
        %{name: "Row B", data: [1]}
      ]

      html =
        live(series, on_click: "pick", options: %{plot_options: %{level_meter: %{target: 3}}})

      assert html =~ ~s(data-j="0-0")
      assert html =~ ~s(data-j="1-0")
      assert html =~ ~s(phx-click="pick")
      assert html =~ ~s(phx-value-series="1")
      assert html =~ "Previous: "
      assert html =~ "Target: "
    end
  end

  describe "themes" do
    @series [%{name: "L", data: [%{x: "a", y: 2, previous: 3}, %{x: "b", y: 4}]}]

    test "dark mode mutes the track; a user track colour wins" do
      svg = static(@series, options: %{theme: %{mode: :dark}})
      assert Enum.all?(tags(svg, "eexcharts-level-meter-track"), &(attr(&1, "fill") == "#4b4f52"))

      svg =
        static(@series,
          options: %{
            theme: %{mode: :dark},
            plot_options: %{level_meter: %{track: %{color: "#222"}}}
          }
        )

      assert Enum.all?(tags(svg, "eexcharts-level-meter-track"), &(attr(&1, "fill") == "#222"))
    end

    test "daisy live output hands var() to the track, warning and labels" do
      html =
        live(@series,
          options: %{theme: %{mode: :daisy}, plot_options: %{level_meter: %{target: 3}}}
        )

      assert html =~ "var(--color-base-200, #f2f2f2)"
      assert html =~ "var(--color-warning, #FEB019)"
      assert html =~ "var(--color-primary, #008FFB)"
      assert html =~ ~r/eexcharts-level-meter-value[^>]*fill="var\(--color-base-content/
    end

    test "daisy static output resolves every var()" do
      svg =
        static(@series,
          options: %{theme: %{mode: :daisy}, plot_options: %{level_meter: %{target: 3}}}
        )

      refute svg =~ "var("
      assert svg =~ "#FEB019"
    end

    test "daisy keeps a user-set below_target_color" do
      html =
        live(@series,
          options: %{
            theme: %{mode: :daisy},
            plot_options: %{level_meter: %{target: 3, below_target_color: "#ff6105"}}
          }
        )

      refute html =~ "--color-warning"
      assert html =~ "#ff6105"
    end
  end
end
