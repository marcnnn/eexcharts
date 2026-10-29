defmodule EexCharts.UnitChartTest do
  use ExUnit.Case, async: true

  alias EexCharts.Charts.Unit
  alias EexCharts.Config

  defp geo(type, series, opts \\ %{}, params \\ %{}) do
    cfg = Config.build(type, opts)
    Unit.geometry(cfg, Map.merge(%{series: series}, params))
  end

  defp svg(type, series, opts \\ []) do
    EexCharts.to_svg("u", type, series, opts)
  end

  defp count_by_group(geo), do: geo.marks |> Enum.frequencies_by(& &1.group)

  defp dist(a, b), do: :math.sqrt(:math.pow(a.cx - b.cx, 2) + :math.pow(a.cy - b.cy, 2))

  defp pairs(list) do
    list
    |> Enum.with_index()
    |> Enum.flat_map(fn {a, i} -> list |> Enum.drop(i + 1) |> Enum.map(&{a, &1}) end)
  end

  describe "largest_remainder/2" do
    test "worked examples" do
      # 100 / 3 = 33.33 each: one leftover unit, first index wins the tie.
      assert Unit.largest_remainder([1, 1, 1], 100) == [34, 33, 33]
      # quotas 46.3 31.9 13.5 8.3: floors 46 31 13 8 = 98, the two largest
      # remainders (.9 and .5) take the leftovers.
      assert Unit.largest_remainder([46.3, 31.9, 13.5, 8.3], 100) == [46, 32, 14, 8]
      assert Unit.largest_remainder([57, 28, 15], 100) == [57, 28, 15]
    end

    test "always sums to the total" do
      for values <- [[1, 2, 3, 4, 5, 6, 7], [0.1, 0.1, 99.8], [3, 3, 3, 3, 3, 3], [1.0e-3, 7]] do
        assert Enum.sum(Unit.largest_remainder(values, 100)) == 100
        assert Enum.sum(Unit.largest_remainder(values, 37)) == 37
      end
    end

    test "zero or negative input gives zeros" do
      assert Unit.largest_remainder([0, 0], 100) == [0, 0]
      assert Unit.largest_remainder([-3, 0], 100) == [0, 0]
      assert Unit.largest_remainder([-3, 5], 10) == [0, 10]
    end
  end

  describe "unit grid" do
    test "mark count per category is round(value / per_unit)" do
      g = geo(:unit, [420, 310, 184, 85, 14], %{plot_options: %{unit: %{per_unit: 10}}})
      assert count_by_group(g) == %{0 => 42, 1 => 31, 2 => 18, 3 => 9, 4 => 1}
      assert g.per_unit == 10
    end

    test "series maps and x/y points are accepted" do
      g = geo(:unit, [%{name: "A", data: 3}, %{name: "B", data: [2, 2]}])
      assert count_by_group(g) == %{0 => 3, 1 => 4}
      assert Enum.map(g.groups, & &1.name) == ["A", "B"]

      g = geo(:unit, [%{data: [%{x: "P", y: 5}, %{x: "Q", y: 2}]}])
      assert count_by_group(g) == %{0 => 5, 1 => 2}
      assert Enum.map(g.groups, & &1.name) == ["P", "Q"]
    end

    test "max_units raises per_unit along the 1/2/5 ladder" do
      g = geo(:unit, [1_000_000], %{plot_options: %{unit: %{max_units: 2000}}})
      assert g.per_unit == 500
      assert length(g.marks) == 2000
    end

    test "marks stay inside the plot and do not overlap" do
      for shape <- [:square, :rounded_square, :circle], order <- [:row, :column] do
        g =
          geo(:unit, [23, 9, 4, 17], %{
            plot_options: %{unit: %{shape: shape, fill_order: order, gap: 3}}
          })

        l = g.layout

        for m <- g.marks do
          assert m.cx - m.size / 2 >= l.grid_x - 1.0e-6
          assert m.cx + m.size / 2 <= l.grid_x + l.grid_w + 1.0e-6
          assert m.cy - m.size / 2 >= l.grid_y - 1.0e-6
          assert m.cy + m.size / 2 <= l.grid_y + l.grid_h + 1.0e-6
        end

        # Square cells: centres at least size + gap apart on one axis.
        for {a, b} <- pairs(g.marks) do
          assert max(abs(a.cx - b.cx), abs(a.cy - b.cy)) >= a.size + 3 - 1.0e-6
        end
      end
    end

    test "fill order: row fills left to right, column fills top to bottom" do
      g = geo(:unit, [5], %{plot_options: %{unit: %{rows: 2, columns: 3}}})
      [a, b | _] = g.marks
      assert a.cy == b.cy and b.cx > a.cx

      g = geo(:unit, [5], %{plot_options: %{unit: %{rows: 2, columns: 3, fill_order: :column}}})
      [a, b | _] = g.marks
      assert a.cx == b.cx and b.cy > a.cy
    end

    test "fixed dimensions grow when too small" do
      g = geo(:unit, [10], %{plot_options: %{unit: %{rows: 2, columns: 2}}})
      assert length(g.marks) == 10
      assert g.marks |> Enum.map(& &1.cx) |> Enum.uniq() |> length() == 2
    end

    test "hidden categories are dropped from the marks, kept in the legend" do
      out = svg(:unit, [3, 4, 5], labels: ~w(a b c), hidden_series: [1])
      g = geo(:unit, [3, 4, 5], %{}, %{hidden_series: [1]})
      assert count_by_group(g) == %{0 => 3, 2 => 5}
      assert out =~ ">b<"
    end

    test "svg draws one primitive per mark and no NaN" do
      out = svg(:unit, [7, 5], options: %{plot_options: %{unit: %{shape: :circle}}})
      assert length(Regex.scan(~r/<circle /, out)) >= 12
      refute out =~ "NaN"
      refute out =~ "Infinity"
    end

    test "tooltips: one per mark group" do
      {:safe, io} = EexCharts.render("u", :unit, [7, 5, 2], labels: ~w(a b c))
      html = IO.iodata_to_binary(io)
      assert length(Regex.scan(~r/class="eexcharts-tip"/, html)) == 3
      assert length(Regex.scan(~r/class="eexcharts-unit-group" data-j=/, html)) == 3
    end

    test "degenerate data renders" do
      for series <- [[], [0, 0], [-4], nil] do
        out = svg(:unit, series)
        assert out =~ "<svg"
        refute out =~ "NaN"
      end

      for layout <- [:parliament, :beeswarm] do
        out = svg(:unit, [], options: %{plot_options: %{unit: %{layout: layout}}})
        assert out =~ "<svg"
      end
    end
  end

  describe "waffle" do
    test "exactly 100 cells, one percent each" do
      g = geo(:waffle, [46.3, 31.9, 13.5, 8.3])
      assert length(g.marks) == 100
      assert count_by_group(g) == %{0 => 46, 1 => 32, 2 => 14, 3 => 8}
      assert g.marks |> Enum.map(&{&1.cx, &1.cy}) |> Enum.uniq() |> length() == 100
    end

    test "hidden categories: the rest is re-shared to 100" do
      g = geo(:waffle, [1, 1, 2], %{}, %{hidden_series: [2]})
      assert count_by_group(g) == %{0 => 50, 1 => 50}
    end

    test "a 10 x 10 grid" do
      g = geo(:waffle, [3, 7])
      assert g.marks |> Enum.map(& &1.cx) |> Enum.uniq() |> length() == 10
      assert g.marks |> Enum.map(& &1.cy) |> Enum.uniq() |> length() == 10
    end

    test "tooltip shows the percent" do
      {:safe, io} = EexCharts.render("w", :waffle, [3, 1], labels: ~w(a b))
      html = IO.iodata_to_binary(io)
      assert html =~ "3 (75%)"
      assert html =~ "1 (25%)"
    end
  end

  describe "parliament" do
    @seats [42, 115, 23, 67, 98, 36, 19]
    @opts %{plot_options: %{unit: %{layout: :parliament, shape: :circle}}}

    test "one seat per unit, none overlapping" do
      g = geo(:unit, @seats, @opts)
      assert length(g.marks) == Enum.sum(@seats)
      assert count_by_group(g) == @seats |> Enum.with_index(&{&2, &1}) |> Map.new()

      for {a, b} <- pairs(g.marks), do: assert(dist(a, b) >= a.size - 1.0e-6)
    end

    test "seats fill each arc evenly, inside the plot, above the baseline" do
      g = geo(:unit, @seats, @opts)
      {cx, cy, inner} = g.center
      l = g.layout

      rows =
        Enum.group_by(g.marks, fn m ->
          Float.round(:math.sqrt(:math.pow(m.cx - cx, 2) + :math.pow(m.cy - cy, 2)), 4)
        end)

      assert map_size(rows) > 1

      for {r, ms} <- rows do
        assert r > inner
        n = length(ms)

        angles =
          ms |> Enum.map(fn m -> :math.atan2(cy - m.cy, m.cx - cx) end) |> Enum.sort()

        # Evenly spaced at (k + 0.5) * pi / n: the arc is filled end to end.
        angles
        |> Enum.with_index()
        |> Enum.each(fn {a, k} -> assert_in_delta a, (k + 0.5) * :math.pi() / n, 1.0e-9 end)
      end

      # Seats per row are proportional to the row radius.
      total = Enum.sum(@seats)
      radius_sum = rows |> Map.keys() |> Enum.sum()

      for {r, ms} <- rows do
        assert abs(length(ms) - total * r / radius_sum) < 1
      end

      for m <- g.marks do
        assert m.cy <= cy + 1.0e-9
        assert m.cx - m.size / 2 >= l.grid_x - 1.0e-6
        assert m.cx + m.size / 2 <= l.grid_x + l.grid_w + 1.0e-6
        assert m.cy - m.size / 2 >= l.grid_y - 1.0e-6
        assert m.cy + m.size / 2 <= l.grid_y + l.grid_h + 1.0e-6
      end
    end

    test "parties form wedges: angle ranges do not interleave" do
      g = geo(:unit, @seats, @opts)
      {cx, cy, _} = g.center

      ranges =
        g.marks
        |> Enum.group_by(& &1.group, fn m -> :math.atan2(cy - m.cy, m.cx - cx) end)
        |> Enum.sort()
        |> Enum.map(fn {_, as} -> Enum.min_max(as) end)

      ranges
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [{lo, _}, {_, hi_next}] -> assert hi_next <= lo + 1.0e-9 end)
    end

    test "explicit row count" do
      g = geo(:unit, [10, 10], put_in(@opts, [:plot_options, :unit, :parliament], %{rows: 2}))
      {cx, cy, _} = g.center

      radii =
        g.marks
        |> Enum.map(
          &Float.round(:math.sqrt(:math.pow(&1.cx - cx, 2) + :math.pow(&1.cy - cy, 2)), 4)
        )
        |> Enum.uniq()

      assert length(radii) == 2
    end

    test "total label in the centre" do
      out = svg(:unit, @seats, options: @opts)
      assert out =~ ~r/class="eexcharts-unit-total"[^>]*>400</
    end
  end

  describe "beeswarm" do
    @swarm [
      %{name: "A", data: [1, 1, 1, 1, 2, 2.1, 2.2, 3, 5, 5, 5, 5, 5, 5]},
      %{name: "B", data: [%{x: 4, label: "p"}, {"q", 4.05}, 4.1, 6]}
    ]
    @bopts %{plot_options: %{unit: %{layout: :beeswarm, size: 10, gap: 1}}}

    test "keeps x exact and never overlaps" do
      g = geo(:unit, @swarm, @bopts)
      assert length(g.marks) == 18

      for m <- g.marks, do: assert(m.cx == g.x_for.(m.x))

      for {a, b} <- pairs(g.marks), do: assert(dist(a, b) >= a.size + 1 - 1.0e-6)
    end

    test "stays inside the plot and is deterministic" do
      g = geo(:unit, @swarm, @bopts)
      l = g.layout

      for m <- g.marks do
        assert m.cy - m.size / 2 >= l.grid_y - 1.0e-6
        assert m.cy + m.size / 2 <= l.grid_y + l.grid_h + 1.0e-6
      end

      assert geo(:unit, @swarm, @bopts).marks == g.marks
    end

    test "shrinks marks when the swarm is too tall" do
      g = geo(:unit, [List.duplicate(3, 80)], Map.put(@bopts, :chart, %{height: 200}))
      l = g.layout
      assert g.size < 10

      for m <- g.marks, do: assert(m.cy + m.size / 2 <= l.grid_y + l.grid_h + 1.0e-6)
      for {a, b} <- pairs(g.marks), do: assert(dist(a, b) >= a.size + g.gap - 1.0e-6)
    end

    test "swarm/2 worked example" do
      # Three marks at one x with d = 10: centre, then up, then down.
      assert Unit.swarm([0, 0, 0], 10) == [0.0, 10.0, -10.0]
      # A neighbour 6 px away sits on the tangent: sqrt(100 - 36) = 8.
      assert Unit.swarm([0, 6], 10) == [0.0, 8.0]
      # Far apart: both on the axis.
      assert Unit.swarm([0, 20], 10) == [0.0, 0.0]
    end

    test "per-point tooltips and circles by default" do
      {:safe, io} = EexCharts.render("b", :unit, @swarm, options: @bopts)
      html = IO.iodata_to_binary(io)
      assert length(Regex.scan(~r/class="eexcharts-tip"/, html)) == 18
      assert length(Regex.scan(~r/<circle [^>]*data-j=/, html)) == 18
      assert html =~ ~s(data-j="1-0")
    end
  end
end
