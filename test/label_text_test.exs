defmodule EexCharts.LabelTextTest do
  use ExUnit.Case, async: true

  alias EexCharts.{LabelText, Layout, Renderer, SVG}

  @key %{text: "01", fill: "#FF4560", font_weight: 700}

  defp html(node), do: node |> SVG.to_iodata() |> IO.iodata_to_binary()

  defp render(params) do
    params |> Renderer.render() |> SVG.to_iodata() |> IO.iodata_to_binary()
  end

  describe "content/3" do
    test "a plain string stays bare, escaped text" do
      assert html(LabelText.content("a < b", 10)) == "a &lt; b"
    end

    test "each line of a list becomes a tspan at x, 1.2em below the last" do
      assert html(LabelText.content(["one", "two"], 10)) ==
               ~s(<tspan x="10">one</tspan><tspan dy="1.2em" x="10">two</tspan>)
    end

    test "a styled segment is a nested tspan carrying only the keys it sets" do
      out = html(LabelText.content([[@key, " Asset <Inventory>"], ["and Tracking"]], 5))

      assert out ==
               ~s(<tspan x="5"><tspan fill="#FF4560" font-weight="700">01</tspan> Asset &lt;Inventory&gt;</tspan>) <>
                 ~s(<tspan dy="1.2em" x="5">and Tracking</tspan>)
    end

    test "a bare map is one styled segment" do
      assert html(LabelText.content(%{text: "x", font_size: 9}, 0)) ==
               ~s(<tspan font-size="9">x</tspan>)
    end

    test "grow decides where the block sits on the anchor" do
      assert html(LabelText.content(~w(a b c), 0, :center)) =~ ~s(<tspan dy="-1.2em" x="0">a)
      assert html(LabelText.content(~w(a b c), 0, :up)) =~ ~s(<tspan dy="-2.4em" x="0">a)
      assert html(LabelText.content(~w(a b c), 0, :down)) =~ ~s(<tspan x="0">a)
      assert html(LabelText.content(["a"], 0, :up)) == ~s(<tspan x="0">a</tspan>)
    end
  end

  describe "width/3" do
    test "is the widest line, segments summed" do
      w = &Layout.text_width(&1, 11, :arial)

      assert LabelText.width([[@key, " Asset"], ["x"]], 11, :arial) == w.("01") + w.(" Asset")
      assert LabelText.width(["short", "much longer"], 11, :arial) == w.("much longer")
    end

    test "measures a segment at its own font size" do
      assert LabelText.width([[%{text: "AB", font_size: 22}]], 11, :arial) ==
               Layout.text_width("AB", 22, :arial)
    end
  end

  test "plain/1 drops the styling and joins lines" do
    assert LabelText.plain([[@key, " Asset"], ["Tracking"]]) == "01 Asset Tracking"
    assert LabelText.plain(42) == "42"
  end

  describe "in charts" do
    test "radar category labels carry styled segments" do
      out =
        render(%{
          id: "lt1",
          type: :radar,
          series: [%{name: "S", data: [1, 2, 3]}],
          categories: ~w(A B C),
          options: %{xaxis: %{labels: %{formatter: fn c, _j -> [[@key, " ", c]] end}}}
        })

      assert out =~ ~s(<tspan fill="#FF4560" font-weight="700">01</tspan> A)
    end

    test "cartesian x-axis labels carry styled segments" do
      out =
        render(%{
          id: "lt2",
          type: :bar,
          series: [%{name: "S", data: [1, 2]}],
          categories: ~w(A B),
          options: %{xaxis: %{labels: %{formatter: fn c -> [[@key, " ", c]] end}}}
        })

      assert out =~ ~s(<tspan fill="#FF4560" font-weight="700">01</tspan> B)
    end

    test "y-axis labels carry styled segments and widen the gutter for them" do
      base = %{id: "lt3", type: :line, series: [%{name: "S", data: [10, 20]}]}

      plain = render(base)

      styled =
        render(
          Map.put(base, :options, %{
            yaxis: %{formatter: fn v -> [[to_string(v), %{text: " units", fill: "#999"}]] end}
          })
        )

      assert styled =~ ~s(<tspan fill="#999"> units</tspan>)

      label_x = fn out ->
        [_, x] = Regex.run(~r/class="eexcharts-yaxis-label"[^>]* x="([-\d.]+)"/, out)
        x |> Float.parse() |> elem(0)
      end

      assert label_x.(styled) > label_x.(plain) + 20
    end
  end
end
