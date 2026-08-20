defmodule EexCharts.DaisyThemeTest do
  @moduledoc """
  `theme.mode: :daisy` maps the chart onto daisyUI's theme variables.

  The library never resolves a daisyUI color — it emits the variable name and
  lets the browser do it — so these tests assert on the emitted strings.
  """
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Renderer, Theme}

  defp build(type, opts \\ %{}) do
    Config.build(type, Config.deep_merge(%{theme: %{mode: :daisy}}, opts))
  end

  defp render(params) do
    params
    |> Map.put(:options, Config.deep_merge(%{theme: %{mode: :daisy}}, params[:options] || %{}))
    |> Renderer.render()
    |> IO.iodata_to_binary()
  end

  describe "series palette" do
    test "walks daisyUI's semantic colors" do
      cfg = build(:line)

      assert cfg.colors == [
               "var(--color-primary, #008FFB)",
               "var(--color-secondary, #00E396)",
               "var(--color-accent, #FEB019)",
               "var(--color-info, #FF4560)",
               "var(--color-success, #775DD0)",
               "var(--color-warning, #008FFB)",
               "var(--color-error, #00E396)",
               "var(--color-neutral, #FEB019)"
             ]
    end

    test "falls back to the light palette for the first five series" do
      # Without daisyUI on the page the var() fallbacks take over, so a chart
      # with up to five series is pixel-identical to the default theme.
      light = Config.palette()

      for {daisy, i} <- Enum.with_index(Enum.take(Theme.daisy_palette(), 5)) do
        assert String.ends_with?(daisy, ", #{Enum.at(light, i)})")
      end
    end

    test "user-supplied colors win" do
      cfg = build(:line, %{colors: ["#123456"]})
      assert cfg.colors == ["#123456"]
    end

    test "an explicit theme palette keeps daisy chrome but restores hex series" do
      cfg = build(:line, %{theme: %{palette: :palette6}})

      assert cfg.colors == Theme.palette(:palette6)
      assert cfg.chart.fore_color == "var(--color-base-content, #373d3f)"
    end
  end

  describe "chrome" do
    test "text follows base-content and borders follow base-300" do
      cfg = build(:line)

      assert cfg.chart.fore_color == "var(--color-base-content, #373d3f)"
      assert cfg.grid.border_color == "var(--color-base-300, #e0e0e0)"
      assert cfg.xaxis.axis_border.color == "var(--color-base-300, #e0e0e0)"
      assert cfg.xaxis.axis_ticks.color == "var(--color-base-300, #e0e0e0)"
    end

    test "marker rings are cut out of the chart surface" do
      assert build(:line).markers.stroke_colors == "var(--color-base-100, #fff)"
    end

    test "the radial-bar track follows base-200" do
      cfg = build(:radial_bar)
      assert cfg.plot_options.radial_bar.track.background == "var(--color-base-200, #f2f2f2)"
    end

    test "radar and polar-area rings and spokes follow base-300" do
      radar = build(:radar).plot_options.radar.polygons
      polar = build(:polar_area).plot_options.polar_area

      assert radar.stroke_colors == "var(--color-base-300, #e8e8e8)"
      assert radar.connector_colors == "var(--color-base-300, #e8e8e8)"
      assert polar.rings.stroke_color == "var(--color-base-300, #e8e8e8)"
      assert polar.spokes.connector_colors == "var(--color-base-300, #e8e8e8)"
    end

    test "keeps values the user set explicitly" do
      cfg = build(:line, %{chart: %{fore_color: "#abcdef"}, grid: %{border_color: "#fedcba"}})

      assert cfg.chart.fore_color == "#abcdef"
      assert cfg.grid.border_color == "#fedcba"
    end

    test "every emitted value carries a fallback for pages without daisyUI" do
      cfg = build(:pie)

      strings =
        [
          cfg.colors,
          cfg.stroke.colors,
          cfg.data_labels.style.colors,
          [cfg.chart.fore_color, cfg.grid.border_color, cfg.markers.stroke_colors]
        ]
        |> List.flatten()

      for value <- strings do
        assert value =~ ~r/var\(--[a-z0-9-]+, [^)]+\)/,
               "#{value} has no var() fallback"
      end
    end
  end

  describe "mark separators" do
    test "the white slice separator follows the chart surface" do
      for type <- [:pie, :donut, :polar_area, :heatmap, :treemap] do
        assert build(type).stroke.colors == ["var(--color-base-100, #fff)"],
               "#{type} separator not themed"
      end
    end

    test "a mark's own dark outline is left alone" do
      # These are the mark's border, not a cut-out of the page, so daisyUI's
      # surface color would erase them.
      assert build(:candlestick).stroke.colors == ["#333"]
      assert build(:box_plot).stroke.colors == ["#24292e"]
    end
  end

  describe "data labels" do
    test "labels drawn on a mark use daisyUI's paired content colors" do
      for type <- [:bar, :pie, :treemap] do
        assert build(type).data_labels.style.colors == Theme.daisy_label_palette(),
               "#{type} label colors not themed"
      end
    end

    test "labels floating over the chart background keep the default resolution" do
      # nil means "fall back to the series color" in the renderer; a content
      # color would be invisible against the page.
      assert build(:line).data_labels.style.colors == nil
    end

    test "are left as-is when the user supplies their own palette" do
      # Content colors are only correct for the daisyUI palette they pair with.
      cfg = build(:bar, %{colors: ["#123456"]})
      assert cfg.data_labels.style.colors == ["#fff"]
    end
  end

  describe "tooltip" do
    test "uses the daisy theme, overriding a chart type's dark default" do
      assert build(:line).tooltip.theme == :daisy
      assert build(:pie).tooltip.theme == :daisy
    end

    test "keeps an explicitly requested theme" do
      assert build(:line, %{tooltip: %{theme: :dark}}).tooltip.theme == :dark
    end

    test "is selected by class, leaving data-theme to daisyUI" do
      html = render(%{id: "t", type: :line, series: [%{name: "A", data: [1, 2]}]})

      assert html =~ ~s(class="eexcharts-tooltip eexcharts-tooltip-daisy")
      refute html =~ ~s(data-theme=)
    end
  end

  describe "rendered output" do
    test "series marks reference the daisyUI variables" do
      html =
        render(%{
          id: "t",
          type: :bar,
          series: [%{name: "A", data: [10, 20]}, %{name: "B", data: [5, 15]}],
          categories: ~w(a b)
        })

      assert html =~ "fill=\"var(--color-primary, #008FFB)\""
      assert html =~ "fill=\"var(--color-secondary, #00E396)\""
    end

    test "tooltip markers reference the daisyUI variables" do
      html = render(%{id: "t", type: :line, series: [%{name: "A", data: [1, 2]}]})
      assert html =~ "background:var(--color-primary, #008FFB)"
    end

    test "area gradients shade the variable with color-mix" do
      html = render(%{id: "t", type: :area, series: [%{name: "A", data: [1, 2]}]})

      assert html =~ "stop-color=\"var(--color-primary, #008FFB)\""

      assert html =~
               "stop-color=\"color-mix(in oklab, #fff 50%, var(--color-primary, #008FFB))\""
    end

    test "heatmap cell shades stay resolvable by the browser" do
      html =
        render(%{
          id: "t",
          type: :heatmap,
          series: [%{name: "A", data: [10, 50, 90]}],
          categories: ~w(a b c)
        })

      assert html =~ "color-mix(in oklab,"
      refute html =~ ~s(fill="#373d3f")
    end
  end

  describe "light and dark modes" do
    test "are untouched" do
      light = Config.build(:line)
      dark = Config.build(:line, %{theme: %{mode: :dark}})

      assert light.colors == nil
      assert light.chart.fore_color == "#373d3f"
      assert dark.colors == Theme.palette(:palette4)
      assert dark.tooltip.theme == :dark
    end
  end
end
