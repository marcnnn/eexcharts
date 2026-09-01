defmodule EexCharts.SVGTest do
  @moduledoc """
  The element tree and its serializer.

  Chart code builds `{:el, tag, attrs, children}` nodes with raw values and
  path data as command tuples; `to_iodata/1` is the only place that turns any
  of it into bytes. These tests pin that byte contract, because a second
  backend (PDF) reads the tree instead — so the tree and the string must stay
  in step.
  """
  use ExUnit.Case, async: true

  import EexCharts.SVG

  alias EexCharts.SVG

  defp render(node), do: node |> SVG.to_iodata() |> IO.iodata_to_binary()

  describe "el/3" do
    test "builds a tagged tuple and keeps attribute values raw" do
      assert el("rect", %{x: 1.5, width: 10}) == {:el, "rect", %{x: 1.5, width: 10}, nil}
    end

    test "a nil child is a void element" do
      assert render(el("rect", %{x: 1})) == ~s(<rect x="1"/>)
    end

    test "children serialize between the tags" do
      assert render(el("text", %{}, "hi")) == "<text>hi</text>"
    end

    test "children may be nested lists, nodes and iodata" do
      tree = el("g", %{}, [[el("line", %{x1: 0})], ["a", ["b"]], []])
      assert render(tree) == ~s(<g><line x1="0"/>ab</g>)
    end

    test "a bare list of nodes serializes in order" do
      assert render([el("a", %{}, "1"), el("b", %{}, "2")]) == "<a>1</a><b>2</b>"
    end
  end

  describe "attributes" do
    test "nil and false attributes are dropped" do
      assert render(el("rect", %{x: 1, y: nil, hidden: false})) == ~s(<rect x="1"/>)
    end

    test "true renders as an empty value" do
      assert render(el("div", %{hidden: true})) == ~s(<div hidden=""/>)
    end

    test "underscores in atom keys become dashes" do
      assert render(el("text", %{font_size: 12})) == ~s(<text font-size="12"/>)
    end

    test "string keys pass through verbatim" do
      assert render(el("rect", %{"phx-click" => "pick"})) == ~s(<rect phx-click="pick"/>)
    end

    test "map attributes are sorted by name, keyword lists keep their order" do
      assert render(el("rect", %{z: 1, a: 2})) == ~s(<rect a="2" z="1"/>)
      assert render(el("rect", z: 1, a: 2)) == ~s(<rect z="1" a="2"/>)
    end

    test "numbers are formatted, not stringified early" do
      assert render(el("rect", %{x: 2.0, y: 0.1 + 0.2})) ==
               ~s(<rect x="2" y="0.30000000000000004"/>)
    end

    test "values are escaped" do
      assert render(el("text", %{title: ~s(a "b" <c>)})) ==
               ~s(<text title="a &quot;b&quot; &lt;c&gt;"/>)
    end
  end

  describe "path commands" do
    test "each command renders with its SVG letter" do
      d = [
        move(1, 2),
        line(3, 4),
        hline(5),
        vline(6),
        curve(1, 2, 3, 4, 5, 6),
        arc(7, 7, 0, 1, 0, 8, 9),
        rmove(-3, 0),
        close()
      ]

      assert render(el("path", %{d: d})) ==
               ~s(<path d="M 1 2 L 3 4 H 5 V 6 C 1 2 3 4 5 6 A 7 7 0 1 0 8 9 m -3 0 Z"/>)
    end

    test "commands are separated by exactly one space, nesting and gaps drop out" do
      # `[]` is what a chart's `if(radius > 0, do: arc(...), else: [])` yields.
      d = [move(0, 0), [[line(1, 1)], []], [], close()]
      assert render(el("path", %{d: d})) == ~s(<path d="M 0 0 L 1 1 Z"/>)
    end

    test "a mid-path move starts a new subpath" do
      d = [move(0, 0), line(1, 0), move(0, 1), line(1, 1)]
      assert render(el("path", %{d: d})) == ~s(<path d="M 0 0 L 1 0 M 0 1 L 1 1"/>)
    end

    test "an attribute holding plain iodata is not mistaken for a path" do
      assert render(el("div", %{class: ["a", [" ", "b"]]})) == ~s(<div class="a b"/>)
    end
  end

  describe "points/1" do
    test "renders x,y pairs space-separated" do
      assert render(el("polygon", %{points: points([{1, 2.5}, {3, 4}])})) ==
               ~s(<polygon points="1,2.5 3,4"/>)
    end
  end

  describe "transform/1" do
    test "translate keeps the comma-space separator" do
      assert render(el("g", %{transform: translate(240, 166.5)})) ==
               ~s|<g transform="translate(240, 166.5)"/>|
    end

    test "rotate renders angle then centre, space-separated" do
      assert render(el("text", %{transform: rotate(-90, 315.1773, 23)})) ==
               ~s|<text transform="rotate(-90 315.1773 23)"/>|
    end

    test "the attribute stays structured on the node" do
      assert el("g", %{transform: translate(1, 2)}) ==
               {:el, "g", %{transform: {:translate, 1, 2}}, nil}
    end
  end

  describe "drop_attrs/2" do
    test "removes the named attributes throughout the tree" do
      tree = el("g", %{data_j: 1}, [el("rect", %{data_cx: 2, x: 3}), el("circle", data_cy: 4)])

      assert render(SVG.drop_attrs(tree, ~w(data-j data-cx data-cy))) ==
               ~s(<g><rect x="3"/><circle/></g>)
    end
  end

  describe "fmt/1" do
    test "emits the shortest round-tripping representation" do
      assert fmt(3) == "3"
      assert fmt(3.0) == "3"
      assert fmt(263.4949645996094) == "263.4949645996094"
    end
  end
end
