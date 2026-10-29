defmodule EexCharts.WaterfallHorizontalTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Layout, Renderer}
  alias EexCharts.Charts.{BarFamily, Waterfall}

  @eps 1.0e-6

  @data [
    %{x: "Start", y: 25},
    %{x: "Decrease", y: -12},
    %{x: "Increase", y: 5},
    %{x: "End", total: true}
  ]

  @horizontal %{plot_options: %{bar: %{horizontal: true}}}

  defp live(series, options) do
    {:safe, io} = EexCharts.render("w", :waterfall, series, options: options)
    IO.iodata_to_binary(io)
  end

  defp static(series, options), do: EexCharts.to_svg("w", :waterfall, series, options: options)

  defp tags(svg, tag), do: Regex.scan(~r/<#{tag}\b[^>]*>/, svg) |> List.flatten()

  defp bars(svg), do: svg |> tags("path") |> Enum.filter(&(&1 =~ "eexcharts-waterfall-"))

  defp bar(svg, kind), do: svg |> bars() |> Enum.filter(&(&1 =~ "eexcharts-waterfall-#{kind}"))

  defp setup_chart(series, options) do
    {type, params} = BarFamily.resolve(:waterfall, %{id: "t", series: series})
    cfg = Config.build(type, options) |> BarFamily.finalize(params)
    series = Renderer.normalize_series(params.series)
    n = series |> Enum.map(&length(&1.data)) |> Enum.max()
    l = Layout.build(cfg, Enum.map(series, & &1.name), n, Waterfall.data_range(series))
    {cfg, series, l}
  end

  defp value_at_x(l, x) do
    %{nice_min: mn, nice_max: mx} = l.scale
    mn + (x - l.grid_x) / l.grid_w * (mx - mn)
  end

  describe "horizontal" do
    setup do
      {cfg, series, l} = setup_chart([%{name: "c", data: @data}], @horizontal)
      %{cfg: cfg, l: l, rects: Waterfall.positions(cfg, series, l)}
    end

    test "uses the horizontal layout, first category at the top", %{l: l, rects: rects} do
      assert l.horizontal
      ys = Enum.map(rects, & &1.y)
      assert ys == Enum.sort(ys)
      assert hd(ys) < l.grid_y + l.grid_h / length(rects)
    end

    test "bars float between running totals on the value axis", %{l: l, rects: rects} do
      Enum.each(rects, fn r ->
        [from, to] = r.point.y
        assert_in_delta value_at_x(l, r.x), min(from, to), @eps
        assert_in_delta value_at_x(l, r.x + r.w), max(from, to), @eps
      end)
    end

    test "connectors are vertical at the shared running total", %{l: l, rects: rects} do
      segs = Waterfall.connector_segments(rects, l)
      assert length(segs) == 3

      Enum.zip([segs, rects, tl(rects)])
      |> Enum.each(fn {{x, y1, x, y2}, a, b} ->
        assert_in_delta y1, a.y + a.h, @eps
        assert_in_delta y2, b.y, @eps
        assert_in_delta value_at_x(l, x), a.point.total, @eps
      end)
    end

    test "several series sit side by side within a category" do
      series = [%{name: "a", data: [10, -4]}, %{name: "b", data: [6, 3]}]
      {cfg, series, l} = setup_chart(series, @horizontal)
      [a0, a1, b0, b1] = Waterfall.positions(cfg, series, l)

      assert_in_delta b0.y, a0.y + a0.h, @eps
      assert_in_delta b1.y, a1.y + a1.h, @eps
      assert a1.y > b0.y
    end

    test "renders categories on the left, labels and tooltips" do
      svg = live([%{name: "Count", data: @data}], @horizontal)

      assert length(bars(svg)) == 4
      assert length(Regex.scan(~r/eexcharts-waterfall-connector/, svg)) == 3

      for label <- ~w(Start Decrease Increase End),
          do: assert(svg =~ ~r/text-anchor="end"[^>]*>#{label}</)

      assert svg =~ ~r/class="eexcharts-datalabel"[^>]*>-12</
      assert svg =~ ">+5<"
      assert svg =~ ~s(data-cy=)
    end
  end

  describe "per-kind styles" do
    test "a colour, :outline and a fill map per kind" do
      colors = %{
        increase: "#ff6105",
        decrease: :outline,
        total: %{fill: %{type: :pattern, pattern: %{style: :slanted_lines}}}
      }

      svg = live([%{name: "c", data: @data}], %{plot_options: %{waterfall: %{colors: colors}}})

      assert [_, inc] = bar(svg, "increase")
      assert inc =~ ~s(fill="#ff6105")

      assert [dec] = bar(svg, "decrease")
      assert dec =~ ~s(fill="none")
      assert dec =~ ~s(stroke="#FF4560")
      assert dec =~ ~s(stroke-width="2")

      assert [total] = bar(svg, "total")
      assert total =~ ~s|fill="url(#w-pattern-0)"|
      assert svg =~ ~r/<pattern[^>]*id="w-pattern-0".*?stroke="#008FFB"/s

      # The outline bar's label sits on the page, in the outline colour.
      assert svg =~ ~r/class="eexcharts-datalabel"[^>]*fill="#FF4560"[^>]*>-12</ or
               svg =~ ~r/fill="#FF4560"[^>]*class="eexcharts-datalabel"[^>]*>-12</
    end

    test "a map with a colour, on a vertical chart" do
      colors = %{decrease: %{color: "#123456", fill: %{type: :none}}}
      svg = live([%{name: "c", data: @data}], %{plot_options: %{waterfall: %{colors: colors}}})

      assert [dec] = bar(svg, "decrease")
      assert dec =~ ~s(fill="none")
      assert dec =~ ~s(stroke="#123456")
    end

    test "per-point paint beats the kind's fill" do
      data = [%{x: "a", y: 3}, %{x: "b", y: -1, fill_color: "#abcdef", fill: %{type: :solid}}]

      svg =
        live([%{name: "c", data: data}], %{
          plot_options: %{waterfall: %{colors: %{decrease: :outline}}}
        })

      assert [dec] = bar(svg, "decrease")
      assert dec =~ ~s(fill="#abcdef")
    end
  end

  describe "themes" do
    test "dark keeps the kind and connector colours" do
      svg = static([%{name: "c", data: @data}], Map.put(@horizontal, :theme, %{mode: :dark}))

      assert [_, inc] = bar(svg, "increase")
      assert inc =~ ~s(fill="#00E396")
      assert svg =~ ~r/eexcharts-waterfall-connector[^>]*stroke="#a8a8a8"/
    end

    test "daisy live: kinds, outlines, connectors and labels take daisyUI variables" do
      options = %{
        theme: %{mode: :daisy},
        plot_options: %{bar: %{horizontal: true}, waterfall: %{colors: %{decrease: :outline}}}
      }

      svg = live([%{name: "c", data: @data}], options)

      assert [_, inc] = bar(svg, "increase")
      assert inc =~ ~s|fill="var(--color-success, #00E396)"|
      assert [dec] = bar(svg, "decrease")
      assert dec =~ ~s|stroke="var(--color-error, #FF4560)"|
      assert [total] = bar(svg, "total")
      assert total =~ ~s|fill="var(--color-primary, #008FFB)"|

      assert svg =~
               ~r/eexcharts-waterfall-connector[^>]*stroke="var\(--color-base-300, #a8a8a8\)"/

      assert svg =~ ~s|fill="var(--color-success-content, #fff)"|
      assert svg =~ ~s|fill="var(--color-primary-content, #fff)"|
    end

    test "daisy keeps colours the user set" do
      options = %{
        theme: %{mode: :daisy},
        plot_options: %{waterfall: %{colors: %{increase: "#ff6105"}, connector: %{color: "#000"}}}
      }

      svg = live([%{name: "c", data: @data}], options)
      assert [_, inc] = bar(svg, "increase")
      assert inc =~ ~s(fill="#ff6105")
      refute svg =~ "--color-success"
      assert svg =~ ~r/eexcharts-waterfall-connector[^>]*stroke="#000"/

      # A user-coloured kind keeps the type's white label, not a daisyUI content colour.
      assert svg =~ ~r/fill="#fff"[^>]*>25</
    end

    test "daisy static resolves every variable to its light fallback" do
      options = %{
        theme: %{mode: :daisy},
        plot_options: %{bar: %{horizontal: true}, waterfall: %{colors: %{decrease: :outline}}}
      }

      svg = static([%{name: "c", data: @data}], options)

      refute svg =~ "var("
      assert [dec] = bar(svg, "decrease")
      assert dec =~ ~s(stroke="#FF4560")
      assert svg =~ ~r/eexcharts-waterfall-connector[^>]*stroke="#a8a8a8"/
    end
  end
end
