defmodule EexCharts.BarFamilyTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Layout, Renderer}
  alias EexCharts.Charts.{Bar, BarFamily, Dumbbell, Funnel, RangeBar, StackGroups, Waterfall}

  @eps 1.0e-6

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  # The geometry the renderer would use: resolve the shorthand type, build the
  # config, and lay out the grid over the type's own value range.
  defp setup_chart(type, params) do
    params = Map.put_new(params, :id, "t")
    {type, params} = BarFamily.resolve(type, params)
    opts = Map.put(params[:options] || %{}, :xaxis, %{categories: params[:categories] || []})
    opts = Config.deep_merge(params[:options] || %{}, opts)
    cfg = Config.build(type, opts) |> BarFamily.finalize(params)
    series = Renderer.normalize_series(params.series)
    n = series |> Enum.map(&length(&1.data)) |> Enum.max()

    range =
      case type do
        :waterfall -> Waterfall.data_range(series)
        :range_bar -> RangeBar.data_range(series)
        :bar -> StackGroups.data_range(cfg, series) || bar_range(series)
      end

    l = Layout.build(cfg, Enum.map(series, & &1.name), n, range)
    {cfg, series, l}
  end

  defp bar_range(series) do
    vals = Enum.flat_map(series, & &1.data)
    {min(Enum.min(vals), 0), Enum.max(vals)}
  end

  # Data value at pixel y / x (inverse of Layout.y_for / x_for).
  defp value_at_y(l, y) do
    %{nice_min: mn, nice_max: mx} = l.scale
    mn + (l.grid_y + l.grid_h - y) / l.grid_h * (mx - mn)
  end

  defp value_at_x(l, x) do
    %{nice_min: mn, nice_max: mx} = l.scale
    mn + (x - l.grid_x) / l.grid_w * (mx - mn)
  end

  defp no_bad_numbers(svg) do
    refute svg =~ "NaN"
    refute svg =~ "Infinity"
    refute svg =~ "nil"
  end

  describe "waterfall" do
    @data [
      %{x: "Open", y: 120},
      %{x: "Sales", y: 80},
      %{x: "Costs", y: -95},
      %{x: "H1", subtotal: true},
      nil,
      %{x: "Tax", y: -150},
      %{x: "Close", total: true}
    ]

    test "prepare turns changes into floating ranges with running totals" do
      [%{data: pts}] = Waterfall.prepare(%{series: [%{name: "c", data: @data}]}).series

      assert Enum.map(pts, &(&1 && &1.y)) ==
               [[0, 120], [120, 200], [200, 105], [0, 105], nil, [105, -45], [0, -45]]

      assert Enum.map(pts, &(&1 && &1.kind)) ==
               [:increase, :increase, :decrease, :total, nil, :decrease, :total]

      assert Enum.map(pts, &(&1 && &1.total)) == [120, 200, 105, 105, nil, -45, -45]
    end

    test "bar ends sit exactly on the running totals" do
      {cfg, series, l} = setup_chart(:waterfall, %{series: [%{name: "c", data: @data}]})
      rects = Waterfall.positions(cfg, series, l)
      assert length(rects) == 6

      for r <- rects do
        [from, to] = r.point.y
        assert_in_delta value_at_y(l, r.y), max(from, to), @eps
        assert_in_delta value_at_y(l, r.y + r.h), min(from, to), @eps
      end

      # Each bar starts where the previous one ended.
      rects
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [a, b] ->
        if b.point.kind != :total, do: assert(hd(b.point.y) == a.point.total)
      end)
    end

    test "connectors run from one bar's end to the next bar's start at the running total" do
      {cfg, series, l} = setup_chart(:waterfall, %{series: [%{name: "c", data: @data}]})
      rects = Waterfall.positions(cfg, series, l)
      segs = Waterfall.connector_segments(rects, l)
      assert length(segs) == length(rects) - 1

      Enum.zip([segs, rects, tl(rects)])
      |> Enum.each(fn {{x1, y, x2, y}, a, b} ->
        assert_in_delta x1, a.x + a.w, @eps
        assert_in_delta x2, b.x, @eps
        assert_in_delta value_at_y(l, y), a.point.total, @eps
      end)
    end

    test "colours by kind and tooltips show signed change and running total" do
      svg =
        render(%{
          id: "w",
          type: :waterfall,
          series: [%{name: "Cash", data: Enum.reject(@data, &is_nil/1)}],
          options: %{plot_options: %{waterfall: %{colors: %{increase: "#0a0", decrease: "#a00"}}}}
        })

      no_bad_numbers(svg)
      assert svg =~ ~r/class="eexcharts-bar eexcharts-waterfall-increase"[^>]*fill="#0a0"/
      assert svg =~ ~r/class="eexcharts-bar eexcharts-waterfall-decrease"[^>]*fill="#a00"/
      assert svg =~ ~r/class="eexcharts-bar eexcharts-waterfall-total"[^>]*fill="#008FFB"/
      assert svg =~ "+80"
      assert svg =~ ~r/Total: <\/span><span class="eexcharts-tip-value">200</
      # categories come from the x labels
      assert svg =~ ">Sales<"
      assert length(Regex.scan(~r/eexcharts-waterfall-connector/, svg)) == 5
    end

    test "connectors can be turned off" do
      svg =
        render(%{
          id: "w",
          type: :waterfall,
          series: [[10, -5, 7]],
          options: %{plot_options: %{waterfall: %{connector: %{show: false}}}}
        })

      refute svg =~ "eexcharts-waterfall-connector"
    end
  end

  describe "funnel and pyramid" do
    @values [1380, 1100, 990, 880, 740, 548]
    @cats ~w(a b c d e f)

    test "bars are centred on the plot midline, widths proportional to value" do
      {cfg, series, l} =
        setup_chart(:funnel, %{series: [%{name: "v", data: @values}], categories: @cats})

      assert l.horizontal
      rects = Bar.positions(cfg, series, l)
      mid = l.grid_x + l.grid_w / 2
      per_unit = l.grid_w / (l.scale.nice_max - l.scale.nice_min)

      for r <- rects do
        assert_in_delta r.x + r.w / 2, mid, @eps
        assert_in_delta r.w, r.value * per_unit, @eps
      end

      # Drawn top to bottom in data order.
      ys = Enum.map(rects, & &1.y)
      assert ys == Enum.sort(ys)
    end

    test "3d connectors are symmetric trapezoids joining consecutive stages" do
      {cfg, series, l} =
        setup_chart(:funnel, %{series: [%{name: "v", data: @values}], categories: @cats})

      rects = Bar.positions(cfg, series, l)
      mid = l.grid_x + l.grid_w / 2
      conns = Funnel.connectors(cfg, rects)
      assert length(conns) == length(rects) - 1

      Enum.zip([conns, rects, tl(rects)])
      |> Enum.each(fn {{:el, "path", %{d: d}, _}, a, b} ->
        [{:move, x1, y1}, {:line, x2, y2}, {:line, x3, y3}, {:line, x4, y4}, :close] = d
        assert_in_delta (x1 + x2) / 2, mid, @eps
        assert_in_delta (x3 + x4) / 2, mid, @eps
        assert_in_delta y1, a.y + a.h, @eps
        assert y1 == y2 and y3 == y4
        assert_in_delta y3, b.y, @eps
      end)
    end

    test "is_funnel_3d: false drops the connectors" do
      svg =
        render(%{
          id: "f",
          type: :bar,
          series: [%{name: "v", data: [3, 2, 1]}],
          options: %{plot_options: %{bar: %{is_funnel: true, is_funnel_3d: false}}}
        })

      refute svg =~ "eexcharts-funnel-connector"
      assert length(Regex.scan(~r/class="eexcharts-bar"/, svg)) == 3
    end

    test "pyramid puts the first data point at the bottom" do
      {cfg, series, l} =
        setup_chart(:pyramid, %{series: [%{name: "v", data: [30, 20, 10]}], categories: ~w(x y z)})

      rects = Bar.positions(cfg, series, l)
      bottom = Enum.max_by(rects, & &1.y)
      assert bottom.value == 30

      svg = render(%{id: "p", type: :pyramid, series: [[30, 20, 10]], categories: ~w(x y z)})
      no_bad_numbers(svg)
      # Category labels are listed top to bottom: z, y, x.
      labels =
        Regex.scan(~r/class="eexcharts-xaxis-label"[^>]*>([xyz])</, svg) |> Enum.map(&List.last/1)

      assert labels == ~w(z y x)
    end

    test "funnel shorthand hides grid and value axis but keeps stage labels" do
      svg = render(%{id: "f", type: :funnel, series: [[3, 2, 1]], categories: ~w(x y z)})
      refute svg =~ "eexcharts-grid-line"
      refute svg =~ "eexcharts-yaxis-labels"
      assert svg =~ ">x<"
    end
  end

  describe "dumbbell" do
    @pairs [[42, 61], [55, 78], [47, 44]]

    test "vertical: dot centres sit at the two values" do
      {cfg, series, l} =
        setup_chart(:dumbbell, %{series: [%{name: "s", data: @pairs}], categories: ~w(a b c)})

      dbs = Dumbbell.positions(series, cfg, l)
      assert length(dbs) == 3

      Enum.zip(dbs, @pairs)
      |> Enum.each(fn {d, [from, to]} ->
        {x1, y1} = d.from
        {x2, y2} = d.to
        assert x1 == x2
        assert_in_delta value_at_y(l, y1), from, @eps
        assert_in_delta value_at_y(l, y2), to, @eps
        assert_in_delta x1, Layout.category_pos(l, d.index), @eps
      end)
    end

    test "horizontal: dot centres sit at the two values" do
      {cfg, series, l} =
        setup_chart(:dumbbell, %{
          series: [%{name: "s", data: @pairs}],
          categories: ~w(a b c),
          options: %{plot_options: %{bar: %{horizontal: true}}}
        })

      assert l.horizontal

      for {d, [from, to]} <- Enum.zip(Dumbbell.positions(series, cfg, l), @pairs) do
        {x1, y1} = d.from
        {x2, y2} = d.to
        assert y1 == y2
        assert_in_delta value_at_x(l, x1), from, @eps
        assert_in_delta value_at_x(l, x2), to, @eps
      end
    end

    test "ends legend lists both ends in the dot colours" do
      svg =
        render(%{
          id: "d",
          type: :dumbbell,
          series: [%{name: "s", ends: ["2015", "2025"], data: [%{x: "A", y: [1, 2]}]}]
        })

      no_bad_numbers(svg)
      assert svg =~ ">2015<"
      assert svg =~ ">2025<"
      assert svg =~ ~r/eexcharts-dumbbell-start"[^>]*fill="#008FFB"/
      assert svg =~ ~r/eexcharts-dumbbell-end"[^>]*fill="#00E396"/
      assert svg =~ ~r/eexcharts-legend-marker"[^>]*fill="#008FFB"/
      assert svg =~ ~r/eexcharts-legend-marker"[^>]*fill="#00E396"/
      # category from the x label
      assert svg =~ ">A<"
    end

    test "v4.7.0 is_dumbbell uses the series colour for both ends by default" do
      svg =
        render(%{
          id: "d",
          type: :range_bar,
          series: [%{name: "s", data: [[1, 2]]}],
          options: %{plot_options: %{bar: %{is_dumbbell: true}}, colors: ["#123456"]}
        })

      assert svg =~ ~r/eexcharts-dumbbell-start"[^>]*fill="#123456"/
      assert svg =~ ~r/eexcharts-dumbbell-end"[^>]*fill="#123456"/
      assert svg =~ ~r/eexcharts-dumbbell-line"[^>]*stroke-width="2"/
    end

    test "dumbbell_colors pairs per series" do
      cfg =
        Config.build(:range_bar, %{plot_options: %{bar: %{dumbbell_colors: [["#a", "#b"], "#c"]}}})

      assert Dumbbell.end_colors(cfg, 0) == {"#a", "#b"}
      assert Dumbbell.end_colors(cfg, 1) == {"#c", "#c"}
    end
  end

  describe "grouped stacks" do
    @series [
      %{name: "a1", group: "A", data: [44, 55, 0]},
      %{name: "a2", group: "A", data: [13, 23, 20]},
      %{name: "b1", group: "B", data: [48, 50, 40]},
      %{name: "b2", group: "B", data: [10, 30, 22]}
    ]

    test "series of one group stack contiguously; groups sit side by side" do
      {cfg, series, l} =
        setup_chart(:bar, %{
          series: @series,
          categories: ~w(x y z),
          options: %{chart: %{stacked: true}}
        })

      rects = StackGroups.positions(cfg, series, l)

      for j <- 0..2 do
        at_j = Enum.filter(rects, &(&1.index == j))
        [ga, gb] = at_j |> Enum.group_by(& &1.group) |> Enum.sort() |> Enum.map(&elem(&1, 1))

        # stacks contiguous: each segment starts where the one below ends
        for g <- [ga, gb] do
          g
          |> Enum.reject(&(&1.h == 0))
          |> Enum.chunk_every(2, 1, :discard)
          |> Enum.each(fn [below, above] -> assert_in_delta above.y + above.h, below.y, @eps end)

          assert Enum.uniq(Enum.map(g, & &1.x)) |> length() == 1
        end

        # side by side, not overlapping
        assert hd(ga).x + hd(ga).w <= hd(gb).x + @eps

        # stack height = group sum
        sum_a = Enum.sum(Enum.map(ga, & &1.value))
        top_a = Enum.min_by(ga, & &1.y)
        assert_in_delta value_at_y(l, top_a.y), sum_a, @eps
      end
    end

    test "value range covers the largest group stack, not the sum of all" do
      cfg = Config.build(:bar, %{chart: %{stacked: true}})
      series = Renderer.normalize_series(@series)
      assert StackGroups.data_range(cfg, series) == {0, 80}
    end

    test "100%: every group's stack fills the plot height independently" do
      {cfg, series, l} =
        setup_chart(:bar, %{
          series: @series,
          categories: ~w(x y z),
          options: %{chart: %{stacked: true, stack_type: "100%"}}
        })

      assert {l.scale.nice_min, l.scale.nice_max} == {0, 100}
      rects = StackGroups.positions(cfg, series, l)

      for j <- 0..2, g <- [0, 1] do
        total =
          rects
          |> Enum.filter(&(&1.index == j and &1.group == g))
          |> Enum.map(& &1.h)
          |> Enum.sum()

        assert_in_delta total, l.grid_h, @eps
      end
    end

    test "100% without groups treats all series as one stack" do
      {cfg, series, l} =
        setup_chart(:bar, %{
          series: [[1, 2], [3, 2]],
          options: %{chart: %{stacked: true, stack_type: "100%"}}
        })

      rects = StackGroups.positions(cfg, series, l)

      for j <- 0..1 do
        total = rects |> Enum.filter(&(&1.index == j)) |> Enum.map(& &1.h) |> Enum.sum()
        assert_in_delta total, l.grid_h, @eps
      end
    end

    test "horizontal grouped stacks render without bad numbers" do
      svg =
        render(%{
          id: "g",
          type: :bar,
          series: @series,
          categories: ~w(x y z),
          options: %{chart: %{stacked: true}, plot_options: %{bar: %{horizontal: true}}}
        })

      no_bad_numbers(svg)
      assert length(Regex.scan(~r/class="eexcharts-bar"/, svg)) == 12
    end

    test "plain stacked bars without groups keep the original layout" do
      cfg = Config.build(:bar, %{chart: %{stacked: true}})
      refute StackGroups.applies?(cfg, Renderer.normalize_series([[1, 2], [3, 4]]))
    end
  end

  test "custom legend items replace series names and disable toggling" do
    svg =
      render(%{
        id: "l",
        type: :bar,
        series: [[1, 2]],
        on_legend_click: "toggle",
        options: %{
          legend: %{
            custom_legend_items: ["Up", "Down"],
            markers: %{fill_colors: ["#111", "#222"]}
          }
        }
      })

    assert svg =~ ">Up<"
    assert svg =~ ~r/eexcharts-legend-marker"[^>]*fill="#222"/
    refute svg =~ ~s(phx-click="toggle")
  end

  test "every bar-family example renders in live and static mode" do
    for ex <- Dev.ChartExamples.BarFamily.examples() do
      params = Map.drop(ex, [:title, :group])
      no_bad_numbers(render(params))
      no_bad_numbers(render(Map.put(params, :static, true)))
    end
  end
end
