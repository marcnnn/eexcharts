defmodule EexCharts.HierarchyTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, Hierarchy, Renderer}
  alias EexCharts.Charts.{Sunburst, Treemap}

  defp render(params) do
    params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()
  end

  defp budget do
    Dev.ChartExamples.all() |> Enum.find(&(&1.id == "hi1")) |> Map.fetch!(:series)
  end

  defp disk do
    Dev.ChartExamples.all() |> Enum.find(&(&1.id == "hi2")) |> Map.fetch!(:series)
  end

  defp close?(a, b), do: abs(a - b) < 1.0e-6

  describe "Hierarchy.nodes/3" do
    test "parents sum their children and ignore their own y" do
      [a, b] =
        Hierarchy.nodes(
          [%{x: "A", y: 999, children: [%{x: "a1", y: 1}, {"a2", 3}]}, %{x: "B", y: 4}],
          &abs/1
        )

      assert a.value == 4
      assert Enum.map(a.children, & &1.label) == ["a1", "a2"]
      assert b.value == 4 and b.children == []
      assert Hierarchy.depth([a, b]) == 2
    end

    test "nested? only for points with a non-empty children list" do
      refute Hierarchy.nested?([%{data: [%{x: "a", y: 1, children: []}]}])
      assert Hierarchy.nested?([%{data: [%{x: "a", children: [%{x: "b", y: 1}]}]}])
    end
  end

  describe "sunburst geometry" do
    setup do
      cfg = Config.build(:sunburst, %{})

      roots =
        Sunburst.roots(%{
          series: [
            %{data: [%{x: "A", children: [%{x: "a1", y: 1}, %{x: "a2", y: 3}]}, %{x: "B", y: 4}]}
          ]
        })

      %{cfg: cfg, geo: Sunburst.geometry(cfg, roots, 400, 400)}
    end

    test "worked example: angles and radii", %{geo: geo} do
      by_key = Map.new(geo.arcs, &{&1.key, &1})

      # total 8: A = 4/8 of 360, B the other half; a1:a2 = 1:3 of A's 180.
      assert close?(by_key["0"].start, 0) and close?(by_key["0"].angle, 180)
      assert close?(by_key["1"].start, 180) and close?(by_key["1"].angle, 180)
      assert close?(by_key["0-0"].start, 0) and close?(by_key["0-0"].angle, 45)
      assert close?(by_key["0-1"].start, 45) and close?(by_key["0-1"].angle, 135)

      # outer radius = 400 / 2.05 - stroke(1); hole 25%; two equal rings.
      r = 400 / 2.05 - 1
      assert close?(geo.r, r)
      assert close?(by_key["0"].r_in, r * 0.25)
      assert close?(by_key["0"].r_out, r * 0.25 + r * 0.75 / 2)
      assert close?(by_key["0-0"].r_out, r)
      assert {geo.cx, geo.cy} == {200.0, 200.0}
    end

    test "each ring's angles tile its parent's angle" do
      cfg = Config.build(:sunburst, %{})
      geo = Sunburst.geometry(cfg, Sunburst.roots(%{series: disk()}), 500, 500)
      arcs = geo.arcs

      top = Enum.filter(arcs, &(&1.depth == 0))
      assert close?(top |> Enum.map(& &1.angle) |> Enum.sum(), 360)

      for parent <- arcs,
          kids = Enum.filter(arcs, &(&1.path == parent.path ++ [List.last(&1.path)])),
          kids != [] do
        assert close?(kids |> Enum.map(& &1.angle) |> Enum.sum(), parent.angle)
        assert close?(hd(kids).start, parent.start)
        assert close?(hd(kids).r_in, parent.r_out)

        # contiguous, in order
        kids
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.each(fn [a, b] -> assert close?(a.start + a.angle, b.start) end)

        # angle proportional to value within the parent
        for k <- kids, do: assert(close?(k.angle / parent.angle, k.value / parent.value))
      end
    end

    test "labels hide in arcs too small for them", %{cfg: cfg} do
      opts = cfg.plot_options.sunburst.labels
      tiny = %{angle: 2, r_in: 50, r_out: 90, start: 0}
      wide = %{angle: 90, r_in: 50, r_out: 90, start: 0}
      deep = %{angle: 20, r_in: 50, r_out: 150, start: 0}

      assert Sunburst.label_orientation(opts, tiny, 30, 11) == nil
      assert Sunburst.label_orientation(opts, wide, 30, 11) == :tangential
      # too narrow along the ring for tangential, but long enough radially
      assert Sunburst.label_orientation(opts, deep, 60, 11) == :radial
      assert Sunburst.label_orientation(%{opts | orientation: :tangential}, deep, 60, 11) == nil
    end
  end

  describe "sunburst rendering" do
    test "one arc per node, tooltips with path and share, legend per branch" do
      html = render(%{id: "sb", type: :sunburst, series: budget()})

      # 5 top-level + 12 children
      assert length(Regex.scan(~r/class="eexcharts-sunburst-arc"/, html)) == 5 + 12
      assert html =~ "Engineering / Platform"
      assert html =~ "Share of parent"
      assert html =~ "eexcharts-legend-item"
      assert html =~ ~s(data-j="0-1")
      refute html =~ ~r/NaN|Infinity/
    end

    test "hidden branches are removed from the rings" do
      html = render(%{id: "sb", type: :sunburst, series: budget(), hidden_series: [0]})

      refute html =~ ~s(class="eexcharts-sunburst-arc" data-j="0")
      refute html =~ ~r/data-j="0-\d"/
      assert html =~ ~s(data-j="1-0")
    end

    test "on_click puts path, name, depth and branch on every arc" do
      html = render(%{id: "sb", type: :sunburst, series: budget(), on_click: "pick"})

      assert html =~ ~s(phx-click="pick")
      assert html =~ ~s(phx-value-path="1-2")
      assert html =~ ~s(phx-value-name="APAC")
      assert html =~ ~s(phx-value-depth="1")
    end

    test "several series become one branch each" do
      roots =
        Sunburst.roots(%{
          series: [%{name: "X", data: [1, 2]}, %{name: "Y", data: [%{x: "y", y: 3}]}]
        })

      assert Enum.map(roots, &{&1.label, &1.value}) == [{"X", 3}, {"Y", 3}]
    end

    test "a single root draws a full ring" do
      html = render(%{id: "sb", type: :sunburst, series: [%{data: [%{x: "only", y: 5}]}]})
      refute html =~ ~r/NaN|Infinity/
      assert html =~ "eexcharts-sunburst-arc"
    end
  end

  describe "nested treemap layout" do
    defp nodes(data), do: Hierarchy.nodes(data, &abs/1)

    defp area(r), do: r.w * r.h

    defp inside?(r, {x, y, w, h}) do
      eps = 1.0e-6
      r.x >= x - eps and r.y >= y - eps and r.x + r.w <= x + w + eps and r.y + r.h <= y + h + eps
    end

    defp overlap?(a, b) do
      eps = 1.0e-6

      a.x + a.w > b.x + eps and b.x + b.w > a.x + eps and a.y + a.h > b.y + eps and
        b.y + b.h > a.y + eps
    end

    test "worked example without padding or headers" do
      items =
        nodes([%{x: "A", children: [%{x: "a1", y: 1}, %{x: "a2", y: 1}]}, %{x: "B", y: 2}])
        |> Treemap.layout_nested({0, 0, 100, 100}, %{padding: 0, header_h: 0})

      [a, a1, a2, b] = items
      assert {a.kind, a1.kind, b.kind} == {:group, :leaf, :leaf}
      assert close?(area(a), 5000) and close?(area(b), 5000)
      assert close?(area(a1), 2500) and close?(area(a2), 2500)
      assert a.inner == {a.x, a.y, a.w, a.h}
    end

    test "header band and padding shrink the inner rect" do
      [g | _] =
        nodes([%{x: "A", children: [%{x: "a1", y: 1}]}])
        |> Treemap.layout_nested({10, 20, 200, 100}, %{padding: 3, header_h: 18})

      assert g.header_h == 18
      assert g.inner == {13, 38, 194, 79}
    end

    test "children are contained, proportional and non-overlapping at every level" do
      [%{data: data}] = disk()

      items =
        data
        |> nodes()
        |> Treemap.layout_nested({0, 0, 600, 420}, %{padding: 3, header_h: 18})

      levels = Enum.group_by(items, &Enum.drop(&1.path, -1))

      for {parent_path, kids} <- levels do
        box =
          case Enum.find(items, &(&1.path == parent_path)) do
            nil -> {0, 0, 600, 420}
            parent -> parent.inner
          end

        {_, _, bw, bh} = box
        total = kids |> Enum.map(& &1.value) |> Enum.sum()

        for k <- kids do
          assert inside?(k, box)
          assert close?(area(k), bw * bh * k.value / total)
        end

        for a <- kids, b <- kids, a.path < b.path, do: refute(overlap?(a, b))
      end
    end
  end

  describe "nested treemap rendering" do
    test "groups get a frame and header, leaves keep composite keys" do
      html = render(%{id: "tm", type: :treemap, series: budget()})

      assert length(Regex.scan(~r/class="eexcharts-treemap-group"/, html)) == 4
      assert html =~ ~s(class="eexcharts-treemap-header")
      assert html =~ "Engineering"
      assert html =~ ~s(data-j="0-0-1")
      assert html =~ "Sales / Americas"
      refute html =~ ~r/NaN|Infinity/
    end

    test "flat data takes the unchanged flat path" do
      html =
        render(%{id: "tm", type: :treemap, series: [%{name: "S", data: [%{x: "a", y: 1}]}]})

      refute html =~ "eexcharts-treemap-group"
      refute html =~ "Share of"
    end
  end
end
