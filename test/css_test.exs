defmodule EexCharts.CSSTest do
  use ExUnit.Case, async: true

  alias EexCharts.CSS

  @payload "red;background:url(https://example.com/x)"
  @font_payload "Arial;background:url(https://example.com/f)"

  defp html(type, series, opts) do
    {:safe, io} = EexCharts.render("c", type, series, opts)
    IO.iodata_to_binary(io)
  end

  describe "safe_value?/1" do
    test "accepts colors, gradient references and font stacks" do
      for v <- [
            "#fff",
            "#FF4560",
            "red",
            "transparent",
            "rgba(0, 0, 0, 0.5)",
            "rgb(0 0 0 / 50%)",
            "oklch(49% 0.3 275)",
            "var(--color-primary, #570df8)",
            "color-mix(in oklab, #fff 20%, var(--color-primary, oklch(49% 0.3 275)))",
            "url(#c-grad-0)",
            "'Helvetica Neue', Arial, sans-serif",
            "\"Segoe UI\", Roboto",
            "微软雅黑",
            "calc(100% - 2px)",
            "0 1px 0 0",
            12,
            0.4,
            :bold
          ] do
        assert CSS.safe_value?(v), "expected #{inspect(v)} to be accepted"
      end
    end

    test "rejects anything that adds a declaration, a rule or a fetch" do
      for v <- [
            @payload,
            "url(https://example.com/x)",
            "url(//example.com/x)",
            "URL(x.png)",
            "url(#a) url(//example.com/x)",
            "image-set(\"//example.com/x\" 1x)",
            "expression(alert(1))",
            "red/**/",
            "a:b",
            "red !important",
            "x\\3b y",
            "@import x",
            "red}body{color:red",
            "\"unbalanced",
            "<b>"
          ] do
        refute CSS.safe_value?(v), "expected #{inspect(v)} to be rejected"
      end
    end
  end

  describe "rendered charts drop unsafe CSS values" do
    test "series color and palette, in SVG fills and the tooltip marker" do
      out =
        html(:bar, [%{name: "S", data: [1, 2], color: @payload}],
          categories: ["a", "b"],
          options: %{colors: [@payload], chart: %{background: @payload}}
        )

      refute out =~ "example.com"
      assert out =~ ~s(class="eexcharts-tip-marker" style="")
    end

    test "HTML legend color and font family" do
      out =
        html(:line, [%{name: "S", data: [1, 2]}, %{name: "T", data: [2, 1]}],
          options: %{colors: [@payload], legend: %{html: true, font_family: @font_payload}}
        )

      refute out =~ "example.com"
      assert out =~ "eexcharts-legend-text"
    end

    test "styled label segments" do
      out =
        html(:bar, [%{name: "S", data: [1, 2]}],
          categories: ["a", "b"],
          options: %{
            xaxis: %{
              labels: %{
                formatter: fn l, _ ->
                  [[%{text: l, fill: @payload, font_family: @font_payload}]]
                end
              }
            }
          }
        )

      refute out =~ "example.com"
      assert out =~ ">a</tspan>"
    end

    test "annotations and per-point scatter markers" do
      out =
        html(:scatter, [%{name: "S", data: [[1, 1], [2, 2]]}],
          options: %{
            markers: %{discrete: [%{series_index: 0, data_point_index: 0, fill_color: @payload}]},
            annotations: %{
              yaxis: [
                %{y: 1, border_color: @payload, label: %{text: "t", style: %{color: @payload}}}
              ]
            }
          }
        )

      refute out =~ "example.com"
    end

    test "chart font family on the root svg" do
      out =
        html(:line, [%{name: "S", data: [1, 2]}],
          options: %{chart: %{font_family: @font_payload}}
        )

      refute out =~ "example.com"
    end

    test "safe colors still come through unchanged" do
      out =
        html(:bar, [%{name: "S", data: [1, 2]}],
          categories: ["a", "b"],
          options: %{colors: ["#123456"]}
        )

      assert out =~ ~s(fill="#123456")
      assert out =~ ~s(style="background:#123456;")
    end
  end

  test "a malformed hex color shades through color-mix instead of raising" do
    assert EexCharts.Color.shade("#ggg", 0.2) == "color-mix(in oklab, #fff 20%, #ggg)"
    assert EexCharts.Color.parse("#zz") == {55, 61, 63}
  end
end
