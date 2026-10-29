defmodule EexCharts.GoalsTest do
  use ExUnit.Case, async: true

  defp live(type, series, opts \\ []) do
    {:safe, io} = EexCharts.render("gl", type, series, opts)
    IO.iodata_to_binary(io)
  end

  defp static(type, series, opts \\ []), do: EexCharts.to_svg("gl", type, series, opts)

  defp tags(svg, tag), do: Regex.scan(~r/<#{tag}\b[^>]*>/, svg) |> List.flatten()

  defp goals(svg, tag \\ "line"),
    do: svg |> tags(tag) |> Enum.filter(&(&1 =~ ~s(class="eexcharts-goal")))

  defp attr(tag, name) do
    [_, v] = Regex.run(~r/\s#{name}="([^"]*)"/, tag)
    v
  end

  defp num(tag, name), do: tag |> attr(name) |> Float.parse() |> elem(0)

  # {x, y, w, h} of the bar paths (`M x y L x2 y ... L x y2 z`).
  defp bars(svg) do
    for tag <- tags(svg, "path"), tag =~ "eexcharts-bar" do
      [x, y | rest] =
        Regex.scan(~r/-?\d+(?:\.\d+)?/, attr(tag, "d"))
        |> List.flatten()
        |> Enum.map(&(&1 |> Float.parse() |> elem(0)))

      xs = [x | rest |> Enum.chunk_every(2) |> Enum.map(&hd/1)]
      ys = [y | rest |> Enum.chunk_every(2) |> Enum.map(&List.last/1)]
      {Enum.min(xs), Enum.min(ys), Enum.max(xs) - Enum.min(xs), Enum.max(ys) - Enum.min(ys)}
    end
  end

  defp goal(value, extra \\ %{}), do: Map.merge(%{name: "Goal", value: value}, extra)

  describe "columns" do
    test "a goal spans the bar width at its value, 2px thick, in the v4.7.0 grey" do
      svg = static(:bar, [%{name: "S", data: [%{x: "A", y: 40, goals: [goal(60)]}, 20]}])

      [line] = goals(svg)
      [{x, _y, w, _h}, _] = bars(svg)

      assert_in_delta num(line, "x1"), x, 0.01
      assert_in_delta num(line, "x2"), x + w, 0.01
      assert num(line, "y1") == num(line, "y2")
      assert attr(line, "stroke") == "#a8a8a8"
      assert attr(line, "stroke-width") == "2"
      refute line =~ "stroke-dasharray"
    end

    test "stroke_width is half the length, stroke_height the thickness" do
      g = goal(30, %{stroke_width: 6, stroke_height: 5, stroke_color: "#775DD0"})
      svg = static(:bar, [%{name: "S", data: [%{y: 40, goals: [g]}]}])

      [line] = goals(svg)
      [{x, _, w, _}] = bars(svg)

      assert_in_delta num(line, "x1"), x + w / 2 - 6, 0.01
      assert_in_delta num(line, "x2"), x + w / 2 + 6, 0.01
      assert attr(line, "stroke-width") == "5"
      assert attr(line, "stroke") == "#775DD0"
    end

    test "dash array and line cap pass through" do
      g = goal(30, %{stroke_dash_array: 4, stroke_line_cap: :round})
      [line] = static(:bar, [%{name: "S", data: [%{y: 40, goals: [g]}]}]) |> goals()

      assert attr(line, "stroke-dasharray") == "4"
      assert attr(line, "stroke-linecap") == "round"
    end

    test "goal values extend the value axis" do
      plain = static(:bar, [%{name: "S", data: [10, 20]}])
      svg = static(:bar, [%{name: "S", data: [%{y: 10, goals: [goal(95)]}, 20]}])

      refute plain =~ ">100<"
      assert svg =~ ">100<"
      [line] = goals(svg)
      assert num(line, "y1") > 0
    end

    test "stacked goals sit at their own value and are drawn after every bar" do
      series = [
        %{name: "S1", data: [%{y: 10, goals: [goal(25)]}]},
        %{name: "S2", data: [20]}
      ]

      svg = static(:bar, series, options: %{chart: %{stacked: true}})
      [line] = goals(svg)

      [last_bar | _] =
        svg |> tags("path") |> Enum.filter(&(&1 =~ "eexcharts-bar")) |> Enum.reverse()

      {bar_pos, _} = :binary.match(svg, last_bar)
      {goal_pos, _} = :binary.match(svg, line)
      assert goal_pos > bar_pos
    end

    test "goals outside a fixed axis range are skipped" do
      svg =
        static(:bar, [%{name: "S", data: [%{y: 10, goals: [goal(500), goal(15)]}]}],
          options: %{yaxis: %{min: 0, max: 20}}
        )

      assert length(goals(svg)) == 1
    end

    test "a chart without goals draws no goal group" do
      refute static(:bar, [%{name: "S", data: [%{y: 10}, 20]}]) =~ "eexcharts-goals"
    end
  end

  describe "horizontal and range bars" do
    test "horizontal goals span the bar height; stroke_width is the thickness" do
      svg =
        static(:bar, [%{name: "S", data: [%{y: 40, goals: [goal(60, %{stroke_width: 3})]}]}],
          options: %{plot_options: %{bar: %{horizontal: true}}}
        )

      [line] = goals(svg)
      [{_x, y, _w, h}] = bars(svg)

      assert num(line, "x1") == num(line, "x2")
      assert_in_delta num(line, "y1"), y, 0.01
      assert_in_delta num(line, "y2"), y + h, 0.01
      assert attr(line, "stroke-width") == "3"
    end

    test "range bars take goals, vertical and horizontal" do
      data = [%{x: "A", y: [20, 40], goals: [goal(30, %{stroke_height: 4})]}]

      for horizontal <- [false, true] do
        svg =
          static(:range_bar, [%{name: "S", data: data}],
            options: %{plot_options: %{bar: %{horizontal: horizontal}}}
          )

        [line] = goals(svg)
        [{x, y, w, h}] = bars(svg)

        if horizontal do
          assert_in_delta num(line, "y2") - num(line, "y1"), 8, 0.01
          assert_in_delta num(line, "x1"), x + w / 2, 0.01
        else
          assert_in_delta num(line, "x2") - num(line, "x1"), w, 0.01
          assert_in_delta num(line, "y1"), y + h / 2, 0.01
        end
      end
    end

    test "range bar goals extend the axis" do
      data = [%{x: "A", y: [20, 40], goals: [goal(5)]}]
      svg = static(:range_bar, [%{name: "S", data: data}])
      [line] = goals(svg)
      [{_x, y, _w, h}] = bars(svg)
      assert num(line, "y1") > y + h
    end
  end

  describe "shape: :circle" do
    test "draws a dot of radius size at the value, centred on the bar" do
      g = goal(30, %{shape: :circle, size: 7, stroke_color: "#ff6105"})

      svg =
        static(:range_bar, [%{name: "S", data: [%{x: "A", y: [40, 60], goals: [g]}]}],
          options: %{plot_options: %{bar: %{horizontal: true}}}
        )

      assert goals(svg) == []
      [dot] = goals(svg, "circle")
      [{_x, y, _w, h}] = bars(svg)

      assert attr(dot, "r") == "7"
      assert attr(dot, "fill") == "#ff6105"
      assert attr(dot, "stroke") == "#fff"
      assert_in_delta num(dot, "cy"), y + h / 2, 0.01
    end

    test "default radius is 5" do
      g = goal(30, %{shape: :circle})
      [dot] = static(:bar, [%{name: "S", data: [%{y: 10, goals: [g]}]}]) |> goals("circle")
      assert attr(dot, "r") == "5"
    end
  end

  describe "tooltip" do
    test "lists each goal under the point's value" do
      g = [goal(60, %{name: "Target", stroke_color: "#775DD0"}), goal(70, %{name: "Stretch"})]
      html = live(:bar, [%{name: "Actual", data: [%{y: 54, goals: g}]}])

      assert html =~ ~r/background:#775DD0.*Target: .*60/s
      assert html =~ ~r/background:#a8a8a8.*Stretch: .*70/s
    end

    test "timeline row tooltips list the goals of every bar in the row" do
      series = [
        %{
          name: "Plan",
          data: [
            %{x: "Design", y: [1, 4], goals: [goal(3, %{name: "Review"})]},
            %{x: "Design", y: [5, 7]}
          ]
        }
      ]

      html = live(:range_bar, series, options: %{plot_options: %{bar: %{horizontal: true}}})

      assert html =~ ~r/Review: .*3/s
    end
  end

  describe "themes" do
    @series [
      %{
        name: "S",
        data: [%{y: 40, goals: [%{value: 60}, %{value: 30, shape: :circle}]}]
      }
    ]

    test "dark mode keeps the mid-grey default, readable on a dark page" do
      svg = static(:bar, @series, options: %{theme: %{mode: :dark}})
      [line] = goals(svg)
      assert attr(line, "stroke") == "#a8a8a8"
    end

    test "daisy live output hands base-content to goals and the surface to dot rings" do
      html = live(:bar, @series, options: %{theme: %{mode: :daisy}})
      [line] = goals(html)
      [dot] = goals(html, "circle")

      assert attr(line, "stroke") == "var(--color-base-content, #a8a8a8)"
      assert attr(dot, "fill") =~ "var(--color-base-content"
      assert attr(dot, "stroke") =~ "var(--color-base-100"
    end

    test "daisy static output has no var()" do
      svg = static(:bar, @series, options: %{theme: %{mode: :daisy}})
      refute svg =~ "var("
      [line] = goals(svg)
      assert attr(line, "stroke") == "#a8a8a8"
    end

    test "a goal's own colour and the configured default win over the theme" do
      series = [%{name: "S", data: [%{y: 40, goals: [goal(60, %{stroke_color: "#123456"})]}]}]
      [line] = live(:bar, series, options: %{theme: %{mode: :daisy}}) |> goals()
      assert attr(line, "stroke") == "#123456"

      opts = %{theme: %{mode: :daisy}, plot_options: %{bar: %{goals: %{stroke_color: "#654321"}}}}
      [line] = live(:bar, @series, options: opts) |> goals()
      assert attr(line, "stroke") == "#654321"
    end
  end
end
