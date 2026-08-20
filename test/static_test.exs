defmodule EexCharts.StaticTest do
  @moduledoc """
  `EexCharts.to_svg/4` renders for rasterizers (resvg, Typst, librsvg), not
  browsers: a bare `<svg>` with no hover furniture, no LiveView wiring, and —
  because rasterizers render `var(…)` as black, ignoring even the fallback —
  no CSS custom properties or `color-mix()`.
  """
  use ExUnit.Case, async: true

  @series [%{name: "Desktops", data: [10, 41, 35]}, %{name: "Mobile", data: [23, 12, 54]}]
  @categories ~w(Jan Feb Mar)

  defp svg(type, opts \\ []) do
    EexCharts.to_svg("t", type, @series, Keyword.put_new(opts, :categories, @categories))
  end

  describe "bare <svg> output" do
    test "returns a string containing only the svg element" do
      out = svg(:line)

      assert is_binary(out)
      assert String.starts_with?(out, "<svg ")
      assert String.ends_with?(out, "</svg>")
      refute out =~ "<div"
    end

    test "the chart itself is complete" do
      out = svg(:line)

      assert out =~ "eexcharts-series"
      assert out =~ "eexcharts-grid"
      assert out =~ "Jan"
      assert out =~ "Desktops"
    end
  end

  describe "hover furniture is omitted" do
    test "line/area charts carry no crosshair, hover markers, or zones" do
      for type <- [:line, :area] do
        out = svg(type)

        refute out =~ "eexcharts-crosshair"
        refute out =~ "eexcharts-hover-marker"
        refute out =~ "eexcharts-zone"
        refute out =~ "eexcharts-tip"
      end
    end

    test "bar charts carry no zones or tooltip indexes" do
      out = svg(:bar)

      refute out =~ "eexcharts-zone"
      refute out =~ "data-j="
    end

    test "data-j / data-cx / data-cy are stripped across chart types" do
      scatter = [%{name: "A", data: [[1, 2], [3, 4]]}]
      heat = [%{name: "r1", data: [1, 2]}, %{name: "r2", data: [3, 4]}]

      for out <- [
            svg(:pie),
            svg(:radar),
            svg(:candlestick, categories: nil),
            EexCharts.to_svg("t", :scatter, scatter),
            EexCharts.to_svg("t", :heatmap, heat),
            EexCharts.to_svg("t", :treemap, heat)
          ] do
        refute out =~ "data-j="
        refute out =~ "data-cx="
        refute out =~ "data-cy="
      end
    end
  end

  describe "no LiveView wiring" do
    test "output carries no phx-* attributes or hook" do
      for type <- [:line, :bar, :pie, :radar, :heatmap] do
        refute svg(type) =~ "phx-"
      end
    end
  end

  describe "CSS custom properties are resolved" do
    @daisy [options: %{theme: %{mode: :daisy}}]

    test "daisy var() colors collapse to their hex fallbacks" do
      out = svg(:bar, @daisy)

      refute out =~ "var("
      assert out =~ "#008FFB"
      assert out =~ "#00E396"
    end

    test "daisy gradients shade with hex arithmetic, not color-mix()" do
      out = svg(:area, @daisy)

      refute out =~ "color-mix("
      refute out =~ "var("
      assert out =~ "stop-color"
    end

    test "daisy treemap shading stays hex" do
      heat = [%{name: "r1", data: [1, 2]}, %{name: "r2", data: [3, 4]}]
      out = EexCharts.to_svg("t", :treemap, heat, @daisy)

      refute out =~ "color-mix("
      refute out =~ "var("
    end
  end

  describe "interactive rendering is unchanged" do
    test "render/4 keeps its hover furniture and phx bindings" do
      {:safe, io} =
        EexCharts.render("t", :line, @series,
          categories: @categories,
          on_click: "point-selected"
        )

      out = IO.iodata_to_binary(io)

      assert out =~ "eexcharts-crosshair"
      assert out =~ "eexcharts-hover-marker"
      assert out =~ "eexcharts-zone"
      assert out =~ "eexcharts-tip"
      assert out =~ "phx-click=\"point-selected\""
      assert out =~ "phx-hook=\"EexCharts\""
      assert out =~ "data-j="
    end

    test "daisy render/4 keeps var() for the browser to resolve" do
      {:safe, io} =
        EexCharts.render("t", :area, @series,
          categories: @categories,
          options: %{theme: %{mode: :daisy}}
        )

      out = IO.iodata_to_binary(io)

      assert out =~ "var(--color-primary, #008FFB)"
      assert out =~ "color-mix("
    end
  end
end
