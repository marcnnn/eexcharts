defmodule EexCharts.SvgInvariantsTest do
  @moduledoc """
  Layer 0 of `docs/VALIDATION.md`: generic invariants every rendered chart must
  satisfy, checked for every example in `Dev.ChartExamples.all/0` in both
  outputs (`EexCharts.to_svg/4` and the live `EexCharts.render/4` markup).
  See `EexCharts.SvgInvariants` for the individual checks.

  New examples are covered automatically. When one fails, decide whether the
  renderer is wrong (fix it, or record it in `docs/KNOWN_ISSUES.md`) or the
  check is too strict for a deliberate design (add an `@allow` entry below,
  with the reason).
  """
  use ExUnit.Case, async: true

  alias EexCharts.SvgInvariants

  @sparkline_hover "sparkline: the plot fills the SVG, so the hover marker on the first " <>
                     "and last point (live output only) overhangs the edge, as in ApexCharts " <>
                     "v4.7.0; reserving room for it would shrink a 24px plot. Drawn markers are " <>
                     "padded and stay inside"

  # Deliberate exceptions: the check is too strict for an intentional design.
  # Each entry matches violations by example id (a string, or `:any`), check
  # and a regex (string, OTP 28 cannot store compiled regexes in attributes) on
  # the element description, and carries its reason.
  @allow [
    # %{id: "x1", check: :text_overlap, element: "...", reason: "..."}
    %{
      id: "sp3",
      check: :bounds,
      element: "^circle\\.eexcharts-hover-marker",
      reason: @sparkline_hover
    },
    %{
      id: "sp4",
      check: :bounds,
      element: "^circle\\.eexcharts-hover-marker",
      reason: @sparkline_hover
    }
  ]

  # Real renderer defects found by this suite and not fixed yet. Same shape as `@allow`, plus `:variant` (the
  # output the bug shows in). These are expected failures: once the renderer
  # is fixed the entry no longer matches and the test fails, asking for the
  # entry to be removed.
  @known_bugs [
    %{
      id: "n2",
      variant: :any,
      check: :bounds,
      element: "^circle\\.eexcharts-marker",
      reason:
        "bubble at the x-axis maximum (r=26) is centred on the plot edge, so 9.6px " <>
          "of it falls past the right edge of the SVG and is cut off"
    }
  ]

  # `overrides` deep-merges into the example's options; `width` replaces it.
  defp static_svg(example, overrides \\ %{}, width \\ nil) do
    attrs = Dev.ChartExamples.attributes(example)

    opts =
      attrs
      |> Map.drop([:id, :type, :series])
      |> Map.put(:options, deep_merge(attrs[:options] || %{}, overrides))
      |> then(&if(width, do: Map.put(&1, :width, width), else: &1))
      |> Map.to_list()

    EexCharts.to_svg(example.id, example.type, example.series, opts)
  end

  defp live_markup(example) do
    opts =
      example
      |> Dev.ChartExamples.attributes()
      |> Map.drop([:id, :type, :series])
      |> Map.to_list()

    {:safe, io} = EexCharts.render(example.id, example.type, example.series, opts)
    IO.iodata_to_binary(io)
  end

  defp deep_merge(a, b) do
    Map.merge(a, b, fn
      _k, %{} = x, %{} = y -> deep_merge(x, y)
      _k, _x, y -> y
    end)
  end

  @dark %{theme: %{mode: :dark}, chart: %{background: "#343434"}}

  # Opt-in extra widths for exploratory runs, e.g.
  # EEXCHARTS_INVARIANT_WIDTHS=320,900 mix test test/svg_invariants_test.exs
  @extra_widths (System.get_env("EEXCHARTS_INVARIANT_WIDTHS") || "")
                |> String.split(",", trim: true)
                |> Enum.map(&String.to_integer(String.trim(&1)))

  defp metrics(example), do: get_in(example, [:options, :chart, :font_metrics]) || :arial

  defp matches?(entry, example, v) do
    entry.id in [:any, example.id] and entry.check == v.check and
      v.element =~ Regex.compile!(entry.element)
  end

  defp known_bugs(example, label) do
    Enum.filter(@known_bugs, &(&1.id == example.id and &1.variant in [:any, label]))
  end

  defp assert_clean(example, markup, label) do
    found =
      markup
      |> SvgInvariants.check(metrics: metrics(example))
      |> Kernel.++(legend_violations(example, markup))
      |> Enum.reject(fn v -> Enum.any?(@allow, &matches?(&1, example, v)) end)

    bugs = known_bugs(example, label)
    violations = Enum.reject(found, fn v -> Enum.any?(bugs, &matches?(&1, example, v)) end)

    fixed = Enum.reject(bugs, fn bug -> Enum.any?(found, &matches?(bug, example, &1)) end)

    assert fixed == [],
           "known bug no longer reproduces in the #{label} SVG of #{example.id}, " <>
             "remove it from @known_bugs: " <> Enum.map_join(fixed, "; ", & &1.reason)

    assert violations == [],
           "#{label} SVG of #{example.id} (#{example.title}) breaks #{length(violations)} invariant(s):\n" <>
             Enum.map_join(violations, "\n", fn v ->
               "  [#{v.check}] #{v.element}: #{v.detail}"
             end)
  end

  # Where a legend is drawn it has one entry per series, or per label for the
  # single-series circular charts (pie, donut, polar area, radial bar).
  # Hidden (toggled-off) series keep their entry, greyed out, as in ApexCharts.
  defp legend_violations(example, markup) do
    with {:ok, tree} <- SvgInvariants.parse(markup),
         [_ | _] <- SvgInvariants.with_class(tree, "eexcharts-legend"),
         expected when is_integer(expected) <- expected_legend_entries(example) do
      actual = length(SvgInvariants.with_class(tree, "eexcharts-legend-item"))

      if actual == expected,
        do: [],
        else: [
          %{
            check: :legend,
            element: "g.eexcharts-legend",
            detail: "#{actual} entries, expected #{expected}"
          }
        ]
    else
      _ -> []
    end
  end

  # Types whose legend does not list series: waterfall shows the bar kinds
  # (increase / decrease / total), dumbbell one item per end, and a heatmap
  # gradient legend is a colour bar with no items at all.
  defp expected_legend_entries(%{type: t}) when t in [:waterfall, :dumbbell], do: nil

  defp expected_legend_entries(%{type: :heatmap, options: %{legend: %{gradient: g}}})
       when g not in [nil, false],
       do: nil

  # Sunburst: one entry per top-level branch, which is each point of a single
  # series, or each series when there are several.
  defp expected_legend_entries(%{type: :sunburst, series: [%{data: data}]}), do: length(data)

  # Unit and waffle (grid / parliament): one entry per category, which is
  # each point when a single series carries `%{x:, y:}` points.
  defp expected_legend_entries(%{type: t, series: [%{data: [%{x: _} | _] = data}]} = example)
       when t in [:unit, :waffle] do
    if get_in(example, [:options, :plot_options, :unit, :layout]) == :beeswarm,
      do: 1,
      else: length(data)
  end

  # Trellis: one shared legend keyed by series name, so a name repeated across
  # panels is a single entry.
  defp expected_legend_entries(%{options: %{trellis: %{}}, series: series}),
    do: series |> Enum.map(& &1.name) |> Enum.uniq() |> length()

  defp expected_legend_entries(%{series: series} = example) do
    cond do
      Enum.all?(series, &is_number/1) -> length(example[:labels] || series)
      Enum.all?(series, &(is_map(&1) and Map.has_key?(&1, :data))) -> length(series)
      true -> nil
    end
  end

  for example <- Dev.ChartExamples.all() do
    @example example

    describe "#{@example.id} (#{@example.title})" do
      test "static to_svg/4 output" do
        assert_clean(@example, static_svg(@example), "static")
      end

      test "static output, dark theme" do
        assert_clean(@example, static_svg(@example, @dark), "static dark")
      end

      test "live render/4 output" do
        assert_clean(@example, live_markup(@example), "live")
      end

      for width <- @extra_widths do
        @width width
        test "static output at width #{width}" do
          assert_clean(@example, static_svg(@example, %{}, @width), "static w=#{@width}")
        end
      end
    end
  end
end
