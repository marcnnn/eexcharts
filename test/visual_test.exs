defmodule EexCharts.VisualTest do
  @moduledoc """
  Layer 2 visual regression gate — real pixel screenshots via
  phoenix_test_playwright driving headless Chromium against the storybook
  catalog. Catches font/CSS/rendering regressions the byte-level SVG gate
  (`EexCharts.SvgSnapshotTest`) can't see, and exercises the JS hook.

  These tests are tagged `:visual` and excluded by default (see
  `test/test_helper.exs`). Run them explicitly:

      mix test --only visual

  ## Baselines are not committed yet

  `test/visual/baseline/` currently holds no `*.png` — only a `.gitkeep`. That
  matters, because `assert_screenshot/3` **saves a baseline and passes** when
  none exists on disk, and only compares on subsequent runs. A CI job running
  against an empty baseline directory therefore seeds fresh baselines on every
  run and can never fail: a green check with zero pixel coverage.

  Seed them with the `Visual baselines` workflow
  (`.github/workflows/visual-baselines.yml`, `workflow_dispatch`), which runs
  this suite inside the Playwright image and opens a PR with the generated
  PNGs. Until that PR is merged, the CI `visual` job fails on purpose — see
  "Strict mode" below.

  ## Strict mode

  Set `EEXCHARTS_REQUIRE_BASELINE=1` and every screenshot assertion first
  requires its baseline file to already exist, failing loudly instead of
  silently seeding. CI sets it; local runs leave it unset so you can still
  generate images to eyeball (they will not match CI's font rendering, so do
  not commit them by hand).

  ## Determinism

  Pixel output depends on font rendering, so baselines must be generated in the
  same environment they're checked against — generate them only inside the
  official Playwright Docker image (`mcr.microsoft.com/playwright`), which is
  what both CI workflows use; `dev/assets/storybook.css` pins the font family.

  On mismatch a diff image is written to `test/visual/baseline/__diff__/` and
  the test fails.
  """
  use PhoenixTest.Playwright.Case, async: false

  @moduletag :visual

  @default_baseline_dir "test/visual/baseline"

  defp iframe_path(id), do: "/storybook/iframe/charts?variation_id=#{id}"

  describe "chart screenshots" do
    for example <- Dev.ChartExamples.all() do
      @example example

      test "#{@example.id} — #{@example.title}", %{conn: conn} do
        baseline = "#{@example.id}.png"
        # Checked before any page work so strict mode reports the real problem
        # instead of whatever the browser happens to do next.
        require_baseline!(baseline)

        conn
        |> visit(iframe_path(@example.id))
        |> assert_has(".eexcharts")
        # Element-scoped screenshot: just the chart's own container, so
        # storybook chrome/padding can't cause spurious diffs. Each variation
        # iframe holds exactly one chart, and phoenix_storybook rewrites the
        # component's DOM id (to `charts-single-<id>`), so scope by the unique
        # `.eexcharts` class rather than the example id.
        |> assert_screenshot(baseline, selector: ".eexcharts")
      end
    end
  end

  describe "hook interaction" do
    test "hovering a data point activates the tooltip", %{conn: conn} do
      conn
      |> visit(iframe_path("c1"))
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

  # `assert_screenshot/3` treats a missing baseline as "seed it and pass", which
  # turns an unseeded CI job into a gate that can never fail. The library has no
  # strict/fail-on-missing option (checked in phoenix_test_playwright 0.15), so
  # enforce it here: with EEXCHARTS_REQUIRE_BASELINE=1 the baseline must already
  # exist on disk before we take the screenshot.
  defp require_baseline!(name) do
    path = Path.join(baseline_dir(), name)

    if require_baseline?() and not File.exists?(path) do
      flunk("""
      Missing visual baseline: #{path}

      EEXCHARTS_REQUIRE_BASELINE=1 is set, so a missing baseline is a failure
      rather than a silent seed-and-pass.

      Baselines are environment-sensitive (font rendering) and must be produced
      inside mcr.microsoft.com/playwright:v1.49.0-noble. Do not hand-generate or
      commit locally-produced PNGs.

      To seed them, run the "Visual baselines" workflow on GitHub
      (Actions -> Visual baselines -> Run workflow, or
      `gh workflow run visual-baselines.yml`). It regenerates every baseline in
      that container and opens a PR; merge it and this gate goes live.

      To iterate locally instead, leave EEXCHARTS_REQUIRE_BASELINE unset:

          mix test --only visual
      """)
    end

    :ok
  end

  defp require_baseline? do
    System.get_env("EEXCHARTS_REQUIRE_BASELINE") in ~w(1 true yes)
  end

  # Mirrors config/test.exs; falls back to the conventional path so the guard
  # still points somewhere sensible if the config is ever dropped.
  defp baseline_dir do
    :phoenix_test
    |> Application.get_env(:playwright, [])
    |> Keyword.get(:snapshot_dir, @default_baseline_dir)
  end
end
