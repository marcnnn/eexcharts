defmodule EexCharts.HeatmapAxesTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Renderer}
  alias EexCharts.Charts.Heatmap.{GradientLegend, XLayout}

  @day 86_400_000
  @eps 1.0e-6

  defp render(params) do
    params
    |> Map.put_new(:id, "hm")
    |> Map.put(:type, :heatmap)
    |> Renderer.render()
    |> EexCharts.SVG.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp attr(tag, name) do
    case Regex.run(~r/ #{name}="([^"]*)"/, tag) do
      [_, v] -> v
      nil -> nil
    end
  end

  defp num(tag, name), do: tag |> attr(name) |> Float.parse() |> elem(0)

  # `[%{key: "s-j", x:, w:, y:, fill:}]` for every cell rect.
  defp cells(svg) do
    ~r/<rect class="eexcharts-heatmap-rect"[^>]*>/
    |> Regex.scan(svg)
    |> Enum.map(fn [tag] ->
      %{
        key: attr(tag, "data-j"),
        x: num(tag, "x"),
        w: num(tag, "width"),
        y: num(tag, "y"),
        fill: attr(tag, "fill")
      }
    end)
  end

  defp y_label_x(svg) do
    [tag] = Regex.run(~r/<text[^>]*text-anchor="end"[^>]*>R0<\/text>/, svg)
    num(tag, "x")
  end

  defp numeric_params(xs, extra \\ %{}) do
    Map.merge(
      %{
        width: 600,
        height: 300,
        series:
          for k <- 0..2 do
            %{name: "R#{k}", data: Enum.map(xs, fn x -> %{x: x, y: rem(x * 3 + k * 5, 17)} end)}
          end,
        options: %{xaxis: %{type: :numeric}}
      },
      extra
    )
  end

  # Shared geometric invariants for value-axis cells.
  defp assert_row_invariants(svg, xs, width) do
    all = cells(svg)
    min_x = y_label_x(svg) + 8

    for c <- all do
      assert c.x >= min_x - @eps, "cell starts left of the plot: #{inspect(c)}"
      assert c.x + c.w <= width + @eps, "cell ends right of the chart: #{inspect(c)}"
      assert c.w > 0
    end

    all
    |> Enum.group_by(& &1.y)
    |> Enum.each(fn {_y, row} ->
      # Data order == column order: x positions strictly increase with x value.
      row =
        Enum.sort_by(row, fn c ->
          c.key |> String.split("-") |> List.last() |> String.to_integer()
        end)

      assert length(row) == length(xs)

      row
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        assert b.x > a.x
        assert a.x + a.w <= b.x + @eps, "cells overlap: #{inspect(a)} #{inspect(b)}"
      end)
    end)

    all
  end

  describe "XLayout.extents/2" do
    test "regular data tiles with midpoint boundaries" do
      xs = [1, 2, 3, 4]
      assert XLayout.step(xs, :numeric) == 1
      e = XLayout.extents(xs, 1)
      assert e[1] == {0.5, 1.5}
      assert e[2] == {1.5, 2.5}
      assert e[4] == {3.5, 4.5}
    end

    test "a spacing wider than 1.5 steps leaves a gap" do
      xs = [0, 1, 2, 5, 6]
      step = XLayout.step(xs, :numeric)
      assert step == 1
      e = XLayout.extents(xs, step)
      assert e[2] == {1.5, 2.5}
      assert e[5] == {4.5, 5.5}
      # 2.5 .. 4.5 is empty: two missing columns.
    end

    test "monthly datetime jitter (28-31 days) stays contiguous" do
      months =
        for m <- 1..12 do
          Date.new!(2024, m, 1) |> EexCharts.TimeScale.to_ms()
        end

      step = XLayout.step(months, :datetime)
      e = XLayout.extents(months, step)

      months
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] -> assert elem(e[a], 1) == elem(e[b], 0) end)
    end

    test "a single x value gets a unit step" do
      assert XLayout.step([5], :numeric) == 1
      assert XLayout.step([5], :datetime) == @day
    end
  end

  describe "numeric x-axis" do
    test "cells are monotonic in x, do not overlap and stay inside the plot" do
      xs = [0, 1, 2, 3, 4, 5, 6, 7]
      svg = render(numeric_params(xs))
      all = assert_row_invariants(svg, xs, 600)

      # Regular data: each row tiles the plot with equal widths.
      widths = all |> Enum.map(& &1.w) |> Enum.uniq_by(&Float.round(&1, 4))
      assert length(widths) == 1
    end

    test "missing x values show as a gap one step wide per missing column" do
      xs = [0, 1, 2, 3, 7, 8, 9]
      svg = render(numeric_params(xs))
      all = assert_row_invariants(svg, xs, 600)
      row = all |> Enum.filter(&String.starts_with?(&1.key, "0-")) |> Enum.sort_by(& &1.x)
      w = hd(row).w
      at3 = Enum.at(row, 3)
      at7 = Enum.at(row, 4)
      # 4, 5, 6 are missing: three cell widths of empty space.
      assert_in_delta at7.x - (at3.x + at3.w), 3 * w, 1.0e-6
    end

    test "the x axis gets value labels instead of categories" do
      svg = render(numeric_params([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]))

      labels =
        Regex.scan(~r/class="eexcharts-xaxis-label"[^>]*>([^<]*)</, svg) |> Enum.map(&List.last/1)

      assert "0" in labels and "10" in labels
      refute svg =~ "NaN"
      refute svg =~ "Infinity"
    end

    test "plain-number data takes x from xaxis.categories" do
      svg =
        render(%{
          series: [%{name: "R0", data: [1, 2, 3, 4]}],
          categories: [10, 20, 30, 60],
          options: %{xaxis: %{type: :numeric}}
        })

      [a, b, c, d] = svg |> cells() |> Enum.sort_by(& &1.x)
      assert_in_delta a.w, b.w, 1.0e-6
      # 30 -> 60 is three steps apart: a gap two cells wide.
      assert_in_delta b.w, c.w, 1.0e-6
      assert_in_delta d.x - (c.x + c.w), 2 * a.w, 1.0e-6
    end

    test "xaxis.min/max clip cells to the domain" do
      svg =
        render(
          numeric_params([0, 1, 2, 3, 4, 5], %{
            options: %{xaxis: %{type: :numeric, min: 1, max: 4}}
          })
        )

      all = cells(svg)
      # x = 0 (extent -0.5..0.5) lies outside; 5 (4.5..5.5) too.
      assert all
             |> Enum.map(& &1.key)
             |> Enum.uniq()
             |> Enum.count(&String.starts_with?(&1, "0-")) == 4

      min_x = y_label_x(svg) + 8
      assert Enum.all?(all, &(&1.x >= min_x - @eps and &1.x + &1.w <= 600 + @eps))
    end
  end

  describe "datetime x-axis" do
    test "cells follow time order and missing days leave a gap" do
      t0 = EexCharts.TimeScale.to_ms(~D[2024-03-01])
      days = [0, 1, 2, 3, 6, 7, 8]

      svg =
        render(%{
          width: 700,
          height: 300,
          series:
            for k <- 0..1 do
              %{name: "R#{k}", data: Enum.map(days, fn d -> [t0 + d * @day, d + k] end)}
            end,
          options: %{xaxis: %{type: :datetime}}
        })

      all = assert_row_invariants(svg, days, 700)
      row = all |> Enum.filter(&String.starts_with?(&1.key, "0-")) |> Enum.sort_by(& &1.x)
      w = hd(row).w
      assert_in_delta Enum.at(row, 4).x - (Enum.at(row, 3).x + Enum.at(row, 3).w), 2 * w, 1.0e-6
      assert svg =~ "01 Mar 2024"
    end
  end

  describe "gradient legend" do
    defp grad_params(extra \\ %{}) do
      Map.merge(
        %{
          series: [
            %{name: "R0", data: [2, 40, 10]},
            %{name: "R1", data: [20, 30, 5]}
          ],
          categories: ~w(a b c),
          options: %{colors: ["#008FFB"], legend: %{gradient: true}}
        },
        extra
      )
    end

    defp stops(svg) do
      ~r/<stop offset="([^"%]+)%" stop-color="([^"]+)"/
      |> Regex.scan(svg)
      |> Enum.map(fn [_, off, color] -> {elem(Float.parse(off), 0), color} end)
    end

    defp fill_of(svg, key), do: svg |> cells() |> Enum.find(&(&1.key == key)) |> Map.fetch!(:fill)

    test "end stops match the shade of the min and max cells" do
      svg = render(grad_params())
      [{+0.0, lo}, {100.0, hi}] = stops(svg)
      assert lo == fill_of(svg, "0-0")
      assert hi == fill_of(svg, "0-1")
      refute svg =~ "eexcharts-legend-item"
    end

    test "data spanning zero gets a stop at zero matching the shade there" do
      svg =
        render(
          grad_params(%{
            series: [%{name: "R0", data: [-10, 30, 0]}, %{name: "R1", data: [5, 10, 20]}]
          })
        )

      assert [{+0.0, lo}, {25.0, zero}, {100.0, hi}] = stops(svg)
      assert lo == fill_of(svg, "0-0")
      assert hi == fill_of(svg, "0-1")
      assert zero == fill_of(svg, "0-2")
    end

    test "stops come from the shade function" do
      cfg = Config.build(:heatmap, %{})
      ctx = %{min: 0, max: 50}
      assert [{0, +0.0, "c0"}, {50, 1.0, "c50"}] = GradientLegend.stops(ctx, &"c#{&1}")
      assert GradientLegend.options(cfg, []) == nil
    end

    test "bottom is the default; right is vertical and beside the plot" do
      bottom = render(grad_params())
      [bar] = Regex.run(~r/<rect class="eexcharts-heatmap-gradient-bar"[^>]*>/, bottom)
      assert num(bar, "width") > num(bar, "height")
      max_cell_y = bottom |> cells() |> Enum.map(& &1.y) |> Enum.max()
      assert num(bar, "y") > max_cell_y
      assert bottom =~ ~s(x1="0" x2="1" y1="0" y2="0")

      right =
        render(
          grad_params(%{
            options: %{colors: ["#008FFB"], legend: %{gradient: %{position: :right}}}
          })
        )

      [bar] = Regex.run(~r/<rect class="eexcharts-heatmap-gradient-bar"[^>]*>/, right)
      assert num(bar, "height") > num(bar, "width")
      max_cell_right = right |> cells() |> Enum.map(&(&1.x + &1.w)) |> Enum.max()
      assert num(bar, "x") > max_cell_right
      assert num(bar, "x") + num(bar, "width") <= 600
      # Minimum at the bottom.
      assert right =~ ~s(x1="0" x2="0" y1="1" y2="0")
    end

    test "min and max are labelled" do
      svg = render(grad_params())

      [legend] =
        Regex.run(~r/<g class="eexcharts-legend eexcharts-heatmap-gradient-legend".*?<\/g>/, svg)

      assert legend =~ ">2</text>"
      assert legend =~ ">40</text>"
    end

    test "colour ranges take precedence over the gradient" do
      svg =
        render(
          grad_params(%{
            options: %{
              legend: %{gradient: true},
              plot_options: %{
                heatmap: %{
                  color_scale: %{ranges: [%{from: 0, to: 50, color: "#f00", name: "all"}]}
                }
              }
            }
          })
        )

      refute svg =~ "eexcharts-heatmap-gradient-bar"
      assert svg =~ ">all</text>"
    end

    test "legend.show false hides it" do
      svg = render(grad_params(%{options: %{legend: %{gradient: true, show: false}}}))
      refute svg =~ "eexcharts-heatmap-gradient-bar"
    end
  end
end
