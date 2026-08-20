defmodule EexCharts.ThemeModeConfigTest do
  @moduledoc """
  `config :eexcharts, theme_mode: :daisy` is what a daisyUI Phoenix app sets
  once instead of passing `theme: %{mode: :daisy}` to every chart.

  Application env is global, so this module is the one place that touches it
  and runs synchronously.
  """
  use ExUnit.Case, async: false

  alias EexCharts.Config

  setup do
    on_exit(fn -> Application.delete_env(:eexcharts, :theme_mode) end)
  end

  test "defaults to light" do
    assert Config.theme_mode() == :light
    assert Config.build(:line).chart.fore_color == "#373d3f"
  end

  test "applies to every chart once configured" do
    Application.put_env(:eexcharts, :theme_mode, :daisy)

    assert Config.build(:line).chart.fore_color == "var(--color-base-content, #373d3f)"
    assert Config.build(:pie).tooltip.theme == :daisy
  end

  test "per-chart options still win" do
    Application.put_env(:eexcharts, :theme_mode, :daisy)

    cfg = Config.build(:line, %{theme: %{mode: :light}})
    assert cfg.chart.fore_color == "#373d3f"
  end
end
