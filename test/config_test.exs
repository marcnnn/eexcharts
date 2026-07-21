defmodule EexCharts.ConfigTest do
  use ExUnit.Case, async: true

  alias EexCharts.Config

  test "line defaults follow ApexCharts (dataLabels off, stroke 5 straight)" do
    cfg = Config.build(:line)

    assert cfg.chart.type == :line
    assert cfg.data_labels.enabled == false
    assert cfg.stroke.width == 5
    assert cfg.stroke.curve == :straight
    assert cfg.markers.size == 0
  end

  test "area defaults use a vertical gradient fill" do
    cfg = Config.build(:area)

    assert cfg.fill.type == :gradient
    assert cfg.fill.gradient.opacity_from == 0.65
    assert cfg.fill.gradient.opacity_to == 0.5
    assert cfg.stroke.width == 4
    assert cfg.stroke.curve == :smooth
  end

  test "bar defaults: square legend markers, center labels, no stroke" do
    cfg = Config.build(:bar)

    assert cfg.stroke.width == 0
    assert cfg.legend.markers.shape == :square
    assert cfg.plot_options.bar.data_labels.position == :center
    assert cfg.plot_options.bar.column_width == "70%"
    assert cfg.data_labels.enabled == true
  end

  test "pie defaults: right legend, percent labels, dark tooltip" do
    cfg = Config.build(:pie)

    assert cfg.legend.position == :right
    assert cfg.data_labels.formatter == :percent
    assert cfg.tooltip.theme == :dark
    assert cfg.plot_options.pie.donut.size == "65%"
  end

  test "user options deep-merge over defaults" do
    cfg = Config.build(:line, %{stroke: %{width: 2}, grid: %{padding: %{left: 20}}})

    assert cfg.stroke.width == 2
    # untouched siblings survive
    assert cfg.stroke.curve == :straight
    assert cfg.grid.padding.left == 20
    assert cfg.grid.padding.right == 10
  end

  test "default palette matches ApexCharts palette1 and cycles" do
    cfg = Config.build(:line)

    assert Config.color_at(cfg, 0) == "#008FFB"
    assert Config.color_at(cfg, 4) == "#775DD0"
    assert Config.color_at(cfg, 5) == "#008FFB"
  end

  test "custom colors override the palette" do
    cfg = Config.build(:line, %{colors: ["#111111", "#222222"]})

    assert Config.color_at(cfg, 0) == "#111111"
    assert Config.color_at(cfg, 2) == "#111111"
  end
end
