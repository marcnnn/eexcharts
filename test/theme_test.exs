defmodule EexCharts.ThemeTest do
  use ExUnit.Case, async: true

  alias EexCharts.Config

  describe "dark mode" do
    test "applies palette4, light fore color and dark tooltip" do
      cfg = Config.build(:line, %{theme: %{mode: :dark}})

      assert cfg.colors == ["#4ecdc4", "#c7f464", "#81D4FA", "#fd6a6a", "#546E7A"]
      assert cfg.chart.fore_color == "#f6f7f8"
      assert cfg.tooltip.theme == :dark
    end

    test "does not override user-supplied colors" do
      cfg = Config.build(:line, %{theme: %{mode: :dark}, colors: ["#123456"]})
      assert cfg.colors == ["#123456"]
    end

    test "keeps a user's explicit light tooltip theme" do
      cfg = Config.build(:line, %{theme: %{mode: :dark}, tooltip: %{theme: :light}})
      assert cfg.tooltip.theme == :light
    end

    test "does not touch grid border or background (matches ApexCharts)" do
      cfg = Config.build(:line, %{theme: %{mode: :dark}})
      assert cfg.grid.border_color == "#e0e0e0"
      assert cfg.chart.background == ""
    end

    test "honors an explicit theme palette" do
      cfg = Config.build(:line, %{theme: %{mode: :dark, palette: :palette6}})
      assert cfg.colors == EexCharts.Theme.palette(:palette6)
    end
  end

  describe "light mode (default)" do
    test "leaves per-type defaults intact" do
      cfg = Config.build(:pie)
      # Pie's own dark tooltip default should survive.
      assert cfg.tooltip.theme == :dark
      assert cfg.chart.fore_color == "#373d3f"
    end
  end
end
