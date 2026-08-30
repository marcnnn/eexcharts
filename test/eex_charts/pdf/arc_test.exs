defmodule EexCharts.PDF.ArcTest do
  @moduledoc """
  Arcs are most of a chart's geometry — every pie slice, donut ring, radial
  bar and rounded bar corner — and PDF cannot draw one, so the conversion to
  cubic Béziers has to be exact rather than close.
  """
  use ExUnit.Case, async: true

  alias EexCharts.PDF.Arc

  # 4/3 · tan(π/8): the control-point distance that makes a cubic touch a unit
  # quarter circle at both ends with matching tangents.
  @k 0.5522847498307933

  defp assert_point({x, y}, {ex, ey}) do
    assert_in_delta x, ex, 1.0e-12
    assert_in_delta y, ey, 1.0e-12
  end

  describe "quarter circles" do
    test "a unit quarter arc reproduces the classic control points" do
      # (1, 0) → (0, 1) the short way round, sweeping through (√½, √½).
      assert [{c1, c2, p}] = Arc.to_curves({1, 0}, 1, 1, 0, 0, 1, {0, 1})

      assert_point(c1, {1.0, @k})
      assert_point(c2, {@k, 1.0})
      assert_point(p, {0.0, 1.0})
    end

    test "the large-arc flag takes the long way round, in three segments" do
      # Same endpoints, same circle, but 270° instead of 90° — and 270° cannot
      # be done in fewer than three ≤90° pieces.
      assert [{_, _, a}, {_, _, b}, {_, _, c}] = Arc.to_curves({1, 0}, 1, 1, 0, 1, 0, {0, 1})

      assert_point(a, {0.0, -1.0})
      assert_point(b, {-1.0, 0.0})
      assert_point(c, {0.0, 1.0})
    end

    test "radii scale the control points with the arc" do
      assert [{c1, c2, p}] = Arc.to_curves({10, 0}, 10, 10, 0, 0, 1, {0, 10})

      assert_point(c1, {10.0, 10 * @k})
      assert_point(c2, {10 * @k, 10.0})
      assert_point(p, {0.0, 10.0})
    end
  end

  describe "half and full circles" do
    test "a half circle splits into two segments meeting at the top" do
      assert [{_, _, mid}, {_, _, last}] = Arc.to_curves({1, 0}, 1, 1, 0, 0, 1, {-1, 0})

      assert_point(mid, {0.0, 1.0})
      assert_point(last, {-1.0, 0.0})
    end

    test "two half circles close a full circle back on the start point" do
      [{_, _, mid} | _] = first = Arc.to_curves({1, 0}, 1, 1, 0, 0, 1, {-1, 0})
      second = Arc.to_curves({-1, 0}, 1, 1, 0, 0, 1, {1, 0})

      assert length(first) == 2
      assert length(second) == 2
      assert_point(mid, {0.0, 1.0})

      {_, _, back} = List.last(second)
      assert_point(back, {1.0, 0.0})
    end

    test "every segment ends on the circle" do
      curves = Arc.to_curves({0, -5}, 5, 5, 0, 1, 1, {0, 5})

      for {_, _, {x, y}} <- curves do
        assert_in_delta :math.sqrt(x * x + y * y), 5.0, 1.0e-12
      end
    end
  end

  describe "ellipses and rotation" do
    test "unequal radii stretch the arc, not the angles" do
      assert [{c1, c2, p}] = Arc.to_curves({8, 0}, 8, 3, 0, 0, 1, {0, 3})

      assert_point(c1, {8.0, 3 * @k})
      assert_point(c2, {8 * @k, 3.0})
      assert_point(p, {0.0, 3.0})
    end

    test "a rotated ellipse rotates its control points too" do
      # The same arc as above, turned a quarter turn: x and y swap, with a sign.
      assert [{c1, c2, p}] = Arc.to_curves({0, 8}, 8, 3, 90, 0, 1, {-3, 0})

      assert_point(c1, {-3 * @k, 8.0})
      assert_point(c2, {-3.0, 8 * @k})
      assert_point(p, {-3.0, 0.0})
    end
  end

  describe "degenerate arcs" do
    test "a zero radius becomes a straight run, as the specification says" do
      assert [{c1, c2, p}] = Arc.to_curves({0, 0}, 0, 5, 0, 0, 1, {9, 0})

      assert_point(c1, {3.0, 0.0})
      assert_point(c2, {6.0, 0.0})
      assert_point(p, {9.0, 0.0})
    end

    test "an arc that ends where it starts draws nothing but a point" do
      assert [{_, _, p}] = Arc.to_curves({4, 4}, 2, 2, 0, 1, 1, {4, 4})
      assert_point(p, {4.0, 4.0})
    end

    test "radii too small to span the endpoints are scaled up to fit" do
      # rx = ry = 1 cannot reach from (-5, 0) to (5, 0); both grow to 5.
      assert [{_, _, mid}, {_, _, last}] = Arc.to_curves({-5, 0}, 1, 1, 0, 0, 1, {5, 0})

      assert_point(mid, {0.0, -5.0})
      assert_point(last, {5.0, 0.0})
    end
  end
end
