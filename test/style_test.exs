defmodule EexCharts.StyleTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Renderer}

  @chartjs ["#36A2EB", "#FF6384", "#FF9F40", "#FFCD56", "#4BC0C0", "#9966FF", "#C9CBCF"]

  defmodule Thick do
    @behaviour EexCharts.Style
    @impl true
    def defaults(:line), do: %{stroke: %{width: 9}}
    def defaults(_), do: %{}
  end

  defp render(type, series, options, extra \\ %{}) do
    %{id: "c", type: type, series: series, options: options}
    |> Map.merge(extra)
    |> Renderer.render()
    |> EexCharts.SVG.to_iodata()
    |> IO.iodata_to_binary()
  end

  @two [%{name: "A", data: [1, 2, 3]}, %{name: "B", data: [3, 2, 1]}]

  describe "layering" do
    test "the default style leaves ApexCharts defaults alone" do
      assert Config.build(:line) == Config.build(:line, %{style: :apexcharts})
      assert Config.build(:line).stroke.width == 5
    end

    test "a style overrides the per-type defaults" do
      cfg = Config.build(:line, %{style: :chartjs})

      assert cfg.stroke.width == 3
      assert cfg.markers.size == 3
      assert cfg.legend.position == :top
      assert cfg.colors == @chartjs
    end

    test "user options win over the style" do
      cfg = Config.build(:line, %{style: :chartjs, stroke: %{width: 1}, colors: ["#123456"]})

      assert cfg.stroke.width == 1
      assert cfg.colors == ["#123456"]
    end

    test "a custom module implementing the behaviour" do
      assert Config.build(:line, %{style: Thick}).stroke.width == 9
      assert Config.build(:bar, %{style: Thick}).stroke.width == 0
    end

    test "an unknown style raises" do
      assert_raise ArgumentError, ~r/unknown chart style :nope/, fn ->
        Config.build(:line, %{style: :nope})
      end
    end

    test "composes with the daisy theme: daisy chrome, Chart.js series" do
      cfg = Config.build(:bar, %{style: :chartjs, theme: %{mode: :daisy}})

      assert cfg.colors == @chartjs
      assert cfg.grid.border_color == "var(--color-base-300, #e0e0e0)"
      assert cfg.fill.opacity == 0.5
    end

    test "dark mode keeps the style's palette" do
      cfg = Config.build(:line, %{style: :chartjs, theme: %{mode: :dark}})

      assert cfg.colors == @chartjs
      assert cfg.chart.fore_color == "#f6f7f8"
    end
  end

  describe "top legend under a title" do
    for style <- [:apexcharts, :chartjs] do
      test "sits above the plot (#{style})" do
        svg =
          render(:line, @two, %{
            style: unquote(style),
            title: %{text: "Title"},
            legend: %{position: :top}
          })

        grid_top =
          ~r/class="eexcharts-grid-line"[^>]*y1="([\d.]+)"/
          |> Regex.scan(svg)
          |> Enum.map(fn [_, y] -> Float.parse(y) |> elem(0) end)
          |> Enum.min()

        [_, legend_y] = Regex.run(~r/class="eexcharts-legend-text"[^>]*y="([\d.]+)"/, svg)
        {legend_y, _} = Float.parse(legend_y)

        assert legend_y + 6 < grid_top
      end
    end

    test "drops below the title by ApexCharts' 2 * titleH + margin - 20" do
      y = fn opts ->
        svg = render(:line, @two, Map.put(opts, :legend, %{position: :top}))
        [_, y] = Regex.run(~r/class="eexcharts-legend-text"[^>]*y="([\d.]+)"/, svg)
        Float.parse(y) |> elem(0)
      end

      assert_in_delta y.(%{title: %{text: "Title"}}) - y.(%{}), 32, 0.01
    end
  end

  describe "light theme palette" do
    test "a named palette applies in light mode too" do
      cfg = Config.build(:line, %{theme: %{palette: :palette6}})
      assert cfg.colors == EexCharts.Theme.palette(:palette6)
    end
  end

  describe "Chart.js rendering" do
    test "line points: translucent body, ring in the series color" do
      svg = render(:line, @two, %{style: :chartjs})

      assert svg =~
               ~r/class="eexcharts-marker"[^>]*fill="#36A2EB" fill-opacity="0.5"[^>]*stroke="#36A2EB"/

      assert svg =~ ~r/class="eexcharts-marker"[^>]*stroke="#FF6384"/
    end

    test "legend swatches are 40x12 boxes outlined in the series color" do
      svg = render(:line, @two, %{style: :chartjs})

      assert svg =~
               ~r/<rect class="eexcharts-legend-marker" fill="#36A2EB" fill-opacity="0.5" height="12" rx="0" stroke="#36A2EB" stroke-width="3" width="40"/
    end

    test "the HTML legend sizes its marker box to the swatch" do
      svg = render(:line, @two, %{style: :chartjs, legend: %{html: true}})
      assert svg =~ "width:42px;height:14px;"
    end

    test "bar borders take the series color once they have a width" do
      plain = render(:bar, @two, %{style: :chartjs})
      refute plain =~ ~r/class="eexcharts-bar"[^>]*stroke="/

      bordered = render(:bar, @two, %{style: :chartjs, stroke: %{width: 1}})

      assert bordered =~
               ~r/class="eexcharts-bar"[^>]*fill="#36A2EB" fill-opacity="0.5" stroke="#36A2EB"/
    end

    test "area fills flat instead of with a gradient" do
      svg = render(:area, @two, %{style: :chartjs})

      refute svg =~ "linearGradient"
      assert svg =~ ~r/fill="#36A2EB" fill-opacity="0.5"/
    end
  end
end
