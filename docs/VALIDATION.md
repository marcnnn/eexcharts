# Validating charts without an upstream reference

eexcharts re-implements ApexCharts.js v4.7.0. For the chart types that exist in
v4.7.0 we can compare against it. For everything added since (histogram,
violin, sunburst, funnel, ...) there is no reference we may look at, so "does
it look right?" has to be answered by our own tooling. Five layers do that,
cheapest first.

## Licence: never compare against ApexCharts v5+

ApexCharts v5.0.0 and later are not MIT; their licence forbids use in
competing charting products. Comparing our output with v5 renders, demos or
screenshots would make them the de-facto spec and taint the code written to
match them. So the only upstream we ever run or read is v4.7.0. New features
are built from public release-note prose plus textbooks and papers, and
validated with the layers below. See `CONTRIBUTING.md` for the full rule.

## Layer 0: invariant lint (`mix test`)

`test/svg_invariants_test.exs` renders every example in
`Dev.ChartExamples.all/0` three ways (static `to_svg/4`, static with the dark
theme, live `render/4`) and runs `EexCharts.SvgInvariants`
(`test/support/svg_invariants.ex`) on each:

- well-formed XML (OTP `:xmerl`), no `NaN` / `Infinity` / `nil` /
  `undefined`, every numeric attribute and every `d`, `points`, `transform`,
  `viewBox` parses to finite numbers; no negative width, height or radius;
- everything drawn lies inside the viewBox: rects, circles, lines, polygons,
  paths (all M/L/H/V/C/S/Q/T/A/Z commands, absolute and relative, with exact
  Bezier extrema and sampled arcs) and estimated text boxes, all through the
  accumulated `transform`s;
- ids are unique and every `url(#id)` / `href="#id"` resolves;
- texts of one label group (the text's class, else its nearest classed
  ancestor) do not overlap; boxes come from `EexCharts.FontMetrics`, rotated
  labels are compared as rotated rectangles, multi-line labels line by line;
- a label drawn on its own background box is readable (contrast at least 1.5:1);
- a drawn legend has one entry per series (per label for pie-like charts).

New examples are covered automatically. When one fails, either the renderer
is wrong (fix it, or add an entry to `@known_bugs` with the reason; it is an
expected failure that flags itself once fixed) or the check is too strict for
a deliberate design (add an `@allow` entry with the reason).
`test/svg_invariants_checker_test.exs` proves each check actually fires.

Text boxes are estimates (within a few px of Chrome's `getBBox` on the
catalog; bold is widened by 7 %), so text bounds get 2 px of tolerance and an
overlap must exceed 1 px.

Exploratory run at other widths (not part of CI, finds layout bugs that the
fixed example sizes hide):

    EEXCHARTS_INVARIANT_WIDTHS=320,900 mix test test/svg_invariants_test.exs

## Layer 1: SVG goldens (`mix test`)

`test/svg_snapshot_test.exs` compares every example with
`test/snapshots/<id>.svg`: markup exactly, numbers numerically. Goldens say
"nothing changed", not "it is right", so a golden is only seeded after layers
0, 3 and 4 passed. Seed or update with
`EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test test/svg_snapshot_test.exs` and review
`git status test/snapshots` (existing goldens must not move unless intended).

## Layer 2: pixel baselines (`mix test --only visual`, Docker)

`test/visual_test.exs` screenshots each example in the storybook with
Playwright and diffs it against `test/visual/baseline/`. Catches font, CSS and
hook regressions the SVG text cannot show. Baselines depend on font
rendering, so they are only seeded and checked inside the Playwright Docker
image used by CI.

## Layer 3: numeric oracles (per chart type, `mix test`)

Each chart type's own test file asserts the numbers the renderer derives
against values computed independently:

- statistics against numpy/scipy (`ASDF_PYTHON_VERSION=3.13.2 python3 ...`),
  pasted into the test as literals: bin edges (Freedman-Diaconis, Sturges),
  quartiles, KDE densities (Silverman's bandwidth), whiskers;
- layouts against worked examples done by hand in the test: treemap and
  sunburst areas proportional to values, arc angles summing to 360 degrees,
  funnel/waterfall steps, stacks contiguous, shares summing to 100 %, hidden
  series removed.

Assert on the SVG (rect sizes, arc end points) or on the layout function's
return value, not on the golden.

## Layer 4: human approval via the contact sheet

    mix run dev/contact_sheet.exs          # tmp/contact_sheet.html
    mix run dev/contact_sheet.exs --png    # + tmp/contact_sheet.png (headless Chrome)
    mix run dev/contact_sheet.exs --group radar --png
    mix run dev/contact_sheet.exs --only c1,n2

Every example as static SVG with id, title, group and type, light and dark
side by side. Look at it before seeding goldens for a new chart: does it read
like a sibling of the v4.7.0 charts (palette, fonts, stroke widths, grid,
legend), is anything clipped, unreadable or misaligned in either theme? Layers
0-3 cannot judge taste; this is where a person does.
