defmodule EexCharts.PDF.OpsTest do
  @moduledoc """
  The tree walker, one element at a time.

  Everything here is about the two coordinate systems disagreeing: SVG puts
  the origin top-left with y growing down, PDF puts it bottom-left with y
  growing up. The snapshot tests prove the whole output is stable; these prove
  it is stable at the *right* coordinates.
  """
  use ExUnit.Case, async: true

  import EexCharts.SVG

  alias EexCharts.PDF.Ops

  # A 100×100 chart, so a y of 30 in SVG is a y of 70 in PDF and the flip is
  # readable at a glance.
  defp ops(children, opts \\ []) do
    el("svg", %{viewBox: "0 0 100 100"}, children)
    |> Ops.build(
      Keyword.get(opts, :x, 0),
      Keyword.get(opts, :y, 0),
      Keyword.get(opts, :scale, 1)
    )
  end

  describe "the y flip" do
    test "a rectangle is placed by its bottom edge" do
      assert ops([el("rect", %{x: 10, y: 20, width: 30, height: 40, fill: "#000"})]) ==
               [
                 {:set_opacity, 1.0},
                 {:set_non_stroking_rgb, 0.0, 0.0, 0.0},
                 {:rectangle, 10, 40, 30, 40},
                 :fill
               ]
    end

    test ":x and :y move the whole chart, :scale sizes it" do
      assert [_, _, {:rectangle, 105.0, 220.0, 15.0, 20.0}, :fill] =
               ops([el("rect", %{x: 10, y: 20, width: 30, height: 40, fill: "#000"})],
                 x: 100,
                 y: 200,
                 scale: 0.5
               )
    end

    test "a line keeps its endpoints, flipped" do
      assert [_, _, _, _, _, _, {:move_to, {0, 100}}, {:line_to, {100, 0}}, :stroke] =
               ops([el("line", %{x1: 0, y1: 0, x2: 100, y2: 100, stroke: "#000"})])
    end
  end

  describe "rotation under the flip" do
    # The y-axis title's transform, and the one case worth pinning by hand.
    test "rotate(-90 x y) becomes a +90° page rotation about the flipped pivot" do
      tree = el("g", %{transform: rotate(-90, 20, 30)}, el("rect", %{width: 1, height: 1}))

      assert [:save_state, matrix | _] = ops([tree])

      # The pivot is (20, 30) in SVG, so (20, 70) on the page. A rotation about
      # it is x' = -y + (px + py), y' = x + (py - px).
      assert matrix == {:concat_matrix, 0.0, 1.0, -1.0, 0.0, 90.0, 50.0}
    end

    test "the pivot is the one point the matrix leaves alone" do
      assert [:save_state, {:concat_matrix, a, b, c, d, e, f} | _] =
               ops([
                 el("g", %{transform: rotate(37, 20, 30)}, el("rect", %{width: 1, height: 1}))
               ])

      assert_in_delta a * 20 + c * 70 + e, 20, 1.0e-9
      assert_in_delta b * 20 + d * 70 + f, 70, 1.0e-9
    end

    test "a positive SVG angle (clockwise on screen) turns the page anticlockwise" do
      assert [:save_state, {:concat_matrix, _, b, _, _, _, _} | _] =
               ops([el("g", %{transform: rotate(90, 0, 0)}, el("rect", %{width: 1, height: 1}))])

      # b is sin of the *negated* angle: −1, not +1.
      assert b == -1.0
    end

    test "translate moves right and, because of the flip, down" do
      assert [:save_state, matrix | _] =
               ops([el("g", %{transform: translate(5, 7)}, el("rect", %{width: 1, height: 1}))])

      assert matrix == {:concat_matrix, 1, 0, 0, 1, 5, -7}
    end

    test "the transform is scoped, so it cannot leak into a sibling" do
      tree = [
        el("g", %{transform: translate(5, 7)}, el("rect", %{width: 1, height: 1})),
        el("rect", %{x: 0, y: 0, width: 1, height: 1})
      ]

      ops = ops(tree)
      assert :save_state in ops
      assert :restore_state in ops
      assert Enum.find_index(ops, &(&1 == :restore_state)) < length(ops) - 1
    end
  end

  describe "shapes" do
    test "a circle is four Béziers, the first control point straight up" do
      [_, _ | path] = ops([el("circle", %{cx: 50, cy: 50, r: 10, fill: "#000"})])

      assert [{:move_to, {60, 50}}, {:curve_to, {60, c}, _, {50, 60}} | _] = path
      assert_in_delta c, 50 + 10 * 0.5523, 1.0e-9
    end

    test "rx turns a rectangle into a rounded path" do
      ops = ops([el("rect", %{x: 0, y: 0, width: 20, height: 20, rx: 4, fill: "#000"})])

      refute Enum.any?(ops, &match?({:rectangle, _, _, _, _}, &1))
      assert Enum.count(ops, &match?({:curve_to, _, _, _}, &1)) == 4
      assert :close_path in ops
    end

    test "a corner radius is clamped to half the shorter side" do
      ops = ops([el("rect", %{x: 0, y: 0, width: 10, height: 4, rx: 50, fill: "#000"})])

      # r = 2, so the bottom run starts and ends at the same x and the two
      # straight edges collapse.
      assert {:move_to, {2.0, 96}} = Enum.find(ops, &match?({:move_to, _}, &1))
    end

    test "polygon points are flipped and closed" do
      ops = ops([el("polygon", %{points: points([{0, 0}, {10, 0}, {10, 10}]), fill: "#000"})])

      assert [{:move_to, {0, 100}}, {:line_to, {10, 100}}, {:line_to, {10, 90}}, :close_path] =
               Enum.filter(
                 ops,
                 &(&1 == :close_path or (is_tuple(&1) and elem(&1, 0) in ~w(move_to line_to)a))
               )
    end
  end

  describe "path data" do
    test "relative and shorthand commands track the current point" do
      d = [move(10, 10), hline(30), vline(40), rmove(5, 5), line(0, 0), close()]

      assert [
               {:move_to, {10, 90}},
               {:line_to, {30, 90}},
               {:line_to, {30, 60}},
               {:move_to, {35, 55}},
               {:line_to, {0, 100}},
               :close_path
             ] = drawing(ops([el("path", %{d: d, fill: "none", stroke: "#000"})]))
    end

    test "close returns the current point to the start of the subpath" do
      d = [move(10, 10), line(20, 20), close(), line(30, 30)]

      assert [_, _, :close_path, {:line_to, {30, 70}}] =
               drawing(ops([el("path", %{d: d, fill: "none", stroke: "#000"})]))
    end

    test "an arc becomes curve_to operations" do
      d = [move(50, 50), arc(10, 10, 0, 0, 1, 60, 60), close()]
      ops = drawing(ops([el("path", %{d: d, fill: "#000"})]))

      # The arc's own endpoint, flipped: (60, 60) in SVG is (60, 40) on the page.
      assert [{:move_to, {50, 50}}, {:curve_to, _, _, {60.0, 40.0}}, :close_path] = ops
    end
  end

  describe "paint" do
    test "fill and stroke on one shape draw the path once" do
      ops = ops([el("rect", %{width: 10, height: 10, fill: "#ff0000", stroke: "#0000ff"})])

      assert {:set_non_stroking_rgb, 1.0, 0.0, 0.0} in ops
      assert {:set_stroking_rgb, 0.0, 0.0, 1.0} in ops
      assert :fill_stroke in ops
      assert Enum.count(ops, &match?({:rectangle, _, _, _, _}, &1)) == 1
    end

    test "fill: none leaves only the stroke" do
      ops = ops([el("rect", %{width: 10, height: 10, fill: "none", stroke: "#000"})])

      assert :stroke in ops
      refute Enum.any?(ops, &match?({:set_non_stroking_rgb, _, _, _}, &1))
    end

    test "a shape with neither fill nor stroke emits nothing" do
      assert ops([el("rect", %{width: 10, height: 10, fill: "none"})]) == []
    end

    test "a zero stroke width is not a stroke" do
      ops = ops([el("line", %{x1: 0, y1: 0, x2: 1, y2: 1, stroke: "#000", stroke_width: 0})])
      assert ops == []
    end

    test "state is emitted only when it changes" do
      rect = el("rect", %{width: 10, height: 10, fill: "#000"})
      ops = ops([rect, rect, rect])

      assert Enum.count(ops, &match?({:set_non_stroking_rgb, _, _, _}, &1)) == 1
      assert Enum.count(ops, &match?({:rectangle, _, _, _, _}, &1)) == 3
    end

    test "group opacity multiplies into every descendant" do
      tree =
        el("g", %{opacity: 0.5}, [
          el("rect", %{width: 1, height: 1, fill: "#000", fill_opacity: 0.5})
        ])

      ops = ops([tree])

      assert [:save_state, {:set_opacity, 0.5} | _] = ops
      assert {:set_opacity, 0.25} in ops
      assert List.last(ops) == :restore_state
    end

    test "stroke-dasharray, linecap and linejoin map to their PDF operators" do
      tree =
        el("path", %{
          d: [move(0, 0), line(1, 1)],
          fill: "none",
          stroke: "#000",
          stroke_dasharray: 3,
          stroke_linecap: :round,
          stroke_linejoin: "bevel"
        })

      ops = ops([tree])

      assert {:set_dash, [3], 0} in ops
      assert {:set_line_cap, 1} in ops
      assert {:set_line_join, 2} in ops
    end

    test "a gradient fill degrades to its first stop" do
      tree = [
        el("defs", %{}, [
          el("linearGradient", %{id: "g1"}, [
            el("stop", %{offset: "0%", stop_color: "#ff0000", stop_opacity: 0.5}),
            el("stop", %{offset: "100%", stop_color: "#0000ff"})
          ])
        ]),
        el("rect", %{width: 10, height: 10, fill: "url(#g1)"})
      ]

      ops = ops(tree)

      assert {:set_non_stroking_rgb, 1.0, 0.0, 0.0} in ops
      assert {:set_opacity, 0.5} in ops
    end

    test "an unknown gradient reference is not painted" do
      assert ops([el("rect", %{width: 10, height: 10, fill: "url(#missing)"})]) == []
    end
  end

  describe "text" do
    test "a start-anchored label sits on its own x, baseline flipped" do
      assert [_, _, _, {:text_at, {10, 80}, "Hi"}] =
               ops([el("text", %{x: 10, y: 20, font_size: 10, fill: "#000"}, "Hi")])
    end

    test "middle and end anchors shift left by the measured width" do
      label = "Wed"
      width = EexCharts.Layout.text_width(label, 10, :arial)

      [{:text_at, {mid, _}, _}] = text_ops(label, text_anchor: "middle")
      [{:text_at, {ends, _}, _}] = text_ops(label, text_anchor: "end")
      [{:text_at, {start, _}, _}] = text_ops(label, text_anchor: "start")

      assert start == 50
      assert_in_delta mid, 50 - width / 2, 1.0e-9
      assert_in_delta ends, 50 - width, 1.0e-9
    end

    test "dominant-baseline central lifts the baseline half an em box" do
      [{:text_at, {_, plain}, _}] = text_ops("x", [])
      [{:text_at, {_, central}, _}] = text_ops("x", dominant_baseline: "central")

      # SVG's y grows downwards, so moving the baseline down moves it down the
      # page too: 10px × (0.718 − 0.207) / 2.
      assert_in_delta plain - central, 2.555, 1.0e-9
    end

    test "font-weight picks the bold base-14 face" do
      assert {:set_font, "Helvetica", 10} in ops_for_text(font_weight: 400)
      assert {:set_font, "Helvetica-Bold", 10} in ops_for_text(font_weight: 600)
      assert {:set_font, "Helvetica-Bold", 10} in ops_for_text(font_weight: "bold")
    end

    test "the font size scales with the chart" do
      ops =
        el("svg", %{viewBox: "0 0 100 100"}, el("text", %{x: 0, y: 0, font_size: 10}, "x"))
        |> Ops.build(0, 0, 2)

      assert {:set_font, "Helvetica", 20} in ops
    end

    test "escaped content is unescaped for the content stream" do
      assert [{:text_at, _, ~s(a & b < c > "d" 'e')}] =
               text_ops(EexCharts.SVG.esc(~s(a & b < c > "d" 'e')), [])
    end

    test "tspans step down by their dy and re-anchor on their own x" do
      tree =
        el("text", %{x: 10, y: 20, font_size: 10, fill: "#000"}, [
          el("tspan", %{x: 10}, "one"),
          el("tspan", %{x: 10, dy: "1.2em"}, "two")
        ])

      assert [{:text_at, {10, 80}, "one"}, {:text_at, {10, 68.0}, "two"}] =
               Enum.filter(ops([tree]), &match?({:text_at, _, _}, &1))
    end

    test "empty text draws nothing" do
      assert ops([el("text", %{x: 0, y: 0, fill: "#000"}, "")]) == []
    end
  end

  describe "elements with no PDF meaning" do
    test "defs, foreignObject and friends are skipped" do
      tree = [
        el("title", %{}, "a chart"),
        el("foreignObject", %{}, el("div", %{}, el("span", %{}, "legend"))),
        el("style", %{}, ".x {}")
      ]

      assert ops(tree) == []
    end
  end

  defp text_ops(content, attrs) do
    attrs = Map.merge(%{x: 50, y: 20, font_size: 10, fill: "#000"}, Map.new(attrs))

    [el("text", attrs, content)]
    |> ops()
    |> Enum.filter(&match?({:text_at, _, _}, &1))
  end

  defp ops_for_text(attrs) do
    attrs = Map.merge(%{x: 0, y: 0, font_size: 10, fill: "#000"}, Map.new(attrs))
    ops([el("text", attrs, "x")])
  end

  defp drawing(ops) do
    Enum.filter(ops, fn
      :close_path -> true
      op when is_tuple(op) -> elem(op, 0) in ~w(move_to line_to curve_to rectangle)a
      _ -> false
    end)
  end
end
