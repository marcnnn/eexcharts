defmodule EexCharts.ScaleTest do
  use ExUnit.Case, async: true

  alias EexCharts.Scale

  test "produces nice ticks covering the range" do
    s = Scale.nice_scale(0, 100)

    assert s.nice_min <= 0
    assert s.nice_max >= 100
    assert List.first(s.ticks) == s.nice_min
    assert List.last(s.ticks) == s.nice_max
    assert length(s.ticks) >= 3

    # Evenly spaced
    diffs =
      s.ticks |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)

    assert Enum.uniq_by(diffs, &Float.round(&1 * 1.0, 6)) |> length() == 1
  end

  test "step size snaps to 1/2/5/10 mantissa" do
    for {min, max} <- [{0, 97}, {3, 41}, {0, 7}, {12, 12_345}] do
      s = Scale.nice_scale(min, max)
      mag = :math.pow(10, :math.floor(:math.log10(s.step)))
      msd = s.step / mag

      assert Float.round(msd * 1.0, 6) in [1.0, 2.0, 2.5, 5.0, 10.0],
             "step #{s.step} for #{min}..#{max}"
    end
  end

  test "snaps min to zero when within 15% of the range" do
    s = Scale.nice_scale(5, 100)
    assert s.nice_min == 0
  end

  test "does not snap min to zero when far from it" do
    s = Scale.nice_scale(80, 100)
    assert s.nice_min > 0
  end

  test "handles min == max" do
    s = Scale.nice_scale(5, 5)
    assert s.nice_min < 5
    assert s.nice_max > 5
  end

  test "handles all-zero data" do
    s = Scale.nice_scale(0, 0)
    assert s.nice_min == 0
    assert s.nice_max >= 2
  end

  test "handles missing data" do
    s = Scale.nice_scale(nil, nil)
    assert is_number(s.nice_min)
    assert s.nice_max > s.nice_min
  end

  test "negative ranges" do
    s = Scale.nice_scale(-80, -20)
    assert s.nice_min <= -80
    # max within 15% of zero from above snaps to 0
    assert s.nice_max >= -20
  end

  test "mixed negative and positive includes zero" do
    s = Scale.nice_scale(-30, 70)
    assert s.nice_min <= -30
    assert s.nice_max >= 70
    assert Enum.any?(s.ticks, &(&1 == 0))
  end

  test "honors forced min/max and tick_amount" do
    s = Scale.nice_scale(3, 97, min: 0, max: 100, tick_amount: 4)
    assert s.nice_min == 0
    assert s.nice_max == 100
    assert length(s.ticks) == 5
    assert s.ticks == [0, 25, 50, 75, 100]
  end

  test "strip_number removes float drift" do
    assert Scale.strip_number(0.30000000000000004) == 0.3
    assert Scale.strip_number(10.0) == 10
    assert Scale.strip_number(7) == 7
  end

  test "large ranges" do
    s = Scale.nice_scale(0, 1_234_567)
    assert s.nice_max >= 1_234_567
    assert length(s.ticks) <= 30
  end

  test "tiny float ranges" do
    s = Scale.nice_scale(0.001, 0.009)
    assert s.nice_min <= 0.001
    assert s.nice_max >= 0.009
  end

  describe "log_scale/4" do
    test "plain log scale spans powers of the base" do
      s = Scale.log_scale(1, 10_000, 10, false)
      assert s.log
      assert s.log_base == 10
      assert s.ticks == [1, 10, 100, 1000, 10_000]
      assert s.nice_min == 1
      assert s.nice_max == 10_000
    end

    test "nice log scale brackets the range with exact powers" do
      s = Scale.log_scale(3, 8000, 10, true)
      assert s.ticks == [1, 10, 100, 1000, 10_000]
    end

    test "supports a custom base" do
      s = Scale.log_scale(1, 64, 2, false)
      assert List.first(s.ticks) == 1
      assert List.last(s.ticks) == 64
      # 2^0..2^6 -> 7 ticks
      assert length(s.ticks) == 7
    end

    test "falls back to a linear nice scale for small ranges (<= 5)" do
      s = Scale.log_scale(1, 4, 10, false)
      refute s.log
    end
  end

  describe "linear_scale/4" do
    test "produces evenly spaced ticks over the range" do
      {result, nmin, nmax} = Scale.linear_scale(0, 10, 5)
      assert result == [0, 2, 4, 6, 8, 10]
      assert nmin == 0
      assert nmax == 10
    end

    test "collapses to a single value when min == max" do
      assert {[7], 7, 7} = Scale.linear_scale(7, 7, 5)
    end

    test "honors a forced step" do
      {result, _, _} = Scale.linear_scale(0, 10, 5, 5)
      assert result == [0, 5, 10]
    end
  end
end
