defmodule EexCharts.StatsTest do
  use ExUnit.Case, async: true

  alias EexCharts.Stats

  # Expected values below were computed with NumPy 1.26
  # (`np.histogram_bin_edges`, `np.histogram`, `np.percentile`) and a direct
  # NumPy evaluation of the Gaussian KDE sum; see the test names for the call.
  @data [12.5, 3.1, 7.7, 15.2, 9.9, 4.4, 11.0, 8.3, 6.6, 21.7, 10.1, 5.5, 13.8] ++
          [7.2, 9.4, 2.9, 14.6, 8.8, 30.2, 10.7, 6.1, 12.0, 9.0, 7.9, 11.6]

  defp close?(a, b, tol \\ 1.0e-9), do: abs(a - b) <= tol * max(1.0, abs(b))

  defp assert_all_close(actual, expected, tol \\ 1.0e-9) do
    assert length(actual) == length(expected), "#{inspect(actual)} vs #{inspect(expected)}"

    for {a, e} <- Enum.zip(actual, expected) do
      assert close?(a, e, tol), "#{inspect(actual)} vs #{inspect(expected)}"
    end
  end

  describe "quantile/2 (np.percentile, linear)" do
    test "matches NumPy at several probabilities" do
      expected = [2.9, 4.840000000000001, 7.2, 9.4, 12.0, 14.96, 30.2]

      actual = Enum.map([0, 0.1, 0.25, 0.5, 0.75, 0.9, 1], &Stats.quantile(@data, &1))
      assert_all_close(actual, expected)
    end

    test "interpolates between order statistics" do
      assert_all_close(Enum.map([0.25, 0.5, 0.75], &Stats.quantile([4, 1, 3, 2], &1)), [
        1.75,
        2.5,
        3.25
      ])
    end

    test "nil for no numbers" do
      assert Stats.quantile([], 0.5) == nil
      assert Stats.quantile([nil, "x"], 0.5) == nil
    end
  end

  describe "summary/2" do
    test "Tukey whiskers end at the extreme observations inside the fences" do
      s = Stats.summary(@data)
      assert close?(s.q1, 7.2) and close?(s.median, 9.4) and close?(s.q3, 12.0)
      # fences: 7.2 - 1.5 * 4.8 = 0.0 and 12.0 + 7.2 = 19.2
      assert s.lower == 2.9
      assert s.upper == 15.2
      assert s.outliers == [21.7, 30.2]
      assert s.n == 25
      assert s.min == 2.9 and s.max == 30.2
    end

    test "whisker multiple and whisker: nil" do
      assert Stats.summary(@data, whisker: 3).outliers == [30.2]
      s = Stats.summary(@data, whisker: nil)
      assert {s.lower, s.upper, s.outliers} == {2.9, 30.2, []}
    end

    test "single value" do
      s = Stats.summary([4])
      assert {s.min, s.q1, s.median, s.q3, s.max, s.outliers} == {4, 4, 4, 4, 4, []}
    end
  end

  describe "bin_edges/2 and histogram/2 (np.histogram_bin_edges, np.histogram)" do
    @oracle %{
      fd:
        {[
           2.9,
           5.933333333333334,
           8.966666666666667,
           12.0,
           15.033333333333333,
           18.066666666666666,
           21.099999999999998,
           24.133333333333333,
           27.166666666666664,
           30.2
         ], [4, 7, 7, 4, 1, 0, 1, 0, 1]},
      sturges:
        {[2.9, 7.449999999999999, 12.0, 16.549999999999997, 21.099999999999998, 25.65, 30.2],
         [7, 11, 5, 0, 1, 1]},
      scott: {[2.9, 9.725, 16.55, 23.375, 30.2], [13, 10, 1, 1]},
      sqrt: {[2.9, 8.36, 13.82, 19.279999999999998, 24.74, 30.2], [10, 11, 2, 1, 1]}
    }

    for method <- [:fd, :sturges, :scott, :sqrt] do
      @method method
      test "bins: #{method} matches NumPy" do
        {edges, counts} = @oracle[@method]
        actual = Stats.bin_edges(@data, bins: @method)
        assert_all_close(actual, edges)
        assert Stats.histogram(@data, actual) == counts
      end
    end

    test "auto is Freedman-Diaconis when the IQR is positive" do
      assert Stats.bin_edges(@data) == Stats.bin_edges(@data, bins: :fd)
    end

    test "auto falls back to Sturges when the IQR is 0" do
      ties = [5, 5, 5, 5, 5, 5, 5, 5, 1, 9]
      # NumPy: fd gives one bin [1, 9]; sturges gives five.
      assert Stats.bin_edges(ties, bins: :fd) == [1, 9]
      assert_all_close(Stats.bin_edges(ties), [1.0, 2.6, 4.2, 5.800000000000001, 7.4, 9.0])
    end

    test "integer bins = linspace(min, max, k + 1)" do
      edges = Stats.bin_edges(@data, bins: 6)
      assert_all_close(edges, elem(@oracle.sturges, 0))
    end

    test "bin_width aligns edges to multiples of the width" do
      assert Stats.bin_edges([3, 7.5, 12, 19.9], bin_width: 5) == [0.0, 5.0, 10.0, 15.0, 20.0]
      edges = Stats.bin_edges([0.12, 0.31, 0.29], bin_width: 0.1)
      assert edges == [0.1, 0.2, 0.3, 0.4]
      assert Stats.histogram([0.12, 0.31, 0.29], edges) == [1, 1, 1]
    end

    test "a maximum on the last edge falls in the last (closed) bin" do
      assert Stats.histogram([0, 5, 10], [0, 5, 10]) == [1, 2]
      assert Stats.histogram([0, 10, 20], Stats.bin_edges([0, 10, 20], bin_width: 10)) == [1, 2]
    end

    test "constant data widens to value ± 0.5" do
      assert Stats.bin_edges([4, 4, 4], bins: 2) == [3.5, 4.0, 4.5]
      assert Stats.histogram([4, 4, 4], [3.5, 4.0, 4.5]) == [0, 3]
    end

    test "counts always sum to n" do
      for opts <- [[], [bins: :sturges], [bins: :scott], [bins: 13], [bin_width: 0.7]] do
        edges = Stats.bin_edges(@data, opts)
        assert Enum.sum(Stats.histogram(@data, edges)) == length(@data)
      end
    end

    test "no values, no bins" do
      assert Stats.bin_edges([]) == []
      assert Stats.histogram([], []) == []
    end
  end

  describe "normalize/4" do
    setup do
      edges = Stats.bin_edges(@data, bins: 6)
      %{edges: edges, counts: Stats.histogram(@data, edges)}
    end

    test "density matches np.histogram(density=True) and integrates to 1", c do
      density = Stats.normalize(c.counts, c.edges, :density)

      assert_all_close(density, [
        0.06153846153846155,
        0.09670329670329668,
        0.04395604395604399,
        0.0,
        0.00879120879120879,
        0.00879120879120879
      ])

      widths = c.edges |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)
      area = Enum.zip_with(density, widths, &(&1 * &2)) |> Enum.sum()
      assert close?(area, 1.0)
    end

    test "probability and percent sum to 1 and 100", c do
      assert close?(Enum.sum(Stats.normalize(c.counts, c.edges, :probability)), 1.0)
      assert close?(Enum.sum(Stats.normalize(c.counts, c.edges, :percent)), 100.0)
      assert Stats.normalize(c.counts, c.edges, :count) == c.counts
    end

    test "cumulative ends at the total", c do
      assert List.last(Stats.normalize(c.counts, c.edges, :count, true)) == 25
      assert close?(List.last(Stats.normalize(c.counts, c.edges, :percent, true)), 100.0)
      assert close?(List.last(Stats.normalize(c.counts, c.edges, :density, true)), 1.0)
      cum = Stats.normalize(c.counts, c.edges, :count, true)
      assert cum == Enum.sort(cum)
    end
  end

  describe "kernel density" do
    test "Silverman's rule of thumb" do
      # 0.9 * min(sd, IQR / 1.34) * n^(-1/5), sd with ddof = 1
      assert close?(Stats.bandwidth(@data), 1.6935224052275035)
      assert close?(Stats.bandwidth(@data, :scott), 3.2495147137817697)
      assert Stats.bandwidth(@data, 2) == 2.0
    end

    test "Gaussian KDE matches a direct NumPy evaluation" do
      h = Stats.bandwidth(@data)

      assert_all_close(
        Stats.kde(@data, [0.0, 5.0, 9.4, 17.5, 30.0], h),
        [
          0.004330605867832878,
          0.053167650147065246,
          0.09566295960193726,
          0.007423864723876151,
          0.009357357819512647
        ],
        1.0e-12
      )
    end

    test "the density curve integrates to ~1" do
      %{points: pts} = Stats.density_curve(@data, cut: 4, points: 400)

      area =
        pts
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [{x0, d0}, {x1, d1}] -> (x1 - x0) * (d0 + d1) / 2 end)
        |> Enum.sum()

      assert abs(area - 1.0) < 1.0e-3
    end

    test "the curve spans the data plus `cut` bandwidths" do
      %{bandwidth: h, points: pts} = Stats.density_curve(@data, cut: 2, points: 10)
      assert length(pts) == 10
      assert close?(elem(hd(pts), 0), 2.9 - 2 * h)
      assert close?(elem(List.last(pts), 0), 30.2 + 2 * h)
    end

    test "degenerate samples still get a positive bandwidth" do
      assert Stats.bandwidth([3, 3, 3]) > 0
      assert Stats.bandwidth([0]) == 1.0
      assert Stats.density_curve([]) == nil
    end
  end

  test "jitter is deterministic and in [0, 1)" do
    js = Enum.map(0..999, &Stats.jitter/1)
    assert js == Enum.map(0..999, &Stats.jitter/1)
    assert Enum.all?(js, &(&1 >= 0 and &1 < 1))
    # Spread out, not clumped: every tenth of the interval gets points.
    assert js |> Enum.map(&trunc(&1 * 10)) |> Enum.uniq() |> length() == 10
  end
end
