defmodule EexCharts.TimelineTest do
  use ExUnit.Case, async: true

  alias EexCharts.TimeScale

  @opts %{
    chart: %{width: 600, height: 300},
    xaxis: %{type: :datetime},
    plot_options: %{bar: %{horizontal: true}}
  }

  @tracks [
    %{
      name: "Tracks",
      data: [
        %{x: "Track 1", y: [~D[2024-01-01], ~D[2024-04-01]], label: "11/12"},
        %{x: "Track 1", y: [~D[2025-01-01], ~D[2025-04-01]], label: "12/12"},
        %{x: "Track 2", y: [~D[2024-06-01], ~D[2024-08-15]], label: "8/12"},
        %{x: "Track 2", y: [~D[2026-08-01], ~D[2026-11-05]], fill: %{type: :none}, label: "6/12"},
        %{
          x: "Track 3",
          y: [~D[2027-03-01], ~D[2027-08-01]],
          fill: %{type: :pattern, pattern: %{style: :slanted_lines}},
          label: "0/12"
        }
      ]
    }
  ]

  @end_labels %{
    data_labels: %{enabled: true},
    plot_options: %{bar: %{data_labels: %{position: :outside_end}}}
  }

  defp svg(series, opts \\ %{}) do
    EexCharts.to_svg("t", :range_bar, series, options: EexCharts.Config.deep_merge(@opts, opts))
    |> IO.iodata_to_binary()
  end

  defp live(series, opts) do
    {:safe, io} =
      EexCharts.render("t", :range_bar, series, options: EexCharts.Config.deep_merge(@opts, opts))

    IO.iodata_to_binary(io)
  end

  defp bars(svg) do
    for [_, attrs] <- Regex.scan(~r/<path class="eexcharts-bar[^"]*"([^>]*)>/, svg) do
      [x0, y0, x1, y1] =
        ~r/d="M ([\d.]+) ([\d.]+) L ([\d.]+) [\d.]+ L [\d.]+ ([\d.]+)/
        |> Regex.run(attrs, capture: :all_but_first)
        |> Enum.map(&parse/1)

      row =
        case Regex.run(~r/data-j="(\d+)"/, attrs, capture: :all_but_first) do
          [j] -> String.to_integer(j)
          nil -> nil
        end

      %{x: x0, y: y0, w: x1 - x0, h: y1 - y0, row: row}
    end
  end

  defp labels(svg) do
    for [_, attrs, text] <-
          Regex.scan(~r/<text ([^>]*class="eexcharts-datalabel"[^>]*)>([^<]*)</, svg) do
      attr = &(Regex.run(~r/\b#{&1}="([^"]*)"/, attrs, capture: :all_but_first) |> hd())
      %{text: text, x: parse(attr.("x")), anchor: attr.("text-anchor"), fill: attr.("fill")}
    end
  end

  defp parse(s), do: s |> Float.parse() |> elem(0)

  defp texts(svg, class) do
    for [_, t] <- Regex.scan(~r/<text [^>]*class="#{class}"[^>]*>([^<]*)</, svg), do: t
  end

  describe "month scale" do
    defp tick_labels(from, to, width) do
      from
      |> TimeScale.to_ms()
      |> TimeScale.ticks(TimeScale.to_ms(to), width)
      |> Enum.map(& &1.label)
    end

    test "names the year at January, as v4.7.0 does" do
      assert tick_labels(~D[2024-01-01], ~D[2027-08-01], 800) == ["2024", "2025", "2026", "2027"]
    end

    test "stepped ticks snap to the calendar, not to the first data month" do
      # 6-month steps from June land on Jul / Jan, never on Jun / Dec.
      assert tick_labels(~D[2024-06-01], ~D[2026-03-01], 800) ==
               ["Jul '24", "2025", "Jul '25", "2026"]
    end
  end

  describe "datetime range bars" do
    test "points sharing an x share a row; the rows are the distinct labels" do
      out = live(@tracks, %{})
      bars = bars(out)

      assert length(bars) == 5
      assert Enum.map(bars, & &1.row) == [0, 0, 1, 1, 2]
      assert texts(out, "eexcharts-xaxis-label") == ["Track 1", "Track 2", "Track 3"]

      [a, b | _] = bars
      assert a.y == b.y and b.x > a.x + a.w
    end

    test "the value axis is a time scale over the data" do
      out = svg(@tracks)
      [axis] = Regex.run(~r/<g class="eexcharts-yaxis-labels">.*?<\/g>/, out)

      assert ~w(2024 2025 2026 2027) --
               (Regex.scan(~r/>([^<]+)</, axis) |> Enum.map(&List.last/1)) == []

      # The first bar starts on the left edge of the plot: no nice rounding.
      [first | _] = bars(out)

      [grid_x] =
        Regex.run(~r/<line class="eexcharts-axis-border"[^>]*x1="([\d.]+)"/, out,
          capture: :all_but_first
        )

      assert_in_delta first.x, parse(grid_x), 0.01
    end

    test "Date, DateTime, NaiveDateTime, ISO strings and unix ms place bars alike" do
      as = fn f ->
        [
          %{
            name: "S",
            data: [
              %{x: "Row A", y: Enum.map([~D[2026-01-01], ~D[2026-03-01]], f)},
              %{x: "Row B", y: [~D[2026-02-01], ~D[2026-06-01]]}
            ]
          }
        ]
      end

      expected = bars(svg(as.(& &1)))

      for f <- [
            &DateTime.new!(&1, ~T[00:00:00]),
            &NaiveDateTime.new!(&1, ~T[00:00:00]),
            &Date.to_iso8601/1,
            &TimeScale.to_ms/1
          ] do
        assert bars(svg(as.(f))) == expected
      end
    end

    test "xaxis.min / xaxis.max bound the time scale" do
      out = svg(@tracks, %{xaxis: %{min: ~D[2023-01-01], max: ~D[2028-01-01]}})
      [first | _] = bars(out)

      [grid_x] =
        Regex.run(~r/<line class="eexcharts-axis-border"[^>]*x1="([\d.]+)"/, out,
          capture: :all_but_first
        )

      assert first.x > parse(grid_x) + 10
    end

    test "range_bar_overlap: false splits overlapping ranges of a row" do
      data = [
        %{x: "Row A", y: [~D[2026-01-01], ~D[2026-03-01]]},
        %{x: "Row A", y: [~D[2026-02-01], ~D[2026-04-01]]},
        %{x: "Row B", y: [~D[2026-01-01], ~D[2026-02-01]]}
      ]

      [a, b, c] = bars(svg([%{name: "S", data: data}]))
      assert a.y == b.y and a.h == b.h
      assert_in_delta c.h, a.h, 0.001

      [a, b, c] =
        bars(
          svg([%{name: "S", data: data}], %{plot_options: %{bar: %{range_bar_overlap: false}}})
        )

      assert_in_delta a.h * 2, c.h, 0.001
      assert_in_delta b.y, a.y + a.h, 0.001
    end

    test "range_bar_group_rows draws every series over the full row" do
      series = [
        %{name: "S1", data: [%{x: "Row A", y: [~D[2026-01-01], ~D[2026-02-01]]}]},
        %{name: "S2", data: [%{x: "Row A", y: [~D[2026-03-01], ~D[2026-04-01]]}]}
      ]

      [a, b] = bars(svg(series))
      assert a.y != b.y

      [a, b] = bars(svg(series, %{plot_options: %{bar: %{range_bar_group_rows: true}}}))
      assert a.y == b.y and a.h == b.h
    end

    test "the tooltip of a row lists every bar in it, with dates" do
      {:safe, io} = EexCharts.render("t", :range_bar, @tracks, options: @opts)
      html = IO.iodata_to_binary(io)

      [tip] = Regex.run(~r/<div[^>]*data-j="1"[^>]*>.*?<\/div><\/div><\/div>/s, html)
      assert tip =~ "01 Jun 2024 – 15 Aug 2024"
      assert tip =~ "01 Aug 2026 – 05 Nov 2026"
    end
  end

  describe "data labels" do
    test "outside_end labels sit past the bar end in the page text colour" do
      out = svg(@tracks, @end_labels)
      bars = bars(out)
      labels = labels(out)

      assert Enum.map(labels, & &1.text) == ~w(11/12 12/12 8/12 6/12 0/12)

      for {bar, label} <- Enum.zip(bars, labels) do
        assert label.anchor == "start"
        assert_in_delta label.x, bar.x + bar.w + 6, 0.001
        assert label.fill == "#373d3f"
      end
    end

    test "the layout keeps every outside label inside the chart" do
      for w <- [300, 450, 600, 900] do
        out = svg(@tracks, Map.put(@end_labels, :chart, %{width: w}))

        for l <- labels(out) do
          assert l.x + EexCharts.Layout.text_width(l.text, 12) <= w - 10 + 0.001,
                 "#{l.text} overflows at width #{w}"
        end
      end
    end

    test "labels default to the range length; formatter gets [from, to]" do
      series = [%{name: "S", data: [%{x: "A", y: [10, 40]}, %{x: "B", y: [5, 12], label: "own"}]}]
      opts = %{xaxis: %{type: :category}, data_labels: %{enabled: true}}

      assert Enum.map(labels(svg(series, opts)), & &1.text) == ["30", "own"]

      opts = put_in(opts, [:data_labels, :formatter], fn [a, b] -> "#{a}..#{b}" end)
      assert Enum.map(labels(svg(series, opts)), & &1.text) == ["10..40", "own"]
    end

    test "inside labels are centred and dropped when wider than the bar" do
      series = [
        %{
          name: "S",
          data: [
            %{x: "A", y: [~D[2026-01-01], ~D[2026-12-01]], label: "fits"},
            %{x: "B", y: [~D[2026-01-01], ~D[2026-01-03]], label: "far too long"}
          ]
        }
      ]

      [label] = labels(svg(series, %{data_labels: %{enabled: true}}))
      assert label.text == "fits" and label.anchor == "middle" and label.fill == "#fff"

      opts = %{
        data_labels: %{enabled: true},
        plot_options: %{bar: %{data_labels: %{hide_overflowing_labels: false}}}
      }

      assert length(labels(svg(series, opts))) == 2
    end

    test "outline and pattern bars keep readable inside labels" do
      [_, _, _, outline, pattern] =
        labels(svg(@tracks, %{data_labels: %{enabled: true}, chart: %{width: 2000}}))

      assert outline.fill == "#008FFB"
      assert pattern.fill == "#373d3f"
    end
  end

  describe "x annotations on the value axis" do
    @today %{annotations: %{xaxis: [%{x: ~D[2026-10-29], label: %{text: "Today"}}]}}

    defp anno_lines(svg) do
      for [_, x1, x2] <-
            Regex.scan(
              ~r/<line class="eexcharts-annotation-line"[^>]*x1="([\d.]+)" x2="([\d.]+)"/,
              svg
            ),
          do: {parse(x1), parse(x2)}
    end

    test "a date draws a vertical line at its place on the time axis" do
      out = svg(@tracks, @today)
      [{x1, x2}] = anno_lines(out)
      assert x1 == x2
      assert texts(out, "eexcharts-annotation-label") == ["Today"]

      # 2026-10-29 lies between the starts of the two Track 2 bars' years.
      [_, _, _, active | _] = bars(out)
      assert x1 > active.x and x1 < active.x + active.w
    end

    test "dates outside the axis are skipped; bands span two dates" do
      out = svg(@tracks, %{annotations: %{xaxis: [%{x: ~D[2030-01-01]}]}})
      assert anno_lines(out) == []

      out = svg(@tracks, %{annotations: %{xaxis: [%{x: ~D[2025-01-01], x2: "2025-06-01"}]}})
      assert out =~ ~s(class="eexcharts-annotation-rect")
    end

    test "category horizontal charts keep x annotations on the categories" do
      series = [%{name: "S", data: [%{x: "A", y: [1, 4]}, %{x: "B", y: [2, 6]}]}]
      out = svg(series, %{xaxis: %{type: :category}, annotations: %{xaxis: [%{x: "B"}]}})
      [{x1, x2}] = anno_lines(out)
      assert x1 < x2
    end
  end

  describe "themes" do
    test "dark: outside labels use the dark page text colour" do
      out = svg(@tracks, Map.put(@end_labels, :theme, %{mode: :dark}))
      assert Enum.all?(labels(out), &(&1.fill == "#f6f7f8"))
    end

    test "daisy live: labels and bars carry daisyUI variables" do
      html = live(@tracks, Map.put(@end_labels, :theme, %{mode: :daisy}))
      assert Enum.all?(labels(html), &(&1.fill == "var(--color-base-content, #373d3f)"))
      assert html =~ ~s|fill="var(--color-primary, #008FFB)"|
      assert html =~ "var(--color-base-content"

      inside =
        live(@tracks, %{
          data_labels: %{enabled: true},
          theme: %{mode: :daisy},
          chart: %{width: 2000}
        })

      assert hd(labels(inside)).fill == "var(--color-primary-content, #fff)"
    end

    test "daisy static: no var( left" do
      out = svg(@tracks, @end_labels |> Map.put(:theme, %{mode: :daisy}) |> Map.merge(@today))
      refute out =~ "var("
      assert Enum.all?(labels(out), &(&1.fill == "#373d3f"))
    end
  end
end
