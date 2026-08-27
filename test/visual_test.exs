defmodule EexCharts.VisualTest do
  @moduledoc """
  Layer 2 visual regression gate — real pixel screenshots via
  phoenix_test_playwright driving headless Chromium against the storybook
  catalog. Catches font/CSS/rendering regressions the byte-level SVG gate
  (`EexCharts.SvgSnapshotTest`) can't see, and exercises the JS hook.

  These tests are tagged `:visual` and excluded by default (see
  `test/test_helper.exs`). Run them explicitly:

      mix test --only visual

  `assert_screenshot/3` compares the live screenshot against a committed
  baseline in `test/visual/baseline/`, using Playwright's native pixel diff
  (which handles anti-aliasing tolerance for us). On the first run — or after
  you delete a baseline — the current screenshot is saved as the new baseline
  and the test passes. On mismatch a diff image is written to
  `test/visual/baseline/__diff__/` and the test fails.

  ## Determinism

  Pixel output depends on font rendering, so baselines must be generated in the
  same environment they're checked against — run this suite (and seed baselines)
  only inside the official Playwright Docker image
  (`mcr.microsoft.com/playwright`); `dev/assets/storybook.css` pins the font
  family. See `.github/workflows/ci.yml`.
  """
  use PhoenixTest.Playwright.Case, async: false

  @moduletag :visual

  # The catalog is split into one story per chart family (`dev/storybook/`), so
  # the iframe path is derived from the example's `:group` rather than being
  # hardcoded to a single story.
  defp iframe_path(example) do
    "/storybook/iframe/#{Dev.ChartExamples.story_path(example)}?variation_id=#{example.id}"
  end

  describe "chart screenshots" do
    for example <- Dev.ChartExamples.all() do
      @example example

      test "#{@example.id} — #{@example.title}", %{conn: conn} do
        conn
        |> visit(iframe_path(@example))
        |> assert_has(".eexcharts")
        # Element-scoped screenshot: just the chart's own container, so
        # storybook chrome/padding can't cause spurious diffs. Each variation
        # iframe holds exactly one chart, and phoenix_storybook rewrites the
        # component's DOM id (to `<story>-single-<id>`), so scope by the unique
        # `.eexcharts` class rather than the example id.
        |> assert_screenshot("#{@example.id}.png", selector: ".eexcharts")
      end
    end
  end

  describe "hook interaction" do
    test "hovering a data point activates the tooltip", %{conn: conn} do
      conn
      |> visit(iframe_path(Dev.ChartExamples.fetch!("c1")))
      |> assert_has(".eexcharts")
      # The hook listens for pointermove on the container and reveals the
      # tooltip for the hovered category. Hover the transparent per-category
      # hover zone (one `.eexcharts-zone` rect per category, so `data-j='0'` is
      # unique here — the bare `[data-j='0']` also matches the per-series
      # markers and the tooltip div, which trips Playwright's strict mode).
      |> unwrap(fn %{frame_id: frame_id} ->
        {:ok, _} =
          PlaywrightEx.Frame.hover(frame_id,
            selector: ".eexcharts .eexcharts-zone[data-j='0']",
            timeout: timeout()
          )
      end)
      |> assert_has(".eexcharts-tooltip-active")
    end
  end
end
