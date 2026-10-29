defmodule EexCharts.SvgSnapshotTest do
  @moduledoc """
  Layer 1 visual regression gate — fast, browserless, runs in `mix test`.

  Every `Dev.ChartExamples.all/0` entry is rendered twice and compared against
  two committed goldens:

    * `test/snapshots/<id>.svg` — `EexCharts.to_svg/4`, the standalone `<svg>`
      for static output. A real SVG file, so GitHub and image viewers show it
      as a picture when reviewing a change.
    * `test/snapshots/<id>.html` — `EexCharts.render/4` with `hook: false` (so
      the output is free of the `phx-hook` attribute): the full LiveView
      fragment, with the wrapper `<div>`, the hover furniture the static SVG
      leaves out, and the HTML tooltips.

  This catches structural/geometry regressions on every commit with zero
  flakiness, since the renderer is a pure function of its input and every
  example is deterministic.

  Markup has to match exactly; numbers have to match numerically. See
  `EexCharts.SnapshotDiff` for why that distinction earns its keep — in short,
  the goldens carry full-precision floats, and the last bit of a `:math.cos/1`
  result is not the same on macOS as on the Linux runner that seeds them.

  ## Regenerating goldens

  When the output *should* change (a deliberate renderer tweak), regenerate the
  goldens instead of asserting:

      EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test test/svg_snapshot_test.exs

  Only goldens that no longer match are rewritten, so regenerating on macOS
  leaves the Linux-seeded floats of every other golden alone. Review the
  resulting diff in `test/snapshots/` before committing.
  """
  use ExUnit.Case, async: true

  @snapshots_dir Path.join(__DIR__, "snapshots")
  @update? System.get_env("EEXCHARTS_UPDATE_SNAPSHOTS") not in [nil, ""]

  defp attributes(example) do
    example
    |> Dev.ChartExamples.attributes()
    |> Map.drop([:id, :type, :series])
  end

  defp render(example, :svg) do
    EexCharts.to_svg(example.id, example.type, example.series, Map.to_list(attributes(example)))
  end

  defp render(example, :html) do
    opts = example |> attributes() |> Map.put(:hook, false) |> Map.to_list()
    {:safe, io} = EexCharts.render(example.id, example.type, example.series, opts)
    IO.iodata_to_binary(io)
  end

  setup_all do
    File.mkdir_p!(@snapshots_dir)
    :ok
  end

  for example <- Dev.ChartExamples.all(), format <- [:svg, :html] do
    @example example
    @format format
    @golden Path.join(@snapshots_dir, "#{example.id}.#{format}")

    test "#{@example.id}.#{@format} — #{@example.title}" do
      actual = render(@example, @format)
      expected = if File.exists?(@golden), do: File.read!(@golden)

      result =
        if expected,
          do: EexCharts.SnapshotDiff.compare(actual, expected),
          else: {:error, "missing golden #{@golden}"}

      case result do
        :ok ->
          :ok

        {:error, _detail} when @update? ->
          File.write!(@golden, actual)

        {:error, detail} ->
          flunk(
            "Snapshot mismatch for #{@example.id}.#{@format} (#{@example.title}).\n\n" <>
              detail <>
              "\nIf this change is intentional, regenerate with " <>
              "EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test."
          )
      end
    end
  end
end
