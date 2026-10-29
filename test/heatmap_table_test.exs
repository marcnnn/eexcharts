defmodule EexCharts.HeatmapTableTest do
  use ExUnit.Case, async: true

  alias EexCharts.Charts.Heatmap.Rows

  @cats ["01", "02", "03", "04"]

  defp live(series, options, opts \\ []) do
    {:safe, io} =
      EexCharts.render("ht", :heatmap, series, [options: options, categories: @cats] ++ opts)

    IO.iodata_to_binary(io)
  end

  defp static(series, options),
    do: EexCharts.to_svg("ht", :heatmap, series, options: options, categories: @cats)

  defp tags(svg, tag), do: Regex.scan(~r/<#{tag}\b[^>]*>/, svg) |> List.flatten()

  defp num(tag, name) do
    [_, v] = Regex.run(~r/\s#{name}="([^"]*)"/, tag)
    v |> Float.parse() |> elem(0)
  end

  defp rect(svg, key), do: svg |> tags("rect") |> Enum.find(&(&1 =~ ~s(data-j="#{key}")))

  defp group(svg, class) do
    case Regex.run(~r/<g class="#{class}">.*?<\/g>/s, svg) do
      [g] -> g
      nil -> nil
    end
  end

  defp texts(svg, class) do
    Regex.scan(~r/<text([^>]*)>([^<]*)<\/text>/, group(svg, class))
    |> Enum.map(fn [_, attrs, text] -> {text, attrs} end)
  end

  @series for {n, k} <- Enum.with_index(["Row A", "Row B", "Row C", "Row D", "Row E"]),
              do: %{name: n, data: for(j <- 0..3, do: 10 + k * 10 + j)}

  @groups [%{name: "Group 1", rows: 2}, %{name: "Group 2", rows: 3}]

  @summary [%{name: "Summary row", data: [20, %{x: "02", y: 30, fill_color: "#123456"}, 40, 50]}]

  defp heat(opts), do: %{plot_options: %{heatmap: Map.new(opts)}}

  defp table do
    Map.merge(
      heat(reverse_rows: true, row_groups: @groups, summary_rows: @summary),
      %{xaxis: %{position: :top, marked: ["01"]}}
    )
  end

  describe "row groups" do
    test "group names sit level with each group's first row, groups are set apart" do
      svg = live(@series, heat(reverse_rows: true, row_groups: @groups, group_gap: 12))

      [{"Group 1", g1}, {"Group 2", g2}] = texts(svg, "eexcharts-heatmap-groups")
      assert g1 =~ ~s(font-weight="700")

      ya = num(rect(svg, "0-0"), "y")
      yb = num(rect(svg, "1-0"), "y")
      yc = num(rect(svg, "2-0"), "y")
      h = num(rect(svg, "0-0"), "height")

      assert_in_delta yb - ya, h, 0.001
      assert_in_delta yc - yb, h + 12, 0.001
      assert_in_delta num("<x " <> g1, "y"), ya + h / 2, 0.001
      assert_in_delta num("<x " <> g2, "y"), yc + h / 2, 0.001
    end

    test "groups count rows from the top of the drawn order" do
      # Default order draws the last series on top: Row E, Row D form group 1.
      svg = live(@series, heat(row_groups: @groups))

      [{"Group 1", g1}, _] = texts(svg, "eexcharts-heatmap-groups")
      e = rect(svg, "4-0")
      assert_in_delta num("<x " <> g1, "y"), num(e, "y") + num(e, "height") / 2, 0.001
    end

    test "the group column pushes the plot right of the row names" do
      plain = live(@series, %{})
      grouped = live(@series, heat(row_groups: @groups))

      assert num(rect(grouped, "0-0"), "x") > num(rect(plain, "0-0"), "x")
    end

    test "hiding every row of a group drops its name and gap" do
      svg = live(@series, heat(reverse_rows: true, row_groups: @groups), hidden_series: [0, 1])

      assert [{"Group 2", _}] = texts(svg, "eexcharts-heatmap-groups")
    end

    test "Rows.layout spends the gaps before splitting the height" do
      cfg = EexCharts.Config.build(:heatmap, heat(reverse_rows: true, row_groups: @groups))
      series = Enum.with_index(@series, fn s, i -> Map.put(s, :index, i) end)

      %{rows: rows, rule_y: nil} = Rows.layout(cfg, series, series, 0, 512)
      assert Enum.map(rows, & &1.h) |> Enum.uniq() == [100.0]
      assert List.last(rows).y + 100 == 512
    end
  end

  describe "summary rows" do
    @summary [
      %{name: "Summary row", data: [20, %{x: "02", y: 30, fill_color: "#123456"}, 40, 50]}
    ]

    test "follow the last row below a rule in the grid border colour" do
      svg = live(@series, heat(reverse_rows: true, summary_rows: @summary, summary_gap: 20))

      [rule] = tags(svg, "line") |> Enum.filter(&(&1 =~ "eexcharts-heatmap-rule"))
      assert rule =~ ~s(stroke="#e0e0e0")

      last = rect(svg, "4-0")
      bottom = num(last, "y") + num(last, "height")
      summary_y = num(rect(svg, "s0-0"), "y")

      assert_in_delta summary_y - bottom, 20, 0.001
      assert_in_delta num(rule, "y1"), bottom + 10, 0.001
    end

    test "names and values are bold; fill_color overrides the scale" do
      svg = live(@series, Map.put(heat(summary_rows: @summary), :data_labels, %{enabled: true}))

      {"Summary row", attrs} =
        svg |> texts("eexcharts-yaxis-labels") |> List.keyfind("Summary row", 0)

      assert attrs =~ ~s(font-weight="700")
      assert attrs =~ ~s(text-anchor="start")
      assert svg =~ ~r/font-weight="700"[^>]*>50<\/text>/
      assert rect(svg, "s0-1") =~ ~s(fill="#123456")
    end

    test "use the colour ranges like every other row" do
      ranges = [%{from: 0, to: 100, color: "#00A100"}]
      opts = heat(summary_rows: @summary, enable_shades: false, color_scale: %{ranges: ranges})
      svg = live(@series, opts)

      assert rect(svg, "s0-0") =~ ~s(fill="#00A100")
      assert rect(svg, "0-0") =~ ~s(fill="#00A100")
    end

    test "a click reports the summary row, not a series" do
      svg = live(@series, heat(summary_rows: @summary), on_click: "cell")

      assert rect(svg, "s0-2") =~ ~s(phx-value-summary="0")
      refute rect(svg, "s0-2") =~ "phx-value-series"
      assert svg =~ ~r/data-j="s0-2" hidden.*?Summary row/s
    end
  end

  describe "marked columns" do
    test "a bar over each marked column, above the labels on a top axis" do
      options = %{xaxis: %{position: :top, marked: ["02", "04"]}}
      svg = live(@series, options)

      bars = group(svg, "eexcharts-heatmap-marked") |> tags("rect")
      assert length(bars) == 2

      [b2, b4] = bars
      col = rect(svg, "0-1")

      assert_in_delta num(b2, "x") + num(b2, "width") / 2,
                      num(col, "x") + num(col, "width") / 2,
                      0.001

      assert_in_delta num(b2, "width"), 0.75 * num(col, "width"), 0.001
      assert num(b4, "x") > num(b2, "x")

      label_ys =
        texts(svg, "eexcharts-xaxis-labels") |> Enum.map(fn {_, a} -> num("<x " <> a, "y") end)

      assert num(b2, "y") + 4 < Enum.min(label_ys) - 12
      assert b2 =~ ~s(fill="#373d3f")
    end

    test "with the axis below, the bar sits just above the plot" do
      svg = live(@series, %{xaxis: %{marked: ["01"]}})
      [bar] = group(svg, "eexcharts-heatmap-marked") |> tags("rect")

      top =
        svg
        |> tags("rect")
        |> Enum.filter(&(&1 =~ "heatmap-rect"))
        |> Enum.map(&num(&1, "y"))
        |> Enum.min()

      assert_in_delta num(bar, "y") + 4 + 4, top, 0.001
    end

    test "colour and height can be set; a name adds a legend entry" do
      ranges = [%{from: 0, to: 100, color: "#00A100", name: "all"}]

      options =
        Map.merge(heat(color_scale: %{ranges: ranges}), %{
          xaxis: %{
            marked: ["01"],
            marked_bar: %{color: "#ff6105", height: 6, name: "Marked column"}
          }
        })

      svg = live(@series, options)
      [bar] = group(svg, "eexcharts-heatmap-marked") |> tags("rect")

      assert bar =~ ~s(fill="#ff6105")
      assert bar =~ ~s(height="6")
      assert svg =~ "Marked column</text>"
    end
  end

  test "everything works without data labels" do
    options =
      Map.merge(
        heat(reverse_rows: true, row_groups: @groups, summary_rows: @summary),
        %{xaxis: %{position: :top, marked: ["01"]}}
      )

    svg = live(@series, options)

    refute svg =~ "eexcharts-datalabel"
    assert group(svg, "eexcharts-heatmap-groups")
    assert group(svg, "eexcharts-heatmap-marked")
    assert rect(svg, "s0-0")
  end

  test "enable_shades: false paints the series colour without shading" do
    svg = live(@series, heat(enable_shades: false))

    for j <- 0..3 do
      assert rect(svg, "0-#{j}") =~ ~s(fill="#008FFB")
      assert rect(svg, "1-#{j}") =~ ~s(fill="#00E396")
    end
  end

  describe "themes" do
    test "dark: labels and the marked bar use the light fore colour" do
      svg = live(@series, Map.put(table(), :theme, %{mode: :dark}))

      [bar] = group(svg, "eexcharts-heatmap-marked") |> tags("rect")
      assert bar =~ ~s(fill="#f6f7f8")
      assert group(svg, "eexcharts-heatmap-groups") =~ ~s(fill="#f6f7f8")
    end

    test "daisy live: rule, bar and group names follow the theme variables" do
      svg = live(@series, Map.put(table(), :theme, %{mode: :daisy}))

      [rule] = tags(svg, "line") |> Enum.filter(&(&1 =~ "eexcharts-heatmap-rule"))
      assert rule =~ "var(--color-base-300"
      assert group(svg, "eexcharts-heatmap-marked") =~ "var(--color-base-content"
      assert group(svg, "eexcharts-heatmap-groups") =~ "var(--color-base-content"
      assert rect(svg, "s0-0") =~ "var(--color-"
    end

    test "daisy static: no var() is left" do
      svg = static(@series, Map.put(table(), :theme, %{mode: :daisy}))

      refute svg =~ "var("
      assert svg =~ "eexcharts-heatmap-rule"
    end
  end
end
