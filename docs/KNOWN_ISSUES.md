# Known issues

A boundary-condition audit of this port: pathological option values, degenerate
data, and ranges small or awkward enough to break tick generation. Every entry
below was reproduced — or refuted — against this code, and each is pinned by a
test in [`test/edge_cases_test.exs`](../test/edge_cases_test.exs), which runs as
part of `mix test`.

**Open: none.** All six defects found by the audit are fixed.

## Fixed defects

Each was reproduced through the public API first, then fixed. The test that
reproduced it is now a regression test.

| # | Defect | Fix |
| --- | --- | --- |
| 1 | A forced `yaxis.step_size` was never validated: `0` raised `ArithmeticError`, a negative value raised or spun, and a step far smaller than the range built ticks unboundedly (0…1e6 at step 1e-6 never returned). Renders from the public component API, so a user-supplied option could crash or hang a LiveView process. | `scale.ex` — a non-positive `step_size` is treated as unset and falls back to the computed nice step; `clamp_step/2` widens any step that would exceed `@max_intervals`; `build_ticks/3` returns a single tick rather than iterating on a non-positive step. |
| 2 | Numeric x-axis labels collapsed to `"0"` for small values, so every tick read the same. A scatter chart over x ∈ [1e-5, 3e-5] rendered five identical `0` labels. | `svg.ex` — `fmt_value/1` keeps four *significant* digits below a thousandth instead of a flat four decimals. Values ≥ 0.001 format exactly as before. |
| 3 | `Scale.linear_scale/4` rounded the step to 2 decimals, so a small x range lost its last tick and the axis stopped short of the data: 0…0.07 yielded a `nice_max` of 0.05, and points above it were drawn outside the grid. | `scale.ex` — the step is cleaned with `strip_number/1` (7 significant digits) rather than rounded to 2 decimals. |
| 4 | `plot_options.bar.data_labels.position` only honoured `:center`; `:top` and `:bottom` were identical, and negative bars got their label at the value end (below the bar) in every mode. | `renderer.ex` — `bar_label_pos/3` resolves the position against the rect's edges, so the top edge of a bar hanging below zero is the zero line. |
| 5 | `TimeScale.ticks/3` raised `ArithmeticError` on non-integer millisecond bounds, because `ceil_div/2` calls `Kernel.div/2`. Reachable from the public API via a float `xaxis.min`. | `time_scale.ex` — `ticks/3` normalizes its bounds to whole milliseconds once, at the entry point, which also covers the month and year generators. |
| 6 | A datetime chart crossing midnight gave no date context: hour ticks were labelled `HH:mm` only, so `20:00 … 00:00 … 04:00` never said which day a point belonged to. | `time_scale.ex` — `label_ticks/2` promotes the first sub-day tick of a new day to a date label. The first tick in a range keeps its time. |

Defect 3 also moved one committed golden (`test/snapshots/n1.svg`): a scatter
point previously drawn at `cx="590.32"`, past the grid's right edge at 590, now
lands on it, and the x labels read `10.375 … 36.4` instead of the truncated
`10.37 … 36.38`.

## Verified correct

Edge cases that behave correctly and would be easy to break. Each is pinned by a
guard test in the same file.

| Behavior | Why it holds |
| --- | --- |
| A range starting exactly on a minute/second boundary keeps that first tick | Fixed-unit ticks are epoch-aligned via ceiling division, which returns the boundary itself. Verified: a range starting at `10:05:00` keeps that tick. |
| A short month cannot shift the following month's ticks | Month ticks are real calendar month starts (`Date.new!/3`) and day ticks are epoch-aligned. Verified across Feb 20 → Mar 5. |
| Hidden series never reach tooltips | Hidden series are rejected before anything downstream is built (`renderer.ex:69`). There is no mutable series list to corrupt. |
| The legend cannot get stuck dimmed after a series is re-enabled | The legend is a pure function of the `hidden_series` assign; re-rendering without it emits no dimmed state, and no client-side state persists. |
| Annotation range bands keep their configured opacity on both axes | `Annotations.band/5` sets `fill_opacity` from `anno.opacity` on one shared path for x and y. Verified: x band 0.66, y band 0.77. |
| Area fills stay correct with `nil` gaps and sub-zero values | `nil` splits the series into segments, each closed independently against the zero baseline. Verified: two fills, one `Z` each. |
| An area path closes exactly once | `area_close/2` appends a single `Z`; no second close can be introduced. |
| Degenerate pie/donut slices render without raising | `nil`, `0` and negative values are handled for both pie and donut. |
| Series hover darkens rather than washing out | The hover filter is `brightness(0.92)`. There is no lighten filter to overshoot into white. |
| Bar data-label offsets apply in both orientations | `offset_x` / `offset_y` are applied to every bar data label regardless of horizontal or vertical layout. |
| Font sizes cannot be given in a unit we fail to parse | `font_size` is a number of px throughout this API, so no unit parsing exists. |
| A y-axis labels formatter cannot clip the axis title | Axis width is measured from *formatted* label text (`layout.ex:189`), and title space is reserved separately. |

## Status

| Bucket | Count |
| --- | --- |
| Open defects | 0 |
| Fixed defects, pinned by regression tests | 6 |
| Behaviors pinned by guard tests | 12 |
