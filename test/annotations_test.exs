defmodule EexCharts.AnnotationsTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  defp base(annotations) do
    %{
      id: "ann",
      type: :line,
      series: [%{name: "A", data: [10, 20, 15, 30]}],
      categories: ~w(Jan Feb Mar Apr),
      options: %{annotations: annotations}
    }
  end

  # Numeric attributes of the first tag containing `marker`.
  defp tag_attrs(html, marker) do
    [tag] = Regex.run(~r/<[a-z]+ [^>]*#{Regex.escape(marker)}[^>]*>/, html)

    for [_, k, v] <- Regex.scan(~r/([a-z-]+)="(-?[\d.]+)"/, tag), into: %{} do
      {k, num(v)}
    end
  end

  defp num(s), do: elem(Float.parse(s), 0)

  test "no annotations -> no annotations group" do
    html = render(%{id: "n", type: :line, series: [%{name: "A", data: [1, 2, 3]}]})
    refute html =~ "eexcharts-annotations"
  end

  describe "y-axis annotations" do
    test "y only draws a horizontal dashed line" do
      html = render(base(%{yaxis: [%{y: 20, border_color: "#00E396"}]}))

      assert html =~ "eexcharts-yaxis-annotations"
      assert html =~ "eexcharts-annotation-line"
      assert html =~ ~s(stroke="#00E396")
      assert html =~ "stroke-dasharray"
    end

    test "y + y2 draws a translucent band rect" do
      html = render(base(%{yaxis: [%{y: 10, y2: 25, fill_color: "#B3F7CA", opacity: 0.4}]}))

      assert html =~ "eexcharts-annotation-rect"
      assert html =~ ~s(fill="#B3F7CA")
      assert html =~ ~s(fill-opacity="0.4")
    end

    test "renders a label pill with escaped text" do
      html = render(base(%{yaxis: [%{y: 20, label: %{text: "<b>target</b>"}}]}))

      assert html =~ "eexcharts-annotation-label-rect"
      assert html =~ "eexcharts-annotation-label"
      assert html =~ "&lt;b&gt;target&lt;/b&gt;"
      refute html =~ "<b>target</b>"
    end

    test "value outside the scale range is skipped" do
      html = render(base(%{yaxis: [%{y: 100_000, border_color: "#123456"}]}))

      refute html =~ ~s(stroke="#123456")
    end

    test "label position :left anchors at the grid start" do
      html = render(base(%{yaxis: [%{y: 20, label: %{text: "L", position: :left}}]}))
      assert html =~ "eexcharts-annotation-label"
    end
  end

  describe "x-axis annotations" do
    test "x resolves a category string to a vertical line" do
      html = render(base(%{xaxis: [%{x: "Mar", border_color: "#FF4560"}]}))

      assert html =~ "eexcharts-xaxis-annotations"
      assert html =~ ~s(stroke="#FF4560")
    end

    test "x + x2 draws a band between two categories" do
      html = render(base(%{xaxis: [%{x: "Feb", x2: "Apr", fill_color: "#EEE1FF"}]}))

      assert html =~ "eexcharts-annotation-rect"
      assert html =~ ~s(fill="#EEE1FF")
    end

    test "vertical label orientation rotates -90 by default" do
      html = render(base(%{xaxis: [%{x: "Mar", label: %{text: "spring"}}]}))

      assert html =~ "rotate(-90"
      assert html =~ "spring"
    end

    test "horizontal orientation is not rotated" do
      html =
        render(base(%{xaxis: [%{x: "Mar", label: %{text: "spring", orientation: :horizontal}}]}))

      assert html =~ "spring"
      refute html =~ "rotate(-90"
    end

    test "a rotated label frame stays inside the plot at the top and bottom" do
      for position <- [:top, :bottom] do
        html =
          render(
            base(%{
              xaxis: [
                %{x: "Feb", x2: "Apr", label: %{text: "a rather long window", position: position}}
              ]
            })
          )

        # The band spans the full plot height, so it marks the plot edges.
        band = tag_attrs(html, ~s(class="eexcharts-annotation-rect"))
        grid_top = band["y"]
        grid_bottom = band["y"] + band["height"]

        # Rotating -90 about (cx, cy) maps the rect's x span onto y:
        # y' = cy - (x - cx). Half the stroke sits outside the rect.
        [_, cx, cy] = Regex.run(~r/rotate\(-90 ([\d.]+) ([\d.]+)\)/, html)
        {cx, cy} = {num(cx), num(cy)}
        rect = tag_attrs(html, ~s(class="eexcharts-annotation-label-rect"))
        half_stroke = rect["stroke-width"] / 2
        top = cy - (rect["x"] + rect["width"] - cx) - half_stroke
        bottom = cy - (rect["x"] - cx) + half_stroke

        assert top >= grid_top - 1.0e-6,
               "#{position}: frame top #{top} above plot top #{grid_top}"

        assert bottom <= grid_bottom + 1.0e-6,
               "#{position}: frame bottom #{bottom} below plot bottom #{grid_bottom}"
      end
    end

    test "unknown category is skipped" do
      html = render(base(%{xaxis: [%{x: "Nope", border_color: "#010203"}]}))
      refute html =~ ~s(stroke="#010203")
    end

    test "bare number is a category index when categories are empty" do
      html =
        render(%{
          id: "x",
          type: :line,
          series: [%{name: "A", data: [1, 2, 3, 4]}],
          options: %{annotations: %{xaxis: [%{x: 2, border_color: "#ABCDEF"}]}}
        })

      assert html =~ ~s(stroke="#ABCDEF")
    end
  end

  describe "point annotations" do
    test "draws a circle marker and a label pill" do
      html =
        render(base(%{points: [%{x: "Apr", y: 30, marker: %{size: 6}, label: %{text: "peak"}}]}))

      assert html =~ "eexcharts-point-annotations"
      assert html =~ "eexcharts-annotation-marker"
      assert html =~ "<circle"
      assert html =~ "peak"
    end

    test "square marker shape renders a rect" do
      html =
        render(base(%{points: [%{x: "Apr", y: 30, marker: %{size: 6, shape: :square}}]}))

      assert html =~ ~s(class="eexcharts-annotation-marker")
    end

    test "point label text is escaped" do
      html = render(base(%{points: [%{x: "Jan", y: 10, label: %{text: "a & b"}}]}))
      assert html =~ "a &amp; b"
    end

    test "point outside the scale range is skipped" do
      html =
        render(base(%{points: [%{x: "Apr", y: 999_999, marker: %{stroke_color: "#654321"}}]}))

      refute html =~ ~s(stroke="#654321")
    end
  end

  describe "horizontal bar charts" do
    test "y-axis value annotation becomes a vertical line" do
      html =
        render(%{
          id: "hb",
          type: :bar,
          series: [%{name: "A", data: [10, 20, 30]}],
          categories: ~w(a b c),
          options: %{
            plot_options: %{bar: %{horizontal: true}},
            annotations: %{yaxis: [%{y: 20, border_color: "#00AA00"}]}
          }
        })

      assert html =~ "eexcharts-yaxis-annotations"
      assert html =~ ~s(stroke="#00AA00")
    end

    test "x-axis category annotation becomes a horizontal line" do
      html =
        render(%{
          id: "hb2",
          type: :bar,
          series: [%{name: "A", data: [10, 20, 30]}],
          categories: ~w(a b c),
          options: %{
            plot_options: %{bar: %{horizontal: true}},
            annotations: %{xaxis: [%{x: "b", border_color: "#0000AA"}]}
          }
        })

      assert html =~ "eexcharts-xaxis-annotations"
      assert html =~ ~s(stroke="#0000AA")
    end
  end

  test "partial label map inherits defaults (no crash, pill rendered)" do
    html = render(base(%{yaxis: [%{y: 20, label: %{text: "ok"}}]}))
    assert html =~ ~s(fill="#fff")
    assert html =~ "ok"
  end

  describe "numeric x-axis" do
    defp scatter(annotations) do
      render(%{
        id: "sc",
        type: :scatter,
        series: [%{name: "A", data: [[18, 52], [47, 72], [71, 84]]}],
        options: %{
          xaxis: %{min: 0, max: 100},
          yaxis: %{min: 0, max: 100},
          annotations: annotations
        }
      })
    end

    defp line_x(html) do
      [_, x] = Regex.run(~r/<line class="eexcharts-annotation-line"[^>]* x1="([-\d.e]+)"/, html)
      x |> Float.parse() |> elem(0)
    end

    test "x is a data value, not a category index" do
      at = fn x -> line_x(scatter(%{xaxis: [%{x: x}]})) end

      assert_in_delta at.(50), (at.(0) + at.(100)) / 2, 0.001
      assert_in_delta at.(47) - at.(0), (at.(100) - at.(0)) * 0.47, 0.001
    end

    test "x + x2 draws a band between the two values" do
      html = scatter(%{xaxis: [%{x: 70, x2: 90, fill_color: "#FEB019"}]})

      assert html =~ "eexcharts-annotation-rect"
      assert html =~ ~s(fill="#FEB019")
    end

    test "values outside the axis range are skipped" do
      refute scatter(%{xaxis: [%{x: 140}]}) =~ "eexcharts-annotation-line"
      refute scatter(%{xaxis: [%{x: "Jan"}]}) =~ "eexcharts-annotation-line"
    end

    test "point annotations are placed by value" do
      html = scatter(%{points: [%{x: 27, y: 59, label: %{text: "Point (27, 59)"}}]})

      assert html =~ "eexcharts-annotation-marker"
      assert html =~ "Point (27, 59)"
    end
  end

  describe "datetime x-axis" do
    defp timeline(x) do
      render(%{
        id: "dt",
        type: :line,
        series: [
          %{
            name: "A",
            data: [["2026-01-01", 10], ["2026-01-15", 30], ["2026-02-01", 20]]
          }
        ],
        options: %{xaxis: %{type: :datetime}, annotations: %{xaxis: [%{x: x}]}}
      })
    end

    test "accepts ISO 8601 strings, dates and unix ms" do
      ms = DateTime.to_unix(~U[2026-01-10 00:00:00Z], :millisecond)

      assert line_x(timeline("2026-01-10")) == line_x(timeline(~D[2026-01-10]))
      assert line_x(timeline("2026-01-10")) == line_x(timeline(ms))
    end

    test "a string that is no date is skipped rather than placed on the epoch" do
      refute timeline("soon") =~ "eexcharts-annotation-line"
    end
  end
end
