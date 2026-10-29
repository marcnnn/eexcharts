defmodule EexCharts.SparklineTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Layout}

  @spark %{chart: %{sparkline: %{enabled: true}}}
  @values [9, 3, 20, 22, 28, 30, 27, 28, 30, 29, 24, 19, 23, 13, 26, 30]

  defp live(type, series, opts) do
    {:safe, io} = EexCharts.render("sp", type, series, opts)
    IO.iodata_to_binary(io)
  end

  defp static(type, series, opts), do: EexCharts.to_svg("sp", type, series, opts)

  defp spark(extra), do: Config.deep_merge(@spark, extra)

  defp tags(svg, tag), do: Regex.scan(~r/<#{tag}\b[^>]*>/, svg) |> List.flatten()

  defp num(tag, attr) do
    [_, v] = Regex.run(~r/\b#{attr}="([-\d.e]+)"/, tag)
    String.to_float(if v =~ ".", do: v, else: v <> ".0")
  end

  # Every coordinate pair in the bar paths.
  defp bar_points(svg) do
    svg
    |> tags("path")
    |> Enum.filter(&(&1 =~ "eexcharts-bar"))
    |> Enum.flat_map(fn tag ->
      [_, d] = Regex.run(~r/ d="([^"]+)"/, tag)

      ~r/(-?[\d.]+) (-?[\d.]+)/
      |> Regex.scan(d, capture: :all_but_first)
      |> Enum.map(fn [x, y] -> {parse(x), parse(y)} end)
    end)
  end

  defp parse(s), do: elem(Float.parse(s), 0)

  describe "config" do
    test "off by default" do
      cfg = Config.build(:line)
      refute Config.sparkline?(cfg)
      assert cfg.chart.sparkline == %{enabled: false}
      assert cfg.grid.show
    end

    test "applies the ApexCharts sparkline defaults" do
      cfg = Config.build(:bar, @spark)

      assert Config.sparkline?(cfg)
      refute cfg.grid.show
      assert cfg.grid.padding == %{top: 0, right: 0, bottom: 0, left: 0}
      refute cfg.legend.show
      refute cfg.xaxis.labels.show
      refute cfg.xaxis.axis_border.show
      refute cfg.xaxis.axis_ticks.show
      refute cfg.data_labels.enabled
      refute cfg.yaxis.show
      assert cfg.chart.parent_height_offset == 0
      assert cfg.chart.pixel_perfect
    end

    test "user options win, except the first y-axis, which stays hidden" do
      cfg =
        Config.build(
          :line,
          spark(%{
            data_labels: %{enabled: true},
            grid: %{padding: %{bottom: 20}},
            yaxis: %{show: true, labels: %{show: true}, title: %{text: "Value"}}
          })
        )

      assert cfg.data_labels.enabled
      assert cfg.grid.padding.bottom == 20
      assert cfg.grid.padding.top == 0
      refute cfg.yaxis.show
      refute cfg.yaxis.labels.show
      assert cfg.yaxis.title.text == nil
    end

    test "with a y-axis list only the first axis is hidden" do
      cfg = Config.build(:line, spark(%{yaxis: [%{show: true}, %{opposite: true}]}))
      [first, second] = Config.yaxes(cfg)
      refute first.show
      assert second.show
    end
  end

  describe "layout" do
    test "a bar sparkline's plot is the whole SVG" do
      cfg = Config.build(:bar, spark(%{chart: %{width: 160, height: 24}}))
      l = Layout.build(cfg, ["Series 1"], 16, {0, 30})

      assert {l.grid_x, l.grid_y, l.grid_w, l.grid_h} == {0, 0, 160, 24}
    end

    test "the stroke keeps half its width at the top and bottom" do
      cfg = Config.build(:line, spark(%{chart: %{width: 160, height: 24}}))
      l = Layout.build(cfg, ["Series 1"], 5, {0, 30})

      # line stroke width 5
      assert {l.grid_x, l.grid_y, l.grid_w, l.grid_h} == {0, 2.5, 160, 19.0}
    end

    test "markers are padded by the ApexCharts marker pad" do
      opts = spark(%{chart: %{width: 160, height: 32}, markers: %{size: 4}})
      l = Layout.build(Config.build(:line, opts), ["Series 1"], 3, {0, 30})

      # (size 4 + line hover offset 6) / 1.5
      pad = 10 / 1.5
      assert {l.grid_x, l.grid_y} == {pad, pad}
      assert_in_delta l.grid_w, 160 - 2 * pad, 1.0e-9
    end

    test "but never less than the drawn marker: radius plus half its stroke" do
      opts = spark(%{chart: %{width: 160, height: 32}, markers: %{size: 4, stroke_width: 8}})
      l = Layout.build(Config.build(:line, opts), ["Series 1"], 3, {0, 30})

      assert {l.grid_x, l.grid_y, l.grid_w, l.grid_h} == {8, 8, 144, 16}
    end

    test "grid padding set by the user is kept when larger" do
      opts = spark(%{chart: %{width: 160, height: 32}, grid: %{padding: %{left: 20, top: 8}}})
      l = Layout.build(Config.build(:bar, opts), ["Series 1"], 3, {0, 30})

      assert {l.grid_x, l.grid_y} == {20, 8}
    end
  end

  describe "rendering" do
    test "no axis, grid, legend or label elements" do
      svg =
        static(:bar, [%{name: "Series 1", data: @values}],
          width: 160,
          height: 24,
          options: @spark
        )

      assert tags(svg, "text") == []
      assert tags(svg, "line") == []
      refute svg =~ "eexcharts-legend"
      assert length(tags(svg, "path")) == 16
    end

    for {w, h} <- [{160, 24}, {120, 32}] do
      @w w
      @h h
      test "bars stay inside a #{w}x#{h} SVG" do
        series = [%{name: "Series 1", data: @values}]
        opts = spark(%{plot_options: %{bar: %{distributed: true}}})
        svg = static(:bar, series, width: @w, height: @h, options: opts)

        points = bar_points(svg)
        assert length(points) == 16 * 4

        for {x, y} <- points do
          assert x >= 0 and x <= @w
          assert y >= 0 and y <= @h
        end

        assert svg =~ ~s(viewBox="0 0 #{@w} #{@h}")
        assert svg =~ ~s(shape-rendering="crispEdges")
        assert svg =~ "width:#{@w}px;height:#{@h}px"
      end
    end

    test "per-point fill_color and range bars work" do
      data = [%{x: "Item 01", y: 4}, %{x: "Item 02", y: 9, fill_color: "#FF4560"}]

      svg =
        static(:bar, [%{name: "Series 1", data: data}], width: 120, height: 32, options: @spark)

      assert svg =~ ~s(fill="#FF4560")

      rows = [%{x: "Row A", y: [2, 6]}, %{x: "Row B", y: [4, 9]}]
      opts = spark(%{plot_options: %{bar: %{horizontal: true}}})

      svg =
        static(:range_bar, [%{name: "Series 1", data: rows}],
          width: 120,
          height: 32,
          options: opts
        )

      for {x, y} <- bar_points(svg), do: assert(x >= 0 and x <= 120 and y >= 0 and y <= 32)
      assert tags(svg, "text") == []
    end

    test "line markers are not cut off" do
      opts = spark(%{markers: %{size: 4}})

      svg =
        static(:line, [%{name: "Series 1", data: [58, 67, 75]}],
          width: 160,
          height: 24,
          options: opts
        )

      markers = svg |> tags("circle") |> Enum.filter(&(&1 =~ "eexcharts-marker"))
      assert length(markers) == 3

      for m <- markers do
        r = num(m, "r") + 1
        assert num(m, "cx") - r >= 0 and num(m, "cx") + r <= 160
        assert num(m, "cy") - r >= 0 and num(m, "cy") + r <= 24
      end
    end

    test "annotations still render, and data labels can be switched back on" do
      opts =
        spark(%{
          yaxis: %{min: 50, max: 80},
          annotations: %{yaxis: [%{y: 80, stroke_dash_array: 4, label: %{text: "Reference 80"}}]},
          data_labels: %{enabled: true, offset_y: 24},
          grid: %{padding: %{top: 20, bottom: 24}}
        })

      svg =
        static(:line, [%{name: "Series 1", data: [58, 67, 75]}],
          width: 480,
          height: 110,
          options: opts
        )

      assert svg =~ "Reference 80"
      assert svg =~ ~s(stroke-dasharray="4")
      assert svg =~ ">75</text>"
    end

    test "a live sparkline drops the parent height offset" do
      html =
        live(:area, [%{name: "Series 1", data: [1, 3, 2]}],
          width: 160,
          height: 32,
          options: @spark
        )

      refute html =~ "min-height"
      assert html =~ "max-width:160px"
      refute html =~ ~s(shape-rendering)
    end

    test "pie and donut drop the legend and labels" do
      for type <- [:pie, :donut] do
        svg =
          static(type, [30, 50, 20],
            width: 48,
            height: 48,
            labels: ["A", "B", "C"],
            options: @spark
          )

        refute svg =~ "eexcharts-legend"
        assert tags(svg, "text") == []
      end
    end

    test "a radial bar sparkline does not shrink the rings by the stroke" do
      track = fn opts ->
        svg = static(:radial_bar, [68], width: 100, height: 100, options: opts)
        [_, d] = Regex.run(~r/class="eexcharts-radialbar-track" d="M [\d.]+ ([\d.]+)/, svg)
        parse(d)
      end

      # The track starts at the top of its circle: a smaller y means a larger ring.
      assert track.(@spark) < track.(%{})
    end
  end

  describe "themes" do
    @series [%{name: "Series 1", data: [12, 14, 9, 17, 21]}]

    test "dark mode uses the dark palette" do
      svg =
        static(:area, @series, width: 160, height: 32, options: spark(%{theme: %{mode: :dark}}))

      [dark | _] = Config.build(:area, %{theme: %{mode: :dark}}).colors

      assert svg =~ ~s(stroke="#{dark}")
      assert tags(svg, "text") == []
    end

    test "daisy: var() reaches the live output, static output has none" do
      opts = spark(%{theme: %{mode: :daisy}})

      html = live(:bar, @series, width: 160, height: 24, options: opts)
      assert html =~ "var(--color-"

      svg = static(:bar, @series, width: 160, height: 24, options: opts)
      refute svg =~ "var("
    end
  end
end
