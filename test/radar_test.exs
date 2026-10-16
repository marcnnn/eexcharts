defmodule EexCharts.RadarTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  describe "radar charts" do
    test "renders a concentric polygon grid and spokes for the categories" do
      html =
        render(%{
          id: "rd1",
          type: :radar,
          series: [%{name: "S1", data: [80, 50, 30, 40, 100]}],
          categories: ~w(Jan Feb Mar Apr May)
        })

      assert html =~ "<svg"
      assert html =~ ~s(class="eexcharts-radar-grid")
      # grid polygons present
      assert html =~ "<polygon"
      # one spoke line per category (5)
      assert length(String.split(html, "<line")) >= 6
      # perimeter category labels
      assert html =~ "Jan"
      assert html =~ "May"
    end

    test "each series is a closed polygon with vertex markers" do
      html =
        render(%{
          id: "rd2",
          type: :radar,
          series: [
            %{name: "A", data: [10, 20, 30]},
            %{name: "B", data: [30, 20, 10]}
          ],
          categories: ~w(x y z)
        })

      assert html =~ ~s(class="eexcharts-radar-area")
      # path is closed
      assert html =~ " Z"
      # markers (size 5) per vertex
      assert html =~ ~s(class="eexcharts-marker")
      assert html =~ ~s(r="5")
      # both series colours
      assert html =~ "#008FFB"
      assert html =~ "#00E396"
      # faint fill
      assert html =~ ~s(fill-opacity="0.2")
    end

    test "tooltips are keyed per category and list visible series" do
      html =
        render(%{
          id: "rd3",
          type: :radar,
          series: [
            %{name: "S1", data: [80, 50]},
            %{name: "S2", data: [20, 30]}
          ],
          categories: ~w(One Two)
        })

      assert html =~ ~s(class="eexcharts-tip" data-j="0")
      assert html =~ ~s(class="eexcharts-tip" data-j="1")
      assert html =~ "One"
      assert html =~ "Two"
      # both series appear in a tooltip
      assert html =~ "S1"
      assert html =~ "S2"
    end

    test "markers carry data-j (category index) for tooltip matching" do
      html =
        render(%{
          id: "rd4",
          type: :radar,
          series: [%{name: "S1", data: [1, 2, 3, 4]}],
          categories: ~w(a b c d)
        })

      for j <- 0..3 do
        assert html =~ ~s(data-j="#{j}")
      end
    end

    test "hidden series are excluded but keep stable colours and a legend entry" do
      html =
        render(%{
          id: "rd5",
          type: :radar,
          series: [
            %{name: "S1", data: [10, 20, 30]},
            %{name: "S2", data: [30, 20, 10]}
          ],
          categories: ~w(x y z),
          hidden_series: [0],
          on_legend_click: "toggle"
        })

      # legend still lists both, hidden one dimmed
      assert html =~ "S1"
      assert html =~ "S2"
      assert html =~ ~s(opacity="0.4")
      # visible series (index 1) keeps its palette colour #00E396
      assert html =~ ~s(class="eexcharts-radar-area")
      assert html =~ "#00E396"
      assert html =~ ~s(phx-click="toggle")
    end

    test "on_click wires phx-click with index and series on markers" do
      html =
        render(%{
          id: "rd6",
          type: :radar,
          series: [%{name: "S1", data: [10, 20]}],
          categories: ~w(a b),
          on_click: "pick"
        })

      assert html =~ ~s(phx-click="pick")
      assert html =~ ~s(phx-value-index="1")
      assert html =~ ~s(phx-value-series="0")
    end

    test "falls back to xaxis categories and synthesises labels when missing" do
      html =
        render(%{
          id: "rd7",
          type: :radar,
          series: [%{name: "S1", data: [5, 10, 15]}]
        })

      # no categories supplied -> spokes still drawn, no crash
      assert html =~ ~s(class="eexcharts-radar-grid")
      assert html =~ ~s(class="eexcharts-radar-area")
    end

    test "escapes user-provided category text" do
      html =
        render(%{
          id: "rd8",
          type: :radar,
          series: [%{name: "S1", data: [1, 2]}],
          categories: ["<b>", "ok"]
        })

      refute html =~ "<b>ok"
      assert html =~ "&lt;b&gt;"
    end
  end

  describe "wrapped category labels" do
    @long ~w(Alpha Beta Gamma Delta Epsilon Zeta)
          |> Enum.map(&"#{&1} Category With A Long Name")

    defp radar_with(formatter) do
      opts = if formatter, do: %{xaxis: %{labels: %{formatter: formatter}}}, else: %{}

      render(%{
        id: "rw",
        type: :radar,
        series: [%{name: "S1", data: [1, 2, 3, 4, 5, 6]}],
        categories: @long,
        width: 560,
        height: 460,
        options: opts
      })
    end

    # Spoke 0 runs from the top vertex straight down to the centre, so its
    # length is the plot radius.
    defp radius(html) do
      [line] = Regex.run(~r/<line [^>]*>/, html)
      [_, y1] = Regex.run(~r/ y1="([-\d.]+)"/, line)
      [_, y2] = Regex.run(~r/ y2="([-\d.]+)"/, line)
      num(y2) - num(y1)
    end

    defp num(s), do: s |> Float.parse() |> elem(0)

    defp halves(label) do
      words = String.split(label)
      {a, b} = Enum.split(words, div(length(words), 2))
      [Enum.join(a, " "), Enum.join(b, " ")]
    end

    test "the label reserve is measured on the longest formatted line" do
      plain = radar_with(nil)
      wrapped = radar_with(&halves/1)

      assert radius(wrapped) > radius(plain) + 30
    end

    test "an arity-1 formatter may return a list of lines" do
      html = radar_with(&halves/1)

      assert html =~ ~s(>Alpha Category With</tspan>)
      assert html =~ ~s(>A Long Name</tspan>)
      refute html =~ "WithA"
    end

    test "wrapped labels on the top spoke keep the radius inside the box" do
      html =
        render(%{
          id: "rv",
          type: :radar,
          series: [%{name: "S1", data: [1, 2, 3, 4]}],
          categories: ~w(N E S W),
          width: 600,
          height: 200,
          options: %{
            legend: %{show: false},
            xaxis: %{labels: %{formatter: fn c -> [c, "line 2", "line 3"] end}}
          }
        })

      font_size = 11
      assert radius(html) <= 100 - 10 - font_size * (0.6 + 1.2 * 2) + 0.001
    end
  end
end
