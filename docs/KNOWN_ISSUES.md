# Known issues

A boundary-condition audit of this port: pathological option values, degenerate
data, and ranges small or awkward enough to break tick generation. Every entry
below was reproduced — or refuted — against this code, and each is pinned by a
test in [`test/edge_cases_test.exs`](../test/edge_cases_test.exs).

## Confirmed defects

Each has a failing test (`@tag :pending`, excluded from `mix test`; run with
`mix test --include pending`).

| # | Defect | Affected code | Test |
| --- | --- | --- | --- |
| 1 | A forced `yaxis.step_size` is never validated: `0` raises `ArithmeticError`, a negative value raises or spins, and a step far smaller than the range builds ticks unboundedly (0…1e6 at step 1e-6 never returns). Renders from the public component API, so a user-supplied option can crash or hang a LiveView process. | `lib/eex_charts/scale.ex:134` (`step_size` path), `build_ticks/3` | `forced y-axis step_size is not validated` (3 cases) |
| 2 | Numeric x-axis labels collapse to `"0"` for small values, so every tick reads the same. A scatter chart over x ∈ [1e-5, 3e-5] renders five identical `0` labels. | `lib/eex_charts/svg.ex:68` (`fmt_value/1` rounds to 4 decimals), used by `lib/eex_charts/layout.ex:234` | `x-axis labels stay distinguishable…`, `fmt_value keeps enough precision…` |
| 3 | `Scale.linear_scale/4` rounds the step to 2 decimals, so a small x range loses its last tick and the axis stops short of the data: 0…0.07 yields a `nice_max` of 0.05, and points above it are drawn outside the grid. | `lib/eex_charts/scale.ex:270` | `linear_scale reaches x_max when the range is small` |
| 4 | `plot_options.bar.data_labels.position` only honours `:center`; `:top` and `:bottom` are identical. Negative bars get their label at the value end (below the bar) in every mode. | `lib/eex_charts/renderer.ex:647` (`bar_data_labels/3`) | `:top and :bottom place labels differently`, `position: :top puts a negative bar's label at its top (zero) edge` |
| 5 | `TimeScale.ticks/3` raises `ArithmeticError` on non-integer millisecond bounds, because `ceil_div/2` calls `Kernel.div/2`. Reachable from the public API via a float `xaxis.min`. | `lib/eex_charts/time_scale.ex:170` | `tolerates non-integer millisecond bounds` |
| 6 | A datetime chart crossing midnight gives no date context: hour ticks are labelled `HH:mm` only, so `20:00 … 00:00 … 04:00` never says which day a point belongs to. The first tick of a new day should be promoted to a date label; this port emits unit-uniform labels instead. | `lib/eex_charts/time_scale.ex:74` | `hour ticks crossing midnight carry the date` |

## Verified correct

Edge cases that behave correctly today and would be easy to break. Each is
pinned by an **untagged** guard test in the same file, so the default `mix test`
run catches a regression into any of them.

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
| Confirmed defects (open) | 6 |
| Behaviors pinned by guard tests | 12 |
