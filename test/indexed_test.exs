defmodule EexCharts.IndexedTest do
  use ExUnit.Case, async: true

  alias EexCharts.Indexed

  test "reads by position and falls back outside the range" do
    t = Indexed.new([:a, nil, :c])
    assert Indexed.at(t, 0) == :a
    assert Indexed.at(t, 1, :default) == nil
    assert Indexed.at(t, 2) == :c
    assert Indexed.at(t, 3) == nil
    assert Indexed.at(t, 3, :default) == :default
    assert Indexed.at(t, -1, :default) == :default
  end

  test "treats nil and other non-lists as empty" do
    assert Indexed.at(Indexed.new(nil), 0, :default) == :default
  end
end
