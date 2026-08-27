defmodule EexCharts.SnapshotDiffTest do
  @moduledoc """
  The snapshot gate is only as good as its comparison: it has to wave through
  cross-platform float noise while still failing on anything a reader would
  call a change.
  """
  use ExUnit.Case, async: true

  alias EexCharts.SnapshotDiff

  @svg ~s(<polygon fill="none" points="0,-105.1652 91.07573479407125,52.58260000000001" stroke="#e8e8e8"/>)

  test "identical snapshots match" do
    assert SnapshotDiff.compare(@svg, @svg) == :ok
  end

  test "last-bit float disagreement between platforms matches" do
    # The real macOS/Linux radar difference: same double, different shortest
    # representation, ~5e-16 apart in relative terms.
    macos = String.replace(@svg, "52.58260000000001", "52.582599999999985")

    assert SnapshotDiff.compare(macos, @svg) == :ok
  end

  test "a difference big enough to move a pixel fails" do
    moved = String.replace(@svg, "52.58260000000001", "52.5826001")

    assert {:error, message} = SnapshotDiff.compare(moved, @svg)
    assert message =~ ">>>52.5826001<<<"
    assert message =~ ">>>52.58260000000001<<<"
  end

  test "markup differences fail even when every number is equal" do
    recolored = String.replace(@svg, ~s(stroke="#e8e8e8"), ~s(stroke="#f8e8e8"))

    assert {:error, message} = SnapshotDiff.compare(recolored, @svg)
    assert message =~ "first difference at token"
  end

  test "an attribute appearing only on one side fails" do
    extra = String.replace(@svg, "<polygon ", ~s(<polygon stroke-width="1" ))

    assert {:error, _message} = SnapshotDiff.compare(extra, @svg)
    assert {:error, _message} = SnapshotDiff.compare(@svg, extra)
  end

  test "integers and floats of the same value are not conflated with markup" do
    assert SnapshotDiff.compare(~s(x="1"), ~s(x="1")) == :ok
    assert {:error, _} = SnapshotDiff.compare(~s(x="1"), ~s(y="1"))
  end
end
