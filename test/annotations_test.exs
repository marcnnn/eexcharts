defmodule EexCharts.AnnotationsTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  defp render(params) do
    params |> Renderer.render() |> IO.iodata_to_binary()
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
end
