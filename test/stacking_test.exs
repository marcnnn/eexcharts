defmodule EexCharts.StackingTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Renderer, Stacking}

  defp annotate(type, data_rows, opts \\ %{}) do
    cfg = Config.build(type, opts) |> Stacking.prepare()
    series = Renderer.normalize_series(Enum.map(data_rows, &%{data: &1}))
    n = data_rows |> Enum.map(&length/1) |> Enum.max()
    Stacking.annotate(cfg, series, n)
  end

  defp svg(type, rows, opts) do
    series = Enum.with_index(rows, fn r, i -> %{name: "s#{i}", data: r} end)
    EexCharts.to_svg("t", type, series, options: opts)
  end

  defp html(type, rows, opts) do
    series = Enum.with_index(rows, fn r, i -> %{name: "s#{i}", data: r} end)
    {:safe, io} = EexCharts.render("t", type, series, options: opts, hook: false)
    IO.iodata_to_binary(io)
  end

  @rows [[31, 40, 28, 51], [11, 32, 45, 32], [15, 11, 32, 18]]

  describe "stacked line / area" do
    test "is off unless chart.stacked is set" do
      refute Stacking.enabled?(Config.build(:area, %{}))
      refute Stacking.enabled?(Config.build(:bar, %{chart: %{stacked: true}}))
      assert Stacking.enabled?(Config.build(:line, %{chart: %{stacked: true}}))
      assert Stacking.enabled?(Config.build(:streamgraph, %{}))
    end

    for type <- [:line, :area] do
      test "#{type}: each category's stack tops equal the cumulative sums" do
        stacked = annotate(unquote(type), @rows, %{chart: %{stacked: true}})

        for j <- 0..3 do
          cums = @rows |> Enum.map(&Enum.at(&1, j)) |> Enum.scan(&+/2)
          assert Enum.map(stacked, &Enum.at(&1.stack.hi, j)) == cums
          # Bands are contiguous: each band starts where the one below ends.
          assert Enum.map(stacked, &Enum.at(&1.stack.lo, j)) == [0 | Enum.drop(cums, -1)]
        end
      end
    end

    test "nil counts as zero in the stack" do
      [_a, b] = annotate(:area, [[1, nil, 3], [2, 2, 2]], %{chart: %{stacked: true}})
      assert b.stack.lo == [1, 0, 3]
      assert b.stack.hi == [3, 2, 5]
    end

    test "the y range covers the stacked totals and the zero baseline" do
      stacked = annotate(:area, @rows, %{chart: %{stacked: true}})
      assert Stacking.data_range(stacked) == {0, 28 + 45 + 32}
    end

    test "area bands close along the layer below, so the SVG has one fill per band" do
      out = svg(:area, @rows, %{chart: %{stacked: true}, fill: %{type: :solid}})
      refute out =~ "NaN"
      refute out =~ "Infinity"
      assert length(Regex.scan(~r/<path[^>]*stroke="none"/, out)) == 3
    end

    test "every curve renders a closed band without NaN" do
      for curve <- [:smooth, :straight, :stepline, :monotone_cubic] do
        out = svg(:area, @rows, %{chart: %{stacked: true}, stroke: %{curve: curve}})
        refute out =~ "NaN"
        assert out =~ "Z"
      end
    end

    test "data labels and hover markers sit on the band tops, showing raw values" do
      out =
        html(:line, [[10, 20], [5, 5]], %{chart: %{stacked: true}, data_labels: %{enabled: true}})

      # Same y range unstacked: the second series' marker at category 0 must
      # land where an unstacked 15 does.
      plain = html(:line, [[15, 25], [0, 0]], %{})

      cy = fn html, color ->
        re =
          ~r/class="eexcharts-hover-marker" cx="[^"]*" cy="([^"]*)" data-j="0"[^>]*fill="#{color}"/

        [_, y] = Regex.run(re, html)
        y
      end

      assert cy.(out, "#00E396") == cy.(plain, "#008FFB")
      assert out =~ ~r/class="eexcharts-datalabel"[^>]*>5</
    end

    test "hidden series drop out of the stack" do
      series = Enum.with_index(@rows, fn r, i -> %{name: "s#{i}", data: r} end)

      {:safe, io} =
        EexCharts.render("t", :line, series,
          options: %{chart: %{stacked: true}},
          hidden_series: [0],
          hook: false
        )

      out = IO.iodata_to_binary(io)
      # With series 0 hidden, the visible stack peaks at 32 + 18 = 50 at most,
      # well under the 101 it would reach with all three.
      refute out =~ ">100<"
    end
  end

  describe "stack_type 100%" do
    test "normalises each category and tops out at exactly 100" do
      for type <- [:line, :area] do
        stacked =
          annotate(type, [[1, 2, 0.1], [2, 5, 0.2], [7, 0, 0.3]], %{
            chart: %{stacked: true, stack_type: "100%"}
          })

        assert List.last(stacked).stack.hi == [100.0, 100.0, 100.0]
        assert hd(stacked).stack.lo == [0.0, 0.0, 0.0]
        assert Enum.map(stacked, &Enum.at(&1.stack.hi, 0)) == [10.0, 30.0, 100.0]
      end
    end

    test "a category totalling zero stays at zero" do
      [_a, b] =
        annotate(:area, [[0, 1], [0, 1]], %{chart: %{stacked: true, stack_type: "100%"}})

      assert b.stack.hi == [0.0, 100.0]
    end

    test "the y-axis runs 0 to 100 with percent labels" do
      out = svg(:area, @rows, %{chart: %{stacked: true, stack_type: "100%"}})

      labels =
        Regex.scan(~r/class="eexcharts-yaxis-label"[^>]*>([^<]*)</, out, capture: :all_but_first)

      assert List.flatten(labels) == ~w(100% 80% 60% 40% 20% 0%) or
               List.flatten(labels) == ~w(0% 20% 40% 60% 80% 100%)
    end

    test "tooltips show the percentage and the raw value" do
      out = html(:area, [[1, 3], [3, 1]], %{chart: %{stacked: true, stack_type: "100%"}})
      assert out =~ "25.0% (1)"
      assert out =~ "75.0% (3)"
    end

    test "a user formatter on the y-axis is kept" do
      cfg =
        Config.build(:area, %{
          chart: %{stacked: true, stack_type: "100%"},
          yaxis: %{formatter: &"#{&1} pct"}
        })
        |> Stacking.prepare()

      assert cfg.yaxis.formatter.(5) == "5 pct"
      assert {cfg.yaxis.min, cfg.yaxis.max} == {0, 100}
    end
  end

  describe "streamgraph offsets" do
    @layers [[2, 4, 4], [2, 2, 0], [1, 5, 3]]

    test "silhouette is symmetric around zero" do
      layers =
        annotate(:streamgraph, @layers, %{plot_options: %{streamgraph: %{offset: :silhouette}}})

      bottom = hd(layers).stack.lo
      top = List.last(layers).stack.hi
      assert Enum.zip_with(bottom, top, &(&1 + &2)) == [0.0, 0.0, 0.0]
      assert top == [2.5, 5.5, 3.5]
    end

    test "wiggle baseline matches Byron & Wattenberg's formula worked by hand" do
      # f0 = [1, 2], f1 = [2, 2]. Step 1: f0' = 1, f1' = 0, total 4.
      # g0' = -((1/2 + 0) * 2 + (0/2 + 1) * 2) / 4 = -3/4, so g = [0, -0.75].
      # Midlines g + total/2 = [1.5, 1.25], mean 1.375, subtracted.
      assert Stacking.baseline(:wiggle, [[1, 2], [2, 2]]) == [-1.375, -2.125]

      # f0 = [2, 4, 4], f1 = [2, 2, 0].
      # Step 1: f' = [2, 0], total 6: -((1 + 0) * 4 + (0 + 2) * 2) / 6 = -4/3.
      # Step 2: f' = [0, -2], total 4: -((0 + 0) * 4 + (-1 + 0) * 0) / 4 = 0.
      # g = [0, -4/3, -4/3]; midlines [2, 5/3, 2/3], mean 13/9.
      [a, b, c] = Stacking.baseline(:wiggle, [[2, 4, 4], [2, 2, 0]])
      assert_in_delta a, -13 / 9, 1.0e-12
      assert_in_delta b, -25 / 9, 1.0e-12
      assert_in_delta c, -25 / 9, 1.0e-12
    end

    test "wiggle is the default offset and drives the bottom edge" do
      layers = annotate(:streamgraph, [[1, 2], [2, 2]])
      assert hd(layers).stack.lo == [-1.375, -2.125]
      assert List.last(layers).stack.hi == [-1.375 + 3, -2.125 + 4]
    end

    test "a zero-total category keeps the previous baseline" do
      # f = [1, 0, 1]: step 1 has total 0 (slope 0); step 2: f' = 1, total 1,
      # g0' = -(1/2 * 1) / 1 = -1/2. g = [0, 0, -1/2]; midlines [1/2, 0, 0],
      # mean 1/6.
      [a, b, c] = Stacking.baseline(:wiggle, [[1, 0, 1]])
      assert_in_delta a, -1 / 6, 1.0e-12
      assert_in_delta b, -1 / 6, 1.0e-12
      assert_in_delta c, -2 / 3, 1.0e-12
    end

    test "negative and nil values count as zero" do
      [a, b] =
        annotate(:streamgraph, [[-3, nil], [2, 2]], %{
          plot_options: %{streamgraph: %{offset: :silhouette}}
        })

      assert a.stack.hi == a.stack.lo
      assert b.stack.hi == [1.0, 1.0]
    end

    test "inside-out order puts early peaks in the middle, alternating sides" do
      rows = [[0, 0, 0, 1], [5, 0, 0, 0], [0, 0, 10, 0], [0, 7, 0, 0]]
      # By peak: row 1 (bottom), row 3 (top), row 2 (bottom), row 0 (top).
      assert Stacking.order(:inside_out, rows) == [2, 1, 3, 0]
      assert Stacking.order(:none, rows) == [0, 1, 2, 3]
    end

    test "colours and legend follow input order under inside-out" do
      rows = [[0, 0, 0, 1], [5, 0, 0, 0], [0, 0, 10, 0], [0, 7, 0, 0]]

      layers =
        annotate(:streamgraph, rows, %{plot_options: %{streamgraph: %{order: :inside_out}}})

      assert Enum.map(layers, & &1.index) == [0, 1, 2, 3]
      assert Enum.map(layers, & &1.stack.pos) == [3, 1, 0, 2]

      # Contiguous: sorted by position, each band starts where the last ended.
      sorted = Enum.sort_by(layers, & &1.stack.pos)

      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [below, above] -> assert above.stack.lo == below.stack.hi end)
    end

    test "the y-axis is hidden by default" do
      out = svg(:streamgraph, @layers, %{})
      refute out =~ ~s(class="eexcharts-yaxis-label")
      refute out =~ "NaN"
    end

    test "an unknown offset raises" do
      assert_raise ArgumentError, fn -> Stacking.baseline(:bogus, [[1]]) end
    end
  end
end
