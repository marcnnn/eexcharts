defmodule EexCharts.LabelsTest do
  use ExUnit.Case, async: true

  alias EexCharts.{DataLabels, Layout, Renderer, Scale}

  defp render(params),
    do: params |> Renderer.render() |> EexCharts.SVG.to_iodata() |> IO.iodata_to_binary()

  defp attr(tag, name) do
    case Regex.run(~r/ #{name}="([^"]*)"/, tag) do
      [_, v] -> v
      nil -> nil
    end
  end

  defp num(tag, name), do: tag |> attr(name) |> Float.parse() |> elem(0)

  defp tags(html, tag, class) do
    Regex.scan(~r/<#{tag} class="#{class}"[^>]*>/, html) |> Enum.map(&hd/1)
  end

  defp texts(html, class) do
    Regex.scan(~r/(<text class="#{class}"[^>]*>)([^<]*)<\/text>/, html)
    |> Enum.map(fn [_, tag, text] -> {tag, text} end)
  end

  # ── 1. annotation dash patterns and line caps ────────────────────────────

  describe "annotation stroke patterns" do
    defp anno_line(opts) do
      html =
        render(%{
          id: "a",
          type: :line,
          series: [%{name: "A", data: [1, 5, 9]}],
          options: %{annotations: %{yaxis: [Map.put(opts, :y, 5)]}}
        })

      html |> tags("line", "eexcharts-annotation-line") |> hd()
    end

    test "numbers, strings and lists become a stroke-dasharray" do
      assert attr(anno_line(%{}), "stroke-dasharray") == "1"
      assert attr(anno_line(%{stroke_dash_array: 6}), "stroke-dasharray") == "6"
      assert attr(anno_line(%{stroke_dash_array: "6 3 1 3"}), "stroke-dasharray") == "6 3 1 3"
      assert attr(anno_line(%{stroke_dash_array: "6,3"}), "stroke-dasharray") == "6 3"

      assert attr(anno_line(%{stroke_dash_array: [6, 3, 1.5, 3]}), "stroke-dasharray") ==
               "6 3 1.5 3"
    end

    test "zero, empty and invalid patterns draw solid" do
      for p <- [0, [], "", [0, 0], "6 x", [-1, 2]] do
        assert attr(anno_line(%{stroke_dash_array: p}), "stroke-dasharray") == nil
      end
    end

    test "line caps are emitted only when set" do
      assert attr(anno_line(%{}), "stroke-linecap") == nil
      assert attr(anno_line(%{stroke_linecap: :round}), "stroke-linecap") == "round"
      assert attr(anno_line(%{stroke_linecap: "square"}), "stroke-linecap") == "square"
      assert attr(anno_line(%{stroke_linecap: :bogus}), "stroke-linecap") == nil
    end

    test "x-axis lines and band borders take the pattern and cap too" do
      html =
        render(%{
          id: "a",
          type: :line,
          series: [%{name: "A", data: [1, 5, 9, 4]}],
          categories: ~w(a b c d),
          options: %{
            annotations: %{
              xaxis: [
                %{x: "b", stroke_dash_array: [4, 2], stroke_linecap: :butt},
                %{x: "c", x2: "d", stroke_dash_array: "2 2", stroke_linecap: :round}
              ]
            }
          }
        })

      [line] = tags(html, "line", "eexcharts-annotation-line")
      [rect] = tags(html, "rect", "eexcharts-annotation-rect")
      assert {attr(line, "stroke-dasharray"), attr(line, "stroke-linecap")} == {"4 2", "butt"}
      assert {attr(rect, "stroke-dasharray"), attr(rect, "stroke-linecap")} == {"2 2", "round"}
    end
  end

  # ── 2. balanced overlap hiding ───────────────────────────────────────────

  describe "data label overlap hiding" do
    defp overlap_free?(boxes) do
      pairs =
        for {a, i} <- Enum.with_index(boxes), {b, k} <- Enum.with_index(boxes), i < k, do: {a, b}

      not Enum.any?(pairs, fn {a, b} -> DataLabels.overlap?(a, b) end)
    end

    test "two fully colliding series alternate instead of one winning" do
      box = fn j -> {j * 10.0, 0.0, j * 10.0 + 15, 10.0} end
      labels = for s <- [0, 1], j <- 0..9, do: {s, box.(j), {s, j}}

      kept = DataLabels.hide_overlapping(labels)
      boxes = Enum.map(kept, fn {_s, b, _} -> b end)

      assert overlap_free?(boxes)
      counts = Enum.frequencies_by(kept, fn {s, _, _} -> s end)
      assert abs(counts[0] - counts[1]) <= 1
      # Input order is preserved.
      assert kept == Enum.filter(labels, &(&1 in kept))
    end

    test "first-wins would starve series 1; balanced hiding does not" do
      # Series 0 labels collide with every series 1 label.
      labels =
        for(j <- 0..5, do: {0, {j * 30.0, 0.0, j * 30.0 + 20, 10.0}, j}) ++
          for(j <- 0..5, do: {1, {j * 30.0 + 5, 0.0, j * 30.0 + 25, 10.0}, j})

      counts = labels |> DataLabels.hide_overlapping() |> Enum.frequencies_by(&elem(&1, 0))
      assert counts == %{0 => 3, 1 => 3}
    end

    defp crowded(type, extra) do
      render(%{
        id: "dl",
        type: type,
        width: 420,
        series: [
          %{name: "A", data: Enum.map(0..19, &(30 + rem(&1 * 7, 11)))},
          %{name: "B", data: Enum.map(0..19, &(31 + rem(&1 * 5, 9)))}
        ],
        options: Map.merge(%{data_labels: %{enabled: true, hide_overlapping: true}}, extra)
      })
    end

    test "no two visible label pills overlap on a line chart" do
      html = crowded(:line, %{})
      rects = tags(html, "rect", "eexcharts-datalabel-bg")

      boxes =
        Enum.map(rects, fn r ->
          {x, y} = {num(r, "x"), num(r, "y")}
          {x, y, x + num(r, "width"), y + num(r, "height")}
        end)

      assert length(boxes) < 40
      assert length(boxes) > 0
      assert overlap_free?(boxes)

      # Both series keep labels (pill colours are the series colours).
      fills = rects |> Enum.map(&attr(&1, "fill")) |> Enum.uniq()
      assert length(fills) == 2
    end

    test "no two visible bar labels overlap" do
      html = crowded(:bar, %{})
      labels = texts(html, "eexcharts-datalabel")

      boxes =
        Enum.map(labels, fn {tag, text} ->
          DataLabels.box(num(tag, "x"), num(tag, "y"), text, num(tag, "font-size"), :arial)
        end)

      assert length(boxes) in 1..39
      assert overlap_free?(boxes)
    end

    test "off by default: every label is drawn" do
      html = crowded(:line, %{data_labels: %{enabled: true}})
      assert length(tags(html, "rect", "eexcharts-datalabel-bg")) == 40
    end
  end

  # ── 3. horizontal bar category thinning ──────────────────────────────────

  describe "horizontal bar category labels" do
    defp hbar(n, height, extra \\ %{}) do
      render(%{
        id: "h",
        type: :bar,
        height: height,
        series: [%{name: "A", data: Enum.map(1..n, &(&1 + 3))}],
        categories: Enum.map(1..n, &"Cat #{&1}"),
        options:
          Map.merge(
            %{plot_options: %{bar: %{horizontal: true}}, data_labels: %{enabled: false}},
            extra
          )
      })
    end

    defp label_ys(html) do
      html |> texts("eexcharts-xaxis-label") |> Enum.map(fn {tag, t} -> {num(tag, "y"), t} end)
    end

    test "crowded labels are thinned to evenly spaced, non-overlapping rows" do
      labels = label_ys(hbar(48, 360))
      ys = Enum.map(labels, &elem(&1, 0))

      assert length(labels) < 48
      assert hd(labels) |> elem(1) == "Cat 1"

      gaps = ys |> Enum.chunk_every(2, 1, :discard) |> Enum.map(fn [a, b] -> b - a end)
      assert Enum.max(gaps) - Enum.min(gaps) < 1.0e-6
      assert Enum.min(gaps) >= Layout.text_height(12)

      # Every k-th category, k constant.
      idx = Enum.map(labels, fn {_, "Cat " <> i} -> String.to_integer(i) - 1 end)
      k = Enum.at(idx, 1)
      assert idx == Enum.map(0..(length(idx) - 1), &(&1 * k))
    end

    test "labels with room are all kept" do
      assert length(label_ys(hbar(6, 350))) == 6
    end

    test "hide_overlapping_labels: false keeps every label" do
      html = hbar(48, 360, %{xaxis: %{labels: %{hide_overlapping_labels: false}}})
      assert length(label_ys(html)) == 48
    end
  end

  # ── 4. per-point offset functions ────────────────────────────────────────

  describe "data label offset functions" do
    test "offset helper resolves numbers and functions" do
      assert DataLabels.offset(3, 10, 0, 0) == 3
      assert DataLabels.offset(fn v -> v * 2 end, 10, 0, 0) == 20

      assert DataLabels.offset(
               fn _v, %{series_index: i, data_point_index: j} -> i * 10 + j end,
               0,
               2,
               5
             ) ==
               25

      assert DataLabels.offset(fn _ -> :nope end, 1, 0, 0) == 0
    end

    test "a point label moves by the function's per-point result" do
      base = %{id: "o", type: :line, series: [%{name: "A", data: [5, 5, 5]}]}
      plain = render(Map.put(base, :options, %{data_labels: %{enabled: true}}))

      moved =
        render(
          Map.put(base, :options, %{
            data_labels: %{
              enabled: true,
              offset_y: fn _v, %{data_point_index: j} -> j * 10 end,
              offset_x: fn v -> -v end
            }
          })
        )

      pos = fn html ->
        html
        |> texts("eexcharts-datalabel")
        |> Enum.map(fn {t, _} -> {num(t, "x"), num(t, "y")} end)
      end

      for {{x0, y0}, {x1, y1}, j} <- Enum.zip([pos.(plain), pos.(moved), 0..2]) do
        assert_in_delta x1 - x0, -5, 1.0e-6
        assert_in_delta y1 - y0, j * 10, 1.0e-6
      end
    end

    test "bar labels get value and indexes" do
      html =
        render(%{
          id: "o",
          type: :bar,
          series: [%{name: "A", data: [4, -4]}],
          options: %{
            data_labels: %{enabled: true, offset_y: fn v, _ -> if v < 0, do: 100, else: 0 end}
          }
        })

      [{a, _}, {b, _}] = texts(html, "eexcharts-datalabel")
      assert num(b, "y") - num(a, "y") > 100
    end

    test "heatmap labels accept offset functions" do
      html =
        render(%{
          id: "hm",
          type: :heatmap,
          series: [%{name: "A", data: [1, 2]}],
          options: %{
            data_labels: %{enabled: true, offset_x: fn _v, %{data_point_index: j} -> j end}
          }
        })

      assert html =~ "eexcharts-datalabel"
    end
  end

  # ── 5. logarithmic axes below the base ───────────────────────────────────

  describe "logarithmic y-axis with values below 1" do
    defp power_of?(t, base) do
      e = :math.log(t) / :math.log(base)
      abs(e - round(e)) < 1.0e-9
    end

    test "sub-unit ticks are whole powers of the base" do
      s = Scale.log_scale(0.004, 90, 10, false)
      assert s.log
      assert s.ticks == [0.001, 0.01, 0.1, 1, 10, 100]

      for base <- [2, 10], {mn, mx} <- [{0.004, 90}, {0.3, 0.8}, {0.02, 3}] do
        s = Scale.log_scale(mn, mx, base, false)
        assert s.log
        below = Enum.filter(s.ticks, &(&1 < 1))
        assert below != []
        assert Enum.all?(s.ticks, &power_of?(&1, base))
        assert s.nice_min <= mn and s.nice_max >= mx
      end
    end

    test "small ranges at or above 1 still fall back to linear" do
      refute Scale.log_scale(1, 4, 10, false).log
    end

    test "rendered line chart plots sub-unit values inside the plot" do
      html =
        render(%{
          id: "lg",
          type: :line,
          series: [%{name: "A", data: [0.002, 0.05, 3, 40]}],
          options: %{yaxis: %{logarithmic: true}}
        })

      labels = html |> texts("eexcharts-yaxis-label") |> Enum.map(&elem(&1, 1))
      assert "0.001" in labels and "0.01" in labels and "0.1" in labels
    end

    test "bar chart on a log axis starts at the smallest positive decade" do
      html =
        render(%{
          id: "lgb",
          type: :bar,
          series: [%{name: "A", data: [0.05, 2, 300]}],
          options: %{yaxis: %{logarithmic: true}, data_labels: %{enabled: false}}
        })

      labels = html |> texts("eexcharts-yaxis-label") |> Enum.map(&elem(&1, 1))
      assert hd(labels) == "0.01"
      # Every bar has a positive height (none collapsed onto a clamped floor).
      # Bars share the plot floor and their tops follow the values' decades.
      bars =
        Regex.scan(~r/class="eexcharts-bar" d="M [\d.]+ ([\d.]+) .* L [\d.]+ ([\d.]+) Z"/U, html)
        |> Enum.map(fn [_, top, bottom] -> {Float.parse(top), Float.parse(bottom)} end)
        |> Enum.map(fn {{t, _}, {b, _}} -> {t, b} end)

      assert length(bars) == 3
      [{t1, b1}, {t2, b2}, {t3, b3}] = bars
      assert b1 == b2 and b2 == b3
      assert b1 - t1 > 0 and t1 > t2 and t2 > t3
      # 0.05 -> 2 spans log10(40) decades; 2 -> 300 spans log10(150).
      assert_in_delta (t1 - t2) / (t2 - t3), :math.log10(40) / :math.log10(150), 1.0e-6
    end
  end

  # ── 6. point-annotation tooltips ─────────────────────────────────────────

  describe "point annotation tooltips" do
    defp tipped(extra \\ %{}) do
      Map.merge(
        %{
          id: "pt",
          type: :line,
          series: [%{name: "A", data: [1, 5, 3]}],
          categories: ~w(a b c),
          options: %{
            annotations: %{
              points: [
                %{x: "a", y: 1, label: %{text: "plain"}},
                %{x: "b", y: 5, label: %{text: "x"}, tooltip: "Peak <here>"}
              ]
            }
          }
        },
        extra
      )
    end

    test "a hover target and a matching tip are rendered" do
      html = render(tipped())
      [target] = tags(html, "circle", "eexcharts-annotation-hover")
      assert attr(target, "data-j") == "anno-1"
      assert html =~ ~s(data-j="anno-1" hidden)
      assert html =~ "Peak &lt;here&gt;"
      refute html =~ "anno-0"

      # The hover targets sit above the line chart's category zones.
      {zones, _} = :binary.match(html, "eexcharts-zones")
      {hover, _} = :binary.match(html, "eexcharts-annotation-hovers")
      assert hover > zones
    end

    test "works with the series tooltip disabled" do
      html =
        render(
          tipped(%{
            options: %{
              tooltip: %{enabled: false},
              annotations: %{points: [%{x: "b", y: 5, tooltip: "Peak"}]}
            }
          })
        )

      assert html =~ "eexcharts-tooltip"
      assert html =~ ~s(data-j="anno-0")
    end

    test "static output drops it" do
      p = tipped()
      svg = EexCharts.to_svg("pt", :line, p.series, categories: p.categories, options: p.options)
      refute svg =~ "anno-"
    end
  end
end
