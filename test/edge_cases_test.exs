defmodule EexCharts.EdgeCasesTest do
  @moduledoc """
  Boundary-condition tests: pathological option values, degenerate data, and
  ranges small or awkward enough to break tick generation.

  Two kinds of test live here, and both must stay green:

    * **regressions** — each one reproduced a real defect through the public
      API before it was fixed, and fails again if the fix is undone.

    * **guard** tests — behavior that is correct and easy to break.

  See `docs/KNOWN_ISSUES.md` for what each case covers.
  """

  use ExUnit.Case, async: true

  alias EexCharts.{Scale, SVG, TimeScale}

  # Runs `fun` with a hard deadline so a non-terminating tick loop fails the
  # test instead of hanging the suite.
  defp within(ms, fun) do
    task = Task.async(fun)

    case Task.yield(task, ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, value} -> {:ok, value}
      nil -> :timeout
    end
  end

  defp html(id, type, series, opts) do
    {:safe, io} = EexCharts.render(id, type, series, opts)
    IO.iodata_to_binary(io)
  end

  defp texts_in(html, group_class) do
    case Regex.run(~r/<g class="#{group_class}">(.*?)<\/g>/s, html) do
      [_, inner] -> Regex.scan(~r/>([^<]*)<\/text>/, inner) |> Enum.map(&List.last/1)
      _ -> []
    end
  end

  defp data_labels(html) do
    Regex.scan(~r/<text ([^>]*class="eexcharts-datalabel"[^>]*)>(-?[\d.]+)</, html)
    |> Enum.map(fn [_, attrs, value] ->
      {y, ""} = Regex.run(~r/ y="(-?[\d.]+)"/, attrs) |> List.last() |> Float.parse()
      {value, y}
    end)
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Regressions — each of these was a real defect. Keep them fixed.
  # ──────────────────────────────────────────────────────────────────────────

  describe "a forced y-axis step_size is not validated" do
    test "step_size: 0 renders instead of raising" do
      assert {:ok, svg} =
               within(2_000, fn ->
                 html("s", :line, [%{name: "A", data: [1, 2]}],
                   categories: ~w(a b),
                   options: %{yaxis: %{step_size: 0}}
                 )
               end)

      assert svg =~ "eexcharts-svg"
    end

    test "negative step_size renders instead of raising or spinning" do
      assert {:ok, svg} =
               within(2_000, fn ->
                 html("s", :line, [%{name: "A", data: [1, 2]}],
                   categories: ~w(a b),
                   options: %{yaxis: %{step_size: -5}}
                 )
               end)

      assert svg =~ "eexcharts-svg"
    end

    test "a step_size far smaller than the range terminates with a bounded tick count" do
      assert {:ok, scale} =
               within(2_000, fn ->
                 Scale.nice_scale(0, 1_000_000, step_size: 1.0e-6)
               end)

      # An unbounded tick list here spins the calling process, so the count must
      # be clamped to what the axis can actually display.
      assert length(scale.ticks) < 1_000
    end
  end

  describe "small numeric x ranges" do
    test "x-axis labels stay distinguishable for very small values" do
      labels =
        html("s", :scatter, [%{name: "A", data: [[0.00001, 1], [0.00002, 2], [0.00003, 3]]}], [])
        |> texts_in("eexcharts-xaxis-labels")

      assert labels != []
      assert Enum.uniq(labels) == labels, "x labels collapsed to duplicates: #{inspect(labels)}"
    end

    test "linear_scale reaches x_max when the range is small" do
      {_ticks, _min, nice_max} = Scale.linear_scale(0, 0.07, 5, nil)

      # Rounding the step to 2 decimals truncates the axis at 0.05, so any data
      # point above it is drawn outside the grid.
      assert nice_max >= 0.07
    end

    test "fmt_value keeps enough precision to distinguish small axis values" do
      formatted = Enum.map([0.00001, 0.00002, 0.00003], &SVG.fmt_value/1)
      assert Enum.uniq(formatted) == formatted
    end
  end

  describe "bar data label position" do
    defp bar_labels(position) do
      html("b", :bar, [%{name: "A", data: [-40, 40]}],
        categories: ~w(neg pos),
        options: %{
          data_labels: %{enabled: true},
          plot_options: %{bar: %{data_labels: %{position: position}}}
        }
      )
      |> data_labels()
      |> Map.new()
    end

    test ":top and :bottom place labels differently" do
      refute bar_labels(:top) == bar_labels(:bottom),
             "position is ignored: :top and :bottom produce identical output"
    end

    test "position: :top puts a negative bar's label at its top (zero) edge" do
      top = bar_labels(:top)
      center = bar_labels(:center)

      # The top edge of a bar hanging below zero is the zero line, which sits
      # above the bar's midpoint. Smaller y == higher on the canvas.
      assert top["-40"] < center["-40"],
             "negative bar label placed at the value end (y=#{top["-40"]}) " <>
               "instead of the top edge (center is y=#{center["-40"]})"
    end
  end

  describe "datetime x-axis" do
    test "tolerates non-integer millisecond bounds" do
      min = TimeScale.to_ms(~D[2026-02-20]) + 0.5

      assert {:ok, ticks} =
               within(2_000, fn -> TimeScale.ticks(min, min + 5 * 86_400_000, 600) end)

      assert is_list(ticks)
    end

    test "hour ticks crossing midnight carry the date" do
      # 20:00 Feb 28 → 04:00 Mar 1 is labelled HH:mm throughout, so the day
      # change is invisible and 00:00 is ambiguous. A tick that opens a new day
      # should be labelled with that day.
      start = TimeScale.to_ms(~N[2026-02-28 20:00:00])
      labels = TimeScale.ticks(start, start + 8 * 3_600_000, 600) |> Enum.map(& &1.label)

      assert Enum.any?(labels, &String.contains?(&1, "Mar")),
             "no tick carries a date across the day boundary: #{inspect(labels)}"
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # Guard tests — currently-correct behavior worth pinning. Keep them green.
  # ──────────────────────────────────────────────────────────────────────────

  describe "extreme magnitudes raise instead of rendering" do
    @huge 1.0e308

    test "every chart type renders values near the float limit" do
      cases = [
        {:line, [%{name: "A", data: [@huge, -@huge]}]},
        {:area, [%{name: "A", data: [@huge, 1.7e308]}]},
        {:bar, [%{name: "A", data: [@huge, -@huge]}]},
        {:scatter, [%{name: "A", data: [[@huge, 1], [-@huge, 2]]}]},
        {:bubble, [%{name: "A", data: [[1, 2, @huge], [2, 3, 1]]}]},
        {:pie, [@huge, @huge]},
        {:radial_bar, [@huge]},
        {:radar, [%{name: "A", data: [@huge, -@huge, 1]}]},
        {:heatmap, [%{name: "A", data: [@huge, -@huge]}]},
        {:treemap, [%{data: [@huge, @huge]}]},
        {:candlestick, [%{data: [%{x: "a", y: [@huge, @huge, -@huge, 1]}]}]},
        {:box_plot, [%{data: [%{x: "a", y: [-@huge, 1, 2, 3, @huge]}]}]},
        {:range_bar, [%{data: [%{x: "a", y: [-@huge, @huge]}]}]}
      ]

      for {type, series} <- cases do
        assert html("s", type, series, []) =~ "eexcharts-svg", "#{type} did not render"
      end
    end

    test "stacked sums of huge values render" do
      series = [%{name: "A", data: [@huge]}, %{name: "B", data: [@huge]}]
      assert html("s", :bar, series, options: %{chart: %{stacked: true}}) =~ "eexcharts-svg"
    end

    test "a forced y-axis min and max at the float limit render" do
      svg =
        html("s", :line, [%{name: "A", data: [1, 2]}],
          options: %{yaxis: %{min: -@huge, max: @huge}}
        )

      assert svg =~ "eexcharts-svg"
    end

    test "values too small or too close together for a scale render" do
      for data <- [
            [1.0e-300, 2.0e-300],
            [5.0e-324, 1.0e-323],
            [1.0, 1.0 + 2.220446049250313e-16],
            [1.0e-20, 2.0e-20]
          ] do
        assert html("s", :line, [%{name: "A", data: data}], []) =~ "eexcharts-svg",
               "#{inspect(data)} did not render"
      end
    end

    test "huge values are labelled in exponent form" do
      assert SVG.fmt_value(1.0e300) == "1.0e300"
      assert SVG.fmt_value(1.0e21) == "1.0e21"
      assert SVG.fmt_value(1.0e20) == "100000000000000000000.0"
    end
  end

  describe "a logarithmic y-axis over values <= 0" do
    test "renders instead of dividing by a zero range" do
      for data <- [[0, -5, 10], [0, 0], [-1, -2]] do
        svg =
          html("s", :line, [%{name: "A", data: data}], options: %{yaxis: %{logarithmic: true}})

        assert svg =~ "eexcharts-svg", "#{inspect(data)} did not render"
      end
    end
  end

  describe "datetime values outside the DateTime range" do
    test "render instead of raising in DateTime.from_unix!/2" do
      for data <- [
            [[0, 1], [9_000_000_000_000_000, 2]],
            [[-9_000_000_000_000_000, 1], [0, 2]],
            [[0, 1], [1.0e300, 2]]
          ] do
        svg = html("s", :line, [%{name: "A", data: data}], options: %{xaxis: %{type: :datetime}})
        assert svg =~ "eexcharts-svg", "#{inspect(data)} did not render"
      end
    end
  end

  describe "heatmap {x, y} points" do
    test "render, and name the columns after the first series' x values" do
      svg =
        html(
          "s",
          :heatmap,
          [
            %{name: "R1", data: [%{x: "W1", y: 3}, %{x: "W2", y: 8}]},
            %{name: "R2", data: [%{x: "W1", y: 5}, %{x: "W2", y: 1}]}
          ],
          []
        )

      assert texts_in(svg, "eexcharts-xaxis-labels") == ["W1", "W2"]
      assert length(Regex.scan(~r/class="eexcharts-heatmap-rect"/, svg)) == 4
    end

    test "a cell without a numeric value is left empty" do
      svg = html("s", :heatmap, [%{name: "R", data: [1, "x", %{x: "c", y: "y"}, nil, 4]}], [])
      assert length(Regex.scan(~r/class="eexcharts-heatmap-rect"/, svg)) == 2
    end
  end

  describe "guards: datetime tick alignment" do
    test "a range starting exactly on a minute boundary keeps its first tick" do
      start = TimeScale.to_ms(~N[2026-03-01 10:05:00])
      labels = TimeScale.ticks(start, start + 10 * 60_000, 600) |> Enum.map(& &1.label)

      assert List.first(labels) == "10:05:00"
    end

    test "a range starting exactly on a second boundary keeps its first tick" do
      start = TimeScale.to_ms(~N[2026-03-01 10:05:00])
      labels = TimeScale.ticks(start, start + 60_000, 600) |> Enum.map(& &1.label)

      assert List.first(labels) == "10:05:00"
    end

    test "short-month rollover does not drift by a day" do
      a = TimeScale.to_ms(~D[2026-02-20])
      b = TimeScale.to_ms(~D[2026-03-05])
      labels = TimeScale.ticks(a, b, 600) |> Enum.map(& &1.label)

      # Day ticks are epoch-aligned, so February's length cannot shift March.
      assert "03 Mar" in labels
      refute "29 Feb" in labels
    end

    test "month ticks land on real calendar month starts" do
      a = TimeScale.to_ms(~D[2026-01-01])
      b = TimeScale.to_ms(~D[2026-12-31])
      ticks = TimeScale.ticks(a, b, 600)

      for %{value: ms} <- ticks do
        d = DateTime.from_unix!(ms, :millisecond)
        assert d.day == 1
        assert {d.hour, d.minute, d.second} == {0, 0, 0}
      end
    end
  end

  describe "guards: hidden series" do
    setup do
      %{
        svg:
          html(
            "t",
            :line,
            [%{name: "Visible", data: [1, 2]}, %{name: "HiddenOne", data: [3, 4]}],
            categories: ~w(a b),
            hidden_series: [1]
          )
      }
    end

    test "tooltips omit hidden series", %{svg: svg} do
      [_, tooltips] = String.split(svg, ~s(class="eexcharts-tooltip"), parts: 2)

      assert tooltips =~ "Visible"
      refute tooltips =~ "HiddenOne"
    end

    test "the legend dims hidden series and is derived from hidden_series only", %{svg: svg} do
      assert svg =~ ~s(data-series="1" opacity="0.4")
      assert svg =~ "HiddenOne"

      # Re-enabling is a pure re-render: no dimmed state can survive it.
      shown =
        html("t", :line, [%{name: "Visible", data: [1, 2]}, %{name: "HiddenOne", data: [3, 4]}],
          categories: ~w(a b),
          hidden_series: []
        )

      refute shown =~ ~s(opacity="0.4")
    end
  end

  describe "guards: annotations" do
    test "x- and y-axis range bands both honor the configured opacity" do
      svg =
        html("an", :line, [%{name: "A", data: [1, 2, 3]}],
          categories: ~w(a b c),
          options: %{
            annotations: %{
              yaxis: [%{y: 1, y2: 2, opacity: 0.77}],
              xaxis: [%{x: "a", x2: "b", opacity: 0.66}]
            }
          }
        )

      rects = Regex.scan(~r/<rect [^>]*eexcharts-annotation-rect[^>]*\/>/, svg)
      assert length(rects) == 2

      opacities =
        rects
        |> Enum.map(fn [tag] -> Regex.run(~r/fill-opacity="([\d.]+)"/, tag) end)
        |> Enum.map(&List.last/1)

      assert "0.77" in opacities
      assert "0.66" in opacities
    end
  end

  describe "guards: area fills" do
    test "nil gaps split the fill and each subpath closes exactly once" do
      svg = html("ar", :area, [%{name: "A", data: [5, nil, -5, 10]}], categories: ~w(a b c d))

      # Area fills are the paths with no stroke; the line on top is stroked.
      fills =
        Regex.scan(~r/<path [^>]*stroke="none"[^>]*\/>/, svg)
        |> Enum.map(fn [tag] -> Regex.run(~r/ d="([^"]*)"/, tag) |> List.last() end)

      assert length(fills) == 2, "expected one fill per non-nil run, got #{inspect(fills)}"

      for d <- fills do
        assert String.ends_with?(d, "Z")
        assert length(String.split(d, "Z")) == 2, "malformed close in #{d}"
      end
    end
  end

  describe "guards: degenerate pie input" do
    test "nil, zero and negative slice values render without crashing" do
      for series <- [[nil, nil], [0, 0], [-5, 10]], type <- [:pie, :donut] do
        assert html("p", type, series, labels: ~w(a b)) =~ "eexcharts-svg"
      end
    end
  end

  describe "guards: hover shading" do
    test "the hover filter darkens rather than lightening toward white" do
      # A lighten filter pushes already-bright fills to white, losing the hue.
      css = File.read!(Path.join(:code.priv_dir(:eexcharts), "static/eexcharts.css"))

      assert css =~ "brightness(0.92)"
      refute css =~ "brightness(1."
    end
  end
end
