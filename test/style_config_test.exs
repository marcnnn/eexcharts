defmodule EexCharts.StyleConfigTest do
  @moduledoc """
  `config :eexcharts, style: :chartjs` sets the style for every chart.

  Application env is global, so this module is the one place that touches it
  and runs synchronously.
  """
  use ExUnit.Case, async: false

  alias EexCharts.Config

  setup do
    on_exit(fn -> Application.delete_env(:eexcharts, :style) end)
  end

  test "defaults to ApexCharts" do
    assert EexCharts.Style.default() == :apexcharts
    assert Config.build(:line).stroke.width == 5
  end

  test "applies to every chart once configured" do
    Application.put_env(:eexcharts, :style, :chartjs)

    assert Config.build(:line).stroke.width == 3
    assert Config.build(:bar).fill.opacity == 0.5
  end

  test "per-chart options still win" do
    Application.put_env(:eexcharts, :style, :chartjs)
    assert Config.build(:line, %{style: :apexcharts}).stroke.width == 5
  end
end
