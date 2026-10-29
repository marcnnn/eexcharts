defmodule EexCharts.EndLabelsTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, EndLabels}

  @on %{end_labels: %{enabled: true}, legend: %{show: false}}

  @series [
    %{name: "Group 1", data: [59, 67, 74], end_label: "74 · +15"},
    %{name: "Group 2", data: [61, 63, 66.5], end_label: true},
    %{name: "Row A", data: [55, 63, 71], opacity: 0.25}
  ]

  defp live(type, series, opts) do
    {:safe, io} = EexCharts.render("el", type, series, opts)
    IO.iodata_to_binary(io)
  end

  defp static(type, series, opts), do: EexCharts.to_svg("el", type, series, opts)

  defp labels(svg) do
    ~r/<text class="eexcharts-end-label"([^>]*)>([^<]*)<\/text>/
    |> Regex.scan(svg, capture: :all_but_first)
    |> Enum.map(fn [attrs, text] ->
      attr = fn name -> Regex.run(~r/ #{name}="([^"]*)"/, attrs, capture: :all_but_first) end
      [x] = attr.("x")
      [y] = attr.("y")
      [fill] = attr.("fill")
      %{text: text, x: num(x), y: num(y), fill: fill}
    end)
  end

  defp num(s), do: s |> Float.parse() |> elem(0)

  # Left and right edge of the plot, from the first horizontal grid line.
  defp grid_box(svg) do
    [x1, x2] =
      Regex.run(~r/<line class="eexcharts-grid-line"[^>]* x1="([\d.]+)" x2="([\d.]+)"/, svg,
        capture: :all_but_first
      )

    {num(x1), num(x2)}
  end

  describe "place/5" do
    test "labels far apart stay on their anchors" do
      assert EndLabels.place([10.0, 100.0, 50.0], true, 15, 0, 200) == [10.0, 100.0, 50.0]
    end

    test "colliding labels are pushed apart symmetrically, input order kept" do
      assert EndLabels.place([104.0, 100.0], true, 20, 0, 200) == [112.0, 92.0]
    end

    test "a lone label at the plot edge is kept inside the plot" do
      assert EndLabels.place([-3.0], true, 10, 0, 200) == [0.0]
    end

    test "a column pushed past an edge is clamped inside" do
      assert EndLabels.place([2.0, 3.0, 4.0], true, 10, 0, 200) == [0.0, 10.0, 20.0]
      assert EndLabels.place([199.0, 198.0], true, 10, 0, 200) == [200.0, 190.0]
    end

    test "avoid_overlap false keeps the anchors" do
      assert EndLabels.place([4.0, 3.0], false, 10, 0, 200) == [4.0, 3.0]
    end
  end

  describe "rendering" do
    test "only series with an end_label get one; true means the series name" do
      svg = static(:line, @series, options: @on)
      assert Enum.map(labels(svg), & &1.text) == ["74 · +15", "Group 2"]
    end

    test "off by default, and then the layout is unchanged" do
      plain = static(:line, @series, options: %{legend: %{show: false}})
      off = static(:line, @series, options: Map.put(@on, :end_labels, %{enabled: false}))

      assert labels(plain) == []
      assert plain == off
    end

    test "the plot shrinks to fit the longest label inside the SVG" do
      {l_off, r_off} = grid_box(static(:line, @series, options: %{legend: %{show: false}}))
      svg = static(:line, @series, options: @on)
      {gx, gr} = grid_box(svg)

      assert gx == l_off
      assert gr < r_off

      for label <- labels(svg) do
        width = EexCharts.Layout.text_width(label.text, 13)
        assert label.x > gr
        assert label.x + width <= 600
      end
    end

    test "labels sit right of the last non-nil point, centred on it" do
      series = [%{name: "Group 1", data: [10, 20, nil], end_label: "end"}]
      svg = static(:line, series, options: Map.put(@on, :yaxis, %{max: 40}))
      [label] = labels(svg)

      [_, x, y] = Regex.run(~r/<path d="M [\d.]+ [\d.]+ L ([\d.]+) ([\d.]+)"/, svg)
      assert label.x == num(x) + 8
      assert label.y == num(y)
    end

    test "close labels are nudged at least one text height apart" do
      series = [
        %{name: "Group 1", data: [10, 60], end_label: true},
        %{name: "Group 2", data: [10, 61], end_label: true}
      ]

      opts = Map.put(@on, :yaxis, %{min: 0, max: 100})
      [a, b] = static(:line, series, options: opts) |> labels()
      assert abs(a.y - b.y) >= EexCharts.Layout.text_height(13) + 2 - 1.0e-6

      overlapping = put_in(opts, [:end_labels, :avoid_overlap], false)
      [c, d] = static(:line, series, options: overlapping) |> labels()
      assert abs(c.y - d.y) < 5
    end

    test "series colour by default, style.colors overrides it" do
      [a, b] = static(:line, @series, options: @on) |> labels()
      assert {a.fill, b.fill} == {"#008FFB", "#00E396"}

      opts = put_in(@on, [:end_labels, :style], %{colors: ["#111111", "#222222"]})

      assert static(:line, @series, options: opts) |> labels() |> Enum.map(& &1.fill) ==
               ["#111111", "#222222"]
    end

    test "formatter gets the label and the last value" do
      opts =
        put_in(@on, [:end_labels, :formatter], fn label, %{value: v, series_index: i} ->
          "#{label} #{v} (#{i})"
        end)

      assert static(:line, @series, options: opts) |> labels() |> Enum.map(& &1.text) ==
               ["74 · +15 74 (0)", "Group 2 66.5 (1)"]
    end

    test "other chart types ignore end_labels" do
      series = [%{name: "Series 1", data: [1, 2], end_label: true}]
      bar = static(:bar, series, options: @on)

      assert labels(bar) == []
      assert bar == static(:bar, series, options: %{legend: %{show: false}})
    end

    test "hidden series get no label but keep the reserve" do
      shown = static(:line, @series, options: @on)
      hidden = static(:line, @series, options: @on, hidden_series: [0])

      assert hidden |> labels() |> Enum.map(& &1.text) == ["Group 2"]
      assert grid_box(hidden) == grid_box(shown)
    end

    test "area and stacked charts label the top of each band" do
      series = [
        %{name: "Series 1", data: [10, 20], end_label: true},
        %{name: "Series 2", data: [10, 20], end_label: true}
      ]

      assert static(:area, series, options: @on) |> labels() |> length() == 2

      stacked = Map.put(@on, :chart, %{stacked: true})
      [s1, s2] = static(:area, series, options: stacked) |> labels()
      # Series 2 stacks on top of series 1, so its label sits higher.
      assert s2.y < s1.y
    end
  end

  describe "series opacity, stroke widths and marker sizes" do
    test "opacity fades the stroke, area fill and markers of that series only" do
      svg = static(:line, @series, options: %{markers: %{size: 4}})
      paths = Regex.scan(~r/<path [^>]*stroke-opacity="0.25"[^>]*>/, svg)
      assert length(paths) == 1
      assert svg =~ ~r/<circle class="eexcharts-marker"[^>]*fill-opacity="0.25"/

      area = static(:area, @series, options: %{fill: %{type: :solid, opacity: 0.8}})
      assert area =~ ~s(fill-opacity="0.2")
    end

    test "stroke.width and markers.size accept per-series lists" do
      svg =
        static(:line, @series,
          options: %{stroke: %{width: [4, 2, 1]}, markers: %{size: [3, 0, 0]}}
        )

      widths =
        Regex.scan(~r/<path d[^>]*stroke-width="([\d.]+)"/, svg, capture: :all_but_first)

      assert List.flatten(widths) == ["4", "2", "1"]
      assert length(Regex.scan(~r/<circle class="eexcharts-marker"/, svg)) == 3
    end
  end

  describe "themes" do
    test "dark: labels take palette4 colours" do
      [a, b] = static(:line, @series, options: Map.put(@on, :theme, %{mode: :dark})) |> labels()
      [c0, c1 | _] = Config.build(:line, %{theme: %{mode: :dark}}).colors
      assert {a.fill, b.fill} == {c0, c1}
    end

    test "dark: a near-black series label turns readable on the dark page" do
      opts = Map.merge(@on, %{theme: %{mode: :dark}, colors: ["#202020", "#4ecdc4"]})
      [a, b] = static(:line, @series, options: opts) |> labels()
      assert a.fill != "#202020"
      assert EexCharts.Color.contrast(a.fill, "#343434") >= 1.5
      assert b.fill == "#4ecdc4"
    end

    test "daisy live output hands the series var() to the labels" do
      svg = live(:line, @series, options: Map.put(@on, :theme, %{mode: :daisy}))
      [a, b] = labels(svg)
      assert a.fill == "var(--color-primary, #008FFB)"
      assert b.fill == "var(--color-secondary, #00E396)"
    end

    test "daisy static output has no var() left" do
      svg = static(:line, @series, options: Map.put(@on, :theme, %{mode: :daisy}))
      refute svg =~ "var("
      assert labels(svg) |> Enum.map(& &1.fill) == ["#008FFB", "#00E396"]
    end
  end
end
