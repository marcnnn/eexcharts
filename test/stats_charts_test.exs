defmodule EexCharts.StatsChartsTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Renderer, Stats}

  # Same sample as test/stats_test.exs (NumPy oracles live there).
  @data [12.5, 3.1, 7.7, 15.2, 9.9, 4.4, 11.0, 8.3, 6.6, 21.7, 10.1, 5.5, 13.8] ++
          [7.2, 9.4, 2.9, 14.6, 8.8, 30.2, 10.7, 6.1, 12.0, 9.0, 7.9, 11.6]

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  # Attribute maps of every element `<tag class="class" ...>`.
  defp elements(html, tag, class) do
    ~r/<#{tag} class="#{class}"([^>]*)>/
    |> Regex.scan(html, capture: :all_but_first)
    |> Enum.map(fn [attrs] ->
      ~r/([\w-]+)="([^"]*)"/
      |> Regex.scan(attrs, capture: :all_but_first)
      |> Map.new(fn [k, v] -> {k, num(v)} end)
    end)
  end

  defp num(v) do
    case Float.parse(v) do
      {f, ""} -> f
      _ -> v
    end
  end

  defp path_points(d) do
    ~r/[ML] (-?[\d.e-]+) (-?[\d.e-]+)/
    |> Regex.scan(d, capture: :all_but_first)
    |> Enum.map(fn [x, y] -> {num(x), num(y)} end)
  end

  defp view_box(html) do
    [_, x, y, w, h] = Regex.run(~r/viewBox="(\S+) (\S+) (\S+) (\S+)"/, html)
    {num(x), num(y), num(w), num(h)}
  end

  defp assert_finite(html) do
    refute html =~ "NaN"
    refute html =~ "Infinity"
  end

  describe "histogram" do
    test "one bar per non-empty bin, adjacent, heights proportional to counts" do
      html = render(%{id: "h", type: :histogram, series: [%{name: "s", data: @data}]})
      assert_finite(html)

      bars = elements(html, "rect", "eexcharts-bar eexcharts-histogram-bar")
      edges = Stats.bin_edges(@data)
      counts = Stats.histogram(@data, edges)
      assert length(bars) == Enum.count(counts, &(&1 > 0))

      # Every bar starts where the previous bin ended (no gaps): bars for
      # consecutive bins touch.
      by_j = Map.new(bars, &{trunc(&1["data-j"]), &1})

      for {a, b} <- Enum.zip(0..(length(counts) - 2), 1..(length(counts) - 1)),
          Map.has_key?(by_j, a) and Map.has_key?(by_j, b) do
        assert_in_delta by_j[a]["x"] + by_j[a]["width"], by_j[b]["x"], 1.0e-6
      end

      # Heights per count unit are the same for every bar.
      ratios =
        for {j, bar} <- by_j, do: bar["height"] / Enum.at(counts, j)

      assert Enum.max(ratios) - Enum.min(ratios) < 1.0e-6

      # Bar widths are proportional to bin widths (equal bins → equal bars).
      widths = Enum.map(bars, & &1["width"])
      assert Enum.max(widths) - Enum.min(widths) < 1.0e-6
    end

    test "bars stay inside the SVG" do
      html = render(%{id: "h", type: :histogram, series: [%{name: "s", data: @data}]})
      {_x, _y, w, h} = view_box(html)

      for b <- elements(html, "rect", "eexcharts-bar eexcharts-histogram-bar") do
        assert b["x"] >= 0 and b["x"] + b["width"] <= w
        assert b["y"] >= 0 and b["y"] + b["height"] <= h
      end
    end

    test "tooltips are titled with the bin range" do
      html =
        render(%{
          id: "h",
          type: :histogram,
          series: [%{name: "s", data: [1, 2, 3, 12, 14]}],
          options: %{plot_options: %{histogram: %{bin_width: 5}}}
        })

      assert html =~ ~s(<div class="eexcharts-tip-title">0 - 5</div>)
      assert html =~ ~s(<div class="eexcharts-tip-title">10 - 15</div>)
      assert html =~ ~s(<span class="eexcharts-tip-value">3</span>)
    end

    test "options are read from plot_options.histogram" do
      cfg = EexCharts.Config.build(:histogram, %{})
      assert cfg.plot_options.histogram.bins == :auto
      assert cfg.plot_options.histogram.normalize == :count
      assert cfg.xaxis.type == :numeric

      {_cfg, [s]} =
        EexCharts.Charts.Histogram.prepare(
          EexCharts.Config.build(:histogram, %{
            plot_options: %{histogram: %{bins: 6, normalize: :percent, cumulative: true}}
          }),
          [%{name: "s", data: @data, index: 0}]
        )

      assert length(s.data) == 6
      assert_in_delta List.last(s.data).y, 100.0, 1.0e-9
      assert List.last(s.data).count == 25
    end

    test "overlaid series share bin edges and draw translucent" do
      a = %{name: "a", data: [1, 2, 2, 3, 4]}
      b = %{name: "b", data: [3, 4, 5, 5, 6, 9]}
      html = render(%{id: "h", type: :histogram, series: [a, b]})
      bars = elements(html, "rect", "eexcharts-bar eexcharts-histogram-bar")

      assert Enum.all?(bars, &(&1["fill-opacity"] == 0.5))

      xs = bars |> Enum.map(&{&1["x"], &1["width"]}) |> Enum.uniq() |> length()
      edges = Stats.bin_edges(a.data ++ b.data)
      assert xs <= length(edges) - 1

      # Hiding a series keeps the bins where they were.
      hidden = render(%{id: "h", type: :histogram, series: [a, b], hidden_series: [1]})
      only_a = elements(hidden, "rect", "eexcharts-bar eexcharts-histogram-bar")
      assert Enum.all?(only_a, fn bar -> Enum.any?(bars, &(&1["x"] == bar["x"])) end)
    end

    test "empty and degenerate data render" do
      for data <- [[], [5], [5, 5, 5], [nil, 3]] do
        html = render(%{id: "h", type: :histogram, series: [%{name: "s", data: data}]})
        assert html =~ "<svg"
        assert_finite(html)
      end
    end
  end

  describe "violin" do
    @groups [
      %{x: "A", y: @data},
      %{x: "B", y: Enum.map(@data, &(&1 * 0.5 + 10))}
    ]

    test "each violin is symmetric about its centre line" do
      html = render(%{id: "v", type: :violin, series: [%{name: "s", data: @groups}]})
      assert_finite(html)
      shapes = elements(html, "path", "eexcharts-violin")
      assert length(shapes) == 2

      for shape <- shapes do
        pts = path_points(shape["d"])
        {xmin, xmax} = pts |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
        cx = (xmin + xmax) / 2
        half = div(length(pts), 2)
        {right, left} = Enum.split(pts, half)

        for {{xr, yr}, {xl, yl}} <- Enum.zip(right, Enum.reverse(left)) do
          assert_in_delta yr, yl, 1.0e-9
          assert_in_delta xr - cx, cx - xl, 1.0e-6
        end
      end
    end

    test "scale: :width makes every violin equally wide" do
      html = render(%{id: "v", type: :violin, series: [%{name: "s", data: @groups}]})

      widths =
        for shape <- elements(html, "path", "eexcharts-violin") do
          {a, b} = shape["d"] |> path_points() |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
          b - a
        end

      [w1, w2] = widths
      assert_in_delta w1, w2, 1.0e-6
    end

    test "categories come from the points' x labels; tooltip shows the summary" do
      html = render(%{id: "v", type: :violin, series: [%{name: "s", data: @groups}]})
      assert html =~ ">A</text>"
      assert html =~ ">B</text>"
      assert html =~ "Median: 9.4 Q1: 7.2 Q3: 12 n: 25"
    end

    test "the inner box spans the quartiles" do
      html = render(%{id: "v", type: :violin, series: [%{name: "s", data: [@data]}]})
      [box] = Regex.scan(~r/<g class="eexcharts-violin-box">.*?<\/g>/, html)
      assert hd(box) =~ "<rect"
      assert hd(box) =~ ~s(fill="#fff")

      none =
        render(%{
          id: "v",
          type: :violin,
          series: [%{name: "s", data: [@data]}],
          options: %{plot_options: %{violin: %{inner: :none}}}
        })

      refute none =~ "eexcharts-violin-box"
    end

    test "raincloud: half violin, box and one deterministic point per observation" do
      params = %{
        id: "v",
        type: :violin,
        series: [%{name: "s", data: [@data]}],
        options: %{plot_options: %{violin: %{raincloud: true}}}
      }

      html = render(params)
      assert html == render(params)

      [cloud] = elements(html, "path", "eexcharts-violin")
      pts = path_points(cloud["d"])
      base = pts |> Enum.map(&elem(&1, 0)) |> Enum.min()
      # The first and last points sit on the base line; the density only
      # rises to the right of it.
      assert_in_delta elem(hd(pts), 0), base, 1.0e-9

      points = elements(html, "circle", "eexcharts-violin-point")
      assert length(points) == length(@data)
      assert Enum.all?(points, &(&1["cx"] < base))
      assert html =~ "eexcharts-violin-box"
    end
  end

  describe "box plot from raw observations" do
    test "computes the Tukey summary and draws outliers" do
      html =
        render(%{
          id: "b",
          type: :box_plot,
          series: [%{name: "s", data: [%{x: "A", observations: @data}]}],
          categories: ["A"]
        })

      assert html =~ "Min: 2.9 Q1: 7.2 Median: 9.4 Q3: 12 Max: 15.2 Outliers: 21.7, 30.2"
      assert length(elements(html, "circle", "eexcharts-boxplot-outlier")) == 2
      assert_finite(html)
    end

    test "a y list that is not five values is raw; exactly five stays a summary" do
      raw =
        render(%{id: "b", type: :box_plot, series: [%{name: "s", data: [%{x: "A", y: @data}]}]})

      assert raw =~ "Median: 9.4"

      five =
        render(%{
          id: "b",
          type: :box_plot,
          series: [%{name: "s", data: [%{x: "A", y: [1, 2, 3, 4, 5]}]}]
        })

      assert five =~ "Min: 1 Q1: 2 Median: 3 Q3: 4 Max: 5"

      five_obs =
        render(%{
          id: "b",
          type: :box_plot,
          series: [%{name: "s", data: [%{x: "A", observations: [5, 1, 4, 2, 3]}]}]
        })

      assert five_obs =~ "Min: 1 Q1: 2 Median: 3 Q3: 4 Max: 5"
    end

    test "whisker multiple comes from plot_options.box_plot.whisker" do
      html =
        render(%{
          id: "b",
          type: :box_plot,
          series: [%{name: "s", data: [%{x: "A", observations: @data}]}],
          options: %{plot_options: %{box_plot: %{whisker: 3}}}
        })

      assert html =~ "Max: 21.7 Outliers: 30.2"
    end
  end
end
