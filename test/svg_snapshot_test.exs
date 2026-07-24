defmodule EexCharts.SvgSnapshotTest do
  @moduledoc """
  Layer 1 visual regression gate — fast, browserless, runs in `mix test`.

  For every `Dev.ChartExamples.all/0` entry we render the chart to SVG (with
  `hook: false` so the output is stable and free of the `phx-hook` attribute)
  and assert it byte-for-byte matches a committed golden file in
  `test/snapshots/<id>.svg`. This catches structural/geometry regressions on
  every commit with zero flakiness, since the renderer is a pure function of
  its input and every example is deterministic.

  ## Regenerating goldens

  When the output *should* change (a deliberate renderer tweak), regenerate the
  goldens instead of asserting:

      EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test test/svg_snapshot_test.exs

  Review the resulting diff in `test/snapshots/` before committing.
  """
  use ExUnit.Case, async: true

  @snapshots_dir Path.join(__DIR__, "snapshots")
  @update? System.get_env("EEXCHARTS_UPDATE_SNAPSHOTS") not in [nil, ""]

  defp render_svg(example) do
    opts =
      example
      |> Dev.ChartExamples.attributes()
      |> Map.drop([:id, :type, :series])
      |> Map.put(:hook, false)
      |> Map.to_list()

    {:safe, io} = EexCharts.render(example.id, example.type, example.series, opts)
    IO.iodata_to_binary(io)
  end

  setup_all do
    File.mkdir_p!(@snapshots_dir)
    :ok
  end

  for example <- Dev.ChartExamples.all() do
    @example example
    @golden Path.join(@snapshots_dir, "#{example.id}.svg")

    test "#{@example.id} — #{@example.title}" do
      actual = render_svg(@example)

      if @update? do
        File.write!(@golden, actual)
      else
        assert File.exists?(@golden),
               "missing golden #{@golden}. Seed it with EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test"

        expected = File.read!(@golden)

        assert actual == expected,
               "SVG snapshot mismatch for #{@example.id} (#{@example.title}).\n" <>
                 "If this change is intentional, regenerate with " <>
                 "EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test."
      end
    end
  end
end
