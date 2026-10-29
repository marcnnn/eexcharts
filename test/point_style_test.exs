defmodule EexCharts.PointStyleTest do
  use ExUnit.Case, async: true

  alias EexCharts.{Config, PointStyle, Renderer}

  defp live(type, series, opts \\ []) do
    {:safe, io} = EexCharts.render("ps", type, series, opts)
    IO.iodata_to_binary(io)
  end

  defp static(type, series, opts), do: EexCharts.to_svg("ps", type, series, opts)

  defp tags(svg, tag), do: Regex.scan(~r/<#{tag}\b[^>]*>/, svg) |> List.flatten()

  defp styled(svg), do: svg |> tags("path") |> Enum.filter(&(&1 =~ "eexcharts-point-styled"))

  describe "resolve/4" do
    setup do: %{cfg: Config.build(:bar), s: %{index: 0}}

    test "without overrides it paints the base colour with the chart's fill", %{cfg: cfg, s: s} do
      assert PointStyle.resolve(cfg, s, 12, "#008FFB") == %{
               fill: "#008FFB",
               fill_opacity: 0.85,
               stroke: nil,
               stroke_width: 0,
               class: nil
             }
    end

    test "point colours beat series fill, which beats the global fill", %{cfg: cfg} do
      s = %{index: 0, fill: %{opacity: 0.4}}
      style = PointStyle.resolve(cfg, s, %{y: 1, fill_color: "#123456"}, "#008FFB")

      assert %{fill: "#123456", fill_opacity: 0.4, class: "eexcharts-point-styled"} = style

      point = %{y: 1, fill: %{opacity: 0.2}}
      assert PointStyle.resolve(cfg, s, point, "#008FFB").fill_opacity == 0.2
    end

    test "a stroke_color on a strokeless bar gets a visible width", %{cfg: cfg, s: s} do
      assert %{stroke: "#111111", stroke_width: 2} =
               PointStyle.resolve(cfg, s, %{y: 1, stroke_color: "#111111"}, "#008FFB")
    end

    test "fill type :none is outline-only in the mark colour", %{cfg: cfg} do
      s = %{index: 0, fill: %{type: :none}}

      assert %{fill: "none", stroke: "var(--color-primary, #008FFB)", stroke_width: 2} =
               PointStyle.resolve(cfg, s, 3, "var(--color-primary, #008FFB)")

      assert %{stroke: "#ff0000"} =
               PointStyle.resolve(cfg, s, %{y: 3, fill_color: "#ff0000"}, "#008FFB")
    end

    test "pattern style lists are indexed by series; missing entries are solid", %{cfg: cfg} do
      cfg = put_in(cfg.fill, %{type: :pattern, opacity: 1, pattern: %{style: [:circles]}})

      assert %{fill: {:pattern, %{style: :circles, color: "#abc", width: 6, height: 6}}} =
               PointStyle.resolve(cfg, %{index: 0}, 1, "#abc")

      cfg = put_in(cfg.fill.pattern.style, [:circles, nil])
      assert %{fill: "#abc"} = PointStyle.resolve(cfg, %{index: 1}, 1, "#abc")
    end
  end

  describe "link/2" do
    test "one <pattern> per distinct style, colour and size" do
      cfg = Config.build(:bar, %{fill: %{type: :pattern}})
      a = %{style: PointStyle.resolve(cfg, %{index: 0}, 1, "#111111")}
      b = %{style: PointStyle.resolve(cfg, %{index: 0}, 1, "#222222")}

      {[a1, b1, a2], defs} = PointStyle.link([a, b, a], "c")
      svg = defs |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()

      assert a1.style.fill == "url(#c-pattern-0)"
      assert b1.style.fill == "url(#c-pattern-1)"
      assert a2.style.fill == a1.style.fill
      assert length(tags(svg, "pattern")) == 2
      refute svg =~ "<rect x=\"0\" y=\"0\" width=\"6\" height=\"6\" fill=\"#fff"
    end

    test "nothing patterned emits no defs" do
      assert {[], []} = PointStyle.link([], "c")
    end
  end

  describe "bars" do
    test "an outline series next to a solid one" do
      svg =
        live(:bar, [
          %{name: "A", data: [3, 5]},
          %{name: "B", data: [4, 2], fill: %{type: :none}}
        ])

      [b1, _] = styled(svg)
      assert b1 =~ ~s(fill="none")
      assert b1 =~ ~s(stroke="#00E396")
      assert b1 =~ ~s(stroke-width="2")
      assert length(styled(svg)) == 2
    end

    test "data labels on an outline bar take the series colour, not white" do
      svg =
        live(:bar, [%{name: "B", data: [4, 2], fill: %{type: :none}}],
          options: %{data_labels: %{enabled: true}}
        )

      labels = tags(svg, "text") |> Enum.filter(&(&1 =~ "eexcharts-datalabel"))
      assert labels != []
      assert Enum.all?(labels, &(&1 =~ ~s(fill="#008FFB")))
    end

    test "per-point fill_color on {x, y} points" do
      svg =
        live(
          :bar,
          [%{name: "A", data: [%{x: "a", y: 3}, %{x: "b", y: 5, fill_color: "#FF4560"}]}],
          categories: ["a", "b"]
        )

      assert [flagged] = styled(svg)
      assert flagged =~ ~s(fill="#FF4560")
      assert length(tags(svg, "path") |> Enum.filter(&(&1 =~ "eexcharts-bar"))) == 2
    end

    test "global pattern fill, stacked and horizontal, resolves every url()" do
      for opts <- [
            %{chart: %{stacked: true}},
            %{plot_options: %{bar: %{horizontal: true}}},
            %{plot_options: %{bar: %{distributed: true}}}
          ] do
        opts = Map.put(opts, :fill, %{type: :pattern, pattern: %{style: :slanted_lines}})
        svg = live(:bar, [%{name: "A", data: [3, 5]}, %{name: "B", data: [2, 4]}], options: opts)

        refs = Regex.scan(~r/url\(#([^)]+)\)/, svg) |> Enum.map(&List.last/1) |> Enum.uniq()
        assert refs != []
        for id <- refs, do: assert(svg =~ ~s(<pattern height="6" id="#{id}"))
      end
    end
  end

  test "range bar points: outline and pattern" do
    svg =
      live(:range_bar, [
        %{
          name: "A",
          data: [
            %{x: "a", y: [1, 3], fill: %{type: :none}},
            %{x: "b", y: [2, 5], fill: %{type: :pattern, pattern: %{style: :vertical_lines}}}
          ]
        }
      ])

    [outline, pattern] = styled(svg)
    assert outline =~ ~s(fill="none")
    assert pattern =~ ~s|fill="url(#ps-pattern-0)"|
    assert svg =~ ~s(<line stroke="#008FFB" stroke-width="3" x1="0" x2="0" y1="0" y2="6")
  end

  test "dumbbell: fill_color colours the connector and both dots" do
    svg =
      live(:dumbbell, [
        %{name: "A", data: [%{x: "a", y: [1, 3]}, %{x: "b", y: [2, 5], fill_color: "#FF4560"}]}
      ])

    [_, flagged] = Regex.scan(~r/<g class="eexcharts-bar[^"]*".*?<\/g>/, svg) |> List.flatten()
    assert flagged =~ "eexcharts-point-styled"
    assert flagged =~ ~s(stroke="#FF4560")
    assert length(Regex.scan(~r/fill="#FF4560"/, flagged)) == 2
  end

  test "waterfall bars take per-point paint" do
    svg =
      live(:waterfall, [
        %{name: "A", data: [%{x: "a", y: 3}, %{x: "b", y: -1, fill: %{type: :none}}]}
      ])

    assert [outline] = styled(svg)
    assert outline =~ "eexcharts-waterfall-decrease"
    assert outline =~ ~s(stroke="#FF4560")
  end

  test "normalize_series keeps extra series keys" do
    [s] =
      Renderer.normalize_series([%{name: "A", data: [1], fill: %{type: :none}, end_label: "x"}])

    assert %{name: "A", index: 0, fill: %{type: :none}, end_label: "x", group: nil} = s
  end

  describe "themes" do
    @series [
      %{name: "A", data: [3, 5], fill: %{type: :none}},
      %{name: "B", data: [2, 4], fill: %{type: :pattern, pattern: %{style: :circles}}}
    ]

    test "dark: outline and pattern take palette4 colours" do
      svg = static(:bar, @series, options: %{theme: %{mode: :dark}})
      [first, second | _] = Config.build(:bar, %{theme: %{mode: :dark}}).colors

      assert svg =~ ~s(fill="none")
      assert svg =~ ~s(stroke="#{first}")
      assert svg =~ ~s(<circle cx="3" cy="3" fill="none" r="3" stroke="#{second}")
    end

    test "daisy live output hands var() to fill, stroke and pattern lines" do
      svg =
        live(:bar, @series ++ [%{name: "C", data: [%{y: 1, fill_color: "var(--color-error)"}]}],
          options: %{theme: %{mode: :daisy}, data_labels: %{enabled: true}}
        )

      assert svg =~ ~s|stroke="var(--color-primary, #008FFB)"|
      assert svg =~ ~s|r="3" stroke="var(--color-secondary, #00E396)"|
      assert svg =~ ~s|fill="var(--color-error)"|
      # Labels on outline and pattern marks sit on the page: the series colour
      # or the page text colour, never an on-mark `*-content` colour.
      fills =
        tags(svg, "text")
        |> Enum.filter(&(&1 =~ "eexcharts-datalabel"))
        |> Enum.map(&(Regex.run(~r/fill="([^"]+)"/, &1) |> List.last()))
        |> Enum.uniq()

      assert "var(--color-primary, #008FFB)" in fills
      assert "var(--color-base-content, #373d3f)" in fills
      assert "var(--color-accent-content, #fff)" in fills
      assert length(fills) == 3
    end

    test "daisy static output resolves every var(), series data included" do
      series = @series ++ [%{name: "C", data: [%{y: 1, fill_color: "var(--color-error, #f00)"}]}]
      svg = static(:bar, series, options: %{theme: %{mode: :daisy}})

      refute svg =~ "var("
      assert svg =~ ~s(fill="#f00")
    end
  end
end
