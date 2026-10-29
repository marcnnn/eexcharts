defmodule EexCharts.TrellisTest do
  use ExUnit.Case, async: true

  alias EexCharts.Renderer

  @cats ~w(Jan Feb Mar Apr May Jun)

  @six [
    %{name: "A", data: [3, 4, 8, 13, 18, 21]},
    %{name: "B", data: [10, 12, 15, 17, 21, 27]},
    %{name: "C", data: [-2, -2, 2, 7, 13, 17]},
    %{name: "D", data: [12, 13, 16, 19, 23, 28]},
    %{name: "E", data: [8, 9, 10, 12, 15, 17]},
    %{name: "F", data: [13, 14, 16, 20, 25, 90]}
  ]

  # ── helpers ────────────────────────────────────────────────────────────────

  defp tree(series, trellis, opts \\ %{}, extra \\ %{}) do
    Map.merge(
      %{
        id: "tr",
        type: Map.get(extra, :type, :line),
        series: series,
        categories: @cats,
        width: 760,
        height: 460,
        static: true,
        options: Map.put(opts, :trellis, trellis)
      },
      Map.delete(extra, :type)
    )
    |> Renderer.render()
  end

  defp all(node, pred) do
    case node do
      {:el, _tag, attrs, children} = el ->
        here = if pred.(el, attrs), do: [el], else: []
        here ++ all(children, pred)

      list when is_list(list) ->
        Enum.flat_map(list, &all(&1, pred))

      _ ->
        []
    end
  end

  defp attr(attrs, key), do: attrs[key]

  defp class?(attrs, class), do: is_binary(attrs[:class]) and attrs[:class] == class

  defp panels({:el, "svg", _attrs, children}) do
    children
    |> List.flatten()
    |> Enum.filter(&match?({:el, "svg", _, _}, &1))
  end

  defp count(node, class), do: length(all(node, fn _el, a -> class?(a, class) end))

  # Plot rectangle of a panel from its value grid lines: {x1, x2, ys}.
  defp grid(panel) do
    lines = all(panel, fn _el, a -> class?(a, "eexcharts-grid-line") end)
    {:el, _, a, _} = hd(lines)
    ys = Enum.map(lines, fn {:el, _, a, _} -> a.y1 end)
    {a.x1, a.x2, ys}
  end

  defp texts(panel, class) do
    panel
    |> all(fn _el, a -> class?(a, class) end)
    |> Enum.map(fn {:el, _, _, children} -> children |> List.wrap() |> to_text() end)
  end

  defp to_text(iodata) do
    iodata
    |> Enum.map(fn
      {:el, _, _, c} -> to_text(List.wrap(c))
      other -> other
    end)
    |> IO.iodata_to_binary()
  end

  defp ids(node) do
    for {:el, _, a, _} <- all(node, fn _el, a -> is_binary(attr(a, :id)) end), do: a.id
  end

  # ── invariants ────────────────────────────────────────────────────────────

  test "one panel per series, one per group" do
    assert length(panels(tree(@six, %{by: :series, columns: 3}))) == 6

    grouped =
      Enum.with_index(@six, fn s, i -> Map.put(s, :group, "g#{rem(i, 4)}") end)

    assert length(panels(tree(grouped, %{by: :group}))) == 4
  end

  test "panels tile the canvas without overlapping" do
    for cols <- [1, 2, 3, 4, 6] do
      boxes =
        for {:el, "svg", a, _} <- panels(tree(@six, %{columns: cols})),
            do: {a.x, a.y, a.x + a.width, a.y + a.height}

      for {x1, y1, x2, y2} <- boxes do
        assert x1 >= 0 and y1 >= 0 and x2 <= 760 + 1.0e-6 and y2 <= 460 + 1.0e-6
        assert x2 > x1 and y2 > y1
      end

      for {b1, i} <- Enum.with_index(boxes), {b2, j} <- Enum.with_index(boxes), i < j do
        {ax1, ay1, ax2, ay2} = b1
        {bx1, by1, bx2, by2} = b2
        overlap_x = min(ax2, bx2) - max(ax1, bx1)
        overlap_y = min(ay2, by2) - max(ay1, by1)
        refute overlap_x > 1.0e-6 and overlap_y > 1.0e-6, "panels #{i} and #{j} overlap"
      end
    end
  end

  test "shared y: every panel draws identical tick values covering all data" do
    # One column: every panel is a left-edge panel and shows its labels.
    ps = panels(tree(@six, %{columns: 1}, %{}, %{height: 1200}))
    labels = Enum.map(ps, &texts(&1, "eexcharts-yaxis-label"))
    assert labels |> Enum.uniq() |> length() == 1
    values = hd(labels) |> Enum.map(&String.to_integer/1)
    assert Enum.min(values) <= -2 and Enum.max(values) >= 90

    # In a grid the inner panels draw the same grid-line pattern.
    ps = panels(tree(@six, %{columns: 3}))

    patterns =
      Enum.map(ps, fn p ->
        {_x1, _x2, ys} = grid(p)
        [y0 | _] = ys
        Enum.map(ys, &Float.round((&1 - y0) * 1.0, 6))
      end)

    assert length(Enum.uniq(patterns)) == 1
  end

  test "free y: panels scale to their own data" do
    ps = panels(tree(@six, %{columns: 1, shared_y: false}, %{}, %{height: 1200}))
    labels = Enum.map(ps, &texts(&1, "eexcharts-yaxis-label"))
    assert labels |> Enum.uniq() |> length() > 1
  end

  test "only edge panels show axis labels and titles" do
    t =
      tree(@six, %{columns: 4}, %{
        yaxis: %{title: %{text: "Temp"}},
        xaxis: %{title: %{text: "Month"}}
      })

    # 4 columns, 6 panels: panels 2 and 3 have nothing below them.
    for {p, k} <- Enum.with_index(panels(t)) do
      left? = rem(k, 4) == 0
      bottom? = k + 4 >= 6
      assert count(p, "eexcharts-yaxis-label") > 0 == left?, "panel #{k} y labels"
      assert count(p, "eexcharts-xaxis-label") > 0 == bottom?, "panel #{k} x labels"
    end
  end

  test "plot areas line up by column and by row and have equal size" do
    ps = panels(tree(@six, %{columns: 3}))

    rects =
      Enum.map(ps, fn {:el, "svg", a, _} = p ->
        {x1, x2, ys} = grid(p)
        {a.x + x1, a.x + x2, a.y + Enum.min(ys), a.y + Enum.max(ys)}
      end)

    widths = Enum.map(rects, fn {x1, x2, _, _} -> x2 - x1 end)
    heights = Enum.map(rects, fn {_, _, y1, y2} -> y2 - y1 end)
    assert Enum.max(widths) - Enum.min(widths) < 0.01
    assert Enum.max(heights) - Enum.min(heights) < 0.01

    for c <- 0..2 do
      col = rects |> Enum.drop(c) |> Enum.take_every(3)

      assert col |> Enum.map(&elem(&1, 0)) |> Enum.uniq_by(&Float.round(&1 * 1.0, 4)) |> length() ==
               1
    end

    for r <- 0..1 do
      row = rects |> Enum.drop(r * 3) |> Enum.take(3)

      assert row |> Enum.map(&elem(&1, 3)) |> Enum.uniq_by(&Float.round(&1 * 1.0, 4)) |> length() ==
               1
    end
  end

  test "ids are unique, statically and in LiveView markup" do
    assert ids(tree(@six, %{columns: 3})) |> then(&(&1 == Enum.uniq(&1)))

    live = tree(@six, %{columns: 3}, %{}, %{static: false})
    live_ids = ids(live)
    assert live_ids == Enum.uniq(live_ids)
    # Every panel is its own hooked container with its own tooltips.
    hooked = all(live, fn _el, a -> a[:"phx-hook"] == "EexCharts" end)
    assert length(hooked) == 6
    assert Enum.all?(hooked, fn {:el, _, a, _} -> a.id =~ ~r/^tr-p\d$/ end)
    for h <- hooked, do: assert(count(h, "eexcharts-tip") == length(@cats))
  end

  test "untitled panels reserve no title band" do
    titled = tree(@six, %{columns: 3})
    untitled = tree(@six, %{columns: 3, title: %{show: false}})
    assert count(titled, "eexcharts-title") == 6
    assert count(untitled, "eexcharts-title") == 0

    top = fn t -> t |> panels() |> hd() |> grid() |> elem(2) |> Enum.min() end
    assert top.(untitled) < top.(titled) - 10
  end

  test "group legend lists each name once, keeps colors, hides by name" do
    series = [
      %{name: "Web", group: "N", data: [1, 2, 3]},
      %{name: "Shop", group: "N", data: [2, 3, 4]},
      %{name: "Web", group: "S", data: [3, 4, 5]},
      %{name: "Shop", group: "S", data: [4, 5, 6]}
    ]

    t = tree(series, %{by: :group})
    assert texts(t, "eexcharts-legend-text") == ["Web", "Shop"]

    hidden = tree(series, %{by: :group}, %{}, %{hidden_series: [0]})
    for p <- panels(hidden), do: assert(count(p, "eexcharts-series") == 1)
  end

  test "works through EexCharts.to_svg/4 and render/4" do
    svg =
      EexCharts.to_svg("x", :bar, @six,
        categories: @cats,
        options: %{trellis: %{columns: 2}, plot_options: %{bar: %{horizontal: true}}}
      )

    assert svg =~ ~r/^<svg /
    refute svg =~ "NaN"
    refute svg =~ "Infinity"
    refute svg =~ "phx-"
    assert length(Regex.scan(~r/<svg /, svg)) == 7

    {:safe, io} =
      EexCharts.render("x", :scatter, [%{name: "s", data: [[1, 2], [3, 4]]}],
        options: %{trellis: %{}}
      )

    assert IO.iodata_to_binary(io) =~ ~s(id="x-p0")
  end

  test "rejects types without a cartesian panel" do
    assert_raise ArgumentError, fn -> tree(@six, %{}, %{}, %{type: :pie}) end
  end
end
