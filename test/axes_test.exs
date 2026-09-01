defmodule EexCharts.AxesTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Layout}
  alias EexCharts.Renderer

  defp render(params),
    do: params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()

  describe "numeric x-axis" do
    test "builds a linear x scale positioned by value" do
      cfg = Config.build(:scatter, %{xaxis: %{type: :numeric}})
      l = Layout.build(cfg, ["A"], 3, [{0, 30}], {0, 10})

      assert l.x_scale.type == :numeric
      assert l.x_type == :numeric
      # leftmost value sits at grid_x, rightmost at grid_x + grid_w
      assert_in_delta Layout.x_value_pos(l, l.x_scale.nice_min), l.grid_x, 0.001
      assert_in_delta Layout.x_value_pos(l, l.x_scale.nice_max), l.grid_x + l.grid_w, 0.001
    end

    test "renders x-axis labels at scale ticks" do
      html =
        render(%{
          id: "num",
          type: :line,
          series: [%{name: "A", data: [[0, 5], [50, 6], [100, 7]]}],
          options: %{xaxis: %{type: :numeric}}
        })

      assert html =~ "eexcharts-xaxis-labels"
    end

    test "respects xaxis min/max overrides" do
      cfg = Config.build(:line, %{xaxis: %{type: :numeric, min: 0, max: 100}})
      l = Layout.build(cfg, ["A"], 5, [{10, 90}], {10, 90})
      assert l.x_scale.nice_min == 0
      assert l.x_scale.nice_max == 100
    end
  end

  describe "datetime x-axis" do
    test "builds datetime ticks with formatted labels" do
      cfg = Config.build(:line, %{xaxis: %{type: :datetime}})
      # ~3 months
      l = Layout.build(cfg, ["A"], 3, [{0, 30}], {1_609_459_200_000, 1_617_235_200_000})

      assert l.x_scale.type == :datetime
      assert l.x_scale.ticks != []
      labels = Enum.map(l.x_scale.ticks, & &1.label)
      assert Enum.all?(labels, &is_binary/1)
    end

    test "accepts DateTime/Date structs as x values" do
      html =
        render(%{
          id: "dt",
          type: :scatter,
          series: [
            %{
              name: "A",
              data: [
                [~D[2021-01-01], 10],
                [~D[2021-02-01], 20],
                [~D[2021-03-01], 15]
              ]
            }
          ],
          options: %{xaxis: %{type: :datetime}}
        })

      assert html =~ "<svg"
      assert html =~ "eexcharts-xaxis-labels"
    end
  end

  describe "logarithmic y-axis" do
    test "uses a log scale and maps y through log space" do
      cfg = Config.build(:line, %{yaxis: %{logarithmic: true, log_base: 10}})
      l = Layout.build(cfg, ["A"], 3, {1, 10_000})

      assert l.scale.log
      # 100 is the geometric midpoint of [1, 10000] -> middle of the grid
      mid = Layout.y_for(l, 100)
      assert_in_delta mid, l.grid_y + l.grid_h / 2, 0.001
    end

    test "renders without error" do
      html =
        render(%{
          id: "log",
          type: :line,
          series: [%{name: "A", data: [1, 100, 10_000]}],
          options: %{yaxis: %{logarithmic: true}}
        })

      assert html =~ "<svg"
    end
  end

  describe "multiple y-axes" do
    test "each axis gets its own scale from its series" do
      cfg =
        Config.build(:line, %{yaxis: [%{}, %{opposite: true}]})

      l = Layout.build(cfg, ["A", "B"], 3, [{0, 3}, {0, 300}], nil)

      assert length(l.scales) == 2
      assert length(l.y_axes) == 2
      [a0, a1] = l.scales
      assert a0.nice_max <= 10
      assert a1.nice_max >= 300
    end

    test "opposite axis renders labels on the right and a right title" do
      html =
        render(%{
          id: "multi",
          type: :line,
          series: [
            %{name: "A", data: [1, 2, 3]},
            %{name: "B", data: [100, 200, 300]}
          ],
          options: %{
            yaxis: [
              %{title: %{text: "Left"}},
              %{opposite: true, title: %{text: "Right"}}
            ]
          }
        })

      assert html =~ "Left"
      assert html =~ "Right"
      # right title is rotated +90 (left is -90)
      assert html =~ "rotate(90"
    end

    test "series bind to an axis by series_name" do
      y_axes = Config.yaxes(Config.build(:line, %{yaxis: [%{}, %{series_name: "revenue"}]}))
      s = %{name: "revenue", index: 0}
      assert Layout.axis_index_for(y_axes, s) == 1
    end
  end
end
