# Features beyond ApexCharts v4.7.0

EexCharts ports ApexCharts.js v4.7.0, the last MIT release. ApexCharts v5.0.0
and later ship under a licence that forbids use in competing charting
products, so nothing here is derived from their code, bundles, docs or demos.

The features below were built from two sources only:

1. **Public release-note prose** (the GitHub release descriptions), which
   names what a feature does, never how. Nobody working on these features
   read, installed or ran ApexCharts v5+ code.
2. **General knowledge**: textbook statistics and published layout
   algorithms, cited per feature.

Where v4.7.0 already had the behaviour, it was ported from the v4.7.0 source
(MIT) instead. The release-note version is listed only as the reason the
feature exists, not as its source.

| Feature | Named in release notes | Built from | Module |
|---|---|---|---|
| Histogram (auto/fixed bins, normalisation, cumulative) | 6.9 | NumPy-compatible `histogram_bin_edges` rules: Freedman-Diaconis, Sturges, Scott, sqrt | `Charts.Histogram`, `Stats` |
| Box plot from raw observations | 6.9 | Quartiles by linear interpolation (Hyndman & Fan type 7), Tukey 1.5 IQR whiskers | `Charts.BoxPlot`, `Stats` |
| Violin, raincloud | 6.9, 7.1 | Gaussian KDE, Silverman's rule of thumb (1986) | `Charts.Violin`, `Stats` |
| Sunburst | 6.7 | Partition (icicle) layout in polar coordinates | `Charts.Sunburst`, `Hierarchy` |
| Nested treemaps | 6.9 | Squarified treemap (Bruls, Huizing, van Wijk 2000), applied recursively | `Charts.Treemap` |
| Funnel, pyramid types | 5.12 | v4.7.0 `isFunnel` (ported) | `Charts.Funnel` |
| Waterfall | 7.1 | Running totals, vertical and horizontal, per-kind colour / outline / pattern | `Charts.Waterfall` |
| Dumbbell type | 7.1 | v4.7.0 `isDumbbell` (ported) | `Charts.Dumbbell` |
| Grouped stacks, 100% per group | 8.2, 8.3 | Own design | `Charts.StackGroups` |
| Stacked and 100% area/line | 8.5 | v4.7.0 stacked area (ported), own 100% normalisation | `Stacking` |
| Streamgraph | 7.1 | Byron & Wattenberg (2008) wiggle; silhouette offset | `Stacking` |
| Gauge (bands, needle, ticks) | 5.12 | Own design on shared arc geometry | `Charts.Gauge`, `Charts.Sector` |
| Radial-bar targets | 8.5 | Own design | `Charts.RadialBar` |
| Pie `border_radius`, `spacing` | 6.7 | Own geometry (parallel edge offset, clamped fillets) | `Charts.Pie`, `Charts.Sector` |
| Unit (grid, parliament, beeswarm), waffle | 6.6, 6.7 | Largest-remainder rounding; hemicycle seat allocation by arc length; greedy beeswarm | `Charts.Unit` |
| Trellis small multiples | 7.0 | Own design | `Trellis` |
| Continuous heatmap x-axis, gradient legend | 6.4, 5.14 | Own design | `Charts.Heatmap.XLayout`, `Charts.Heatmap.GradientLegend` |
| Annotation dash patterns and line caps | 8.5 | SVG `stroke-dasharray` / `stroke-linecap` | `Annotations` |
| Balanced overlapping-label hiding | 8.5 | Own design (round-robin across series) | `DataLabels` |
| Thinned horizontal-bar categories | 8.5 | Own design | `Renderer` |
| Per-point data-label offset functions | 6.8 | Own design | `DataLabels` |
| Log axes below the base | 8.3 | Powers of the base below 1 | `Scale` |
| Point-annotation tooltips | 6.7 | Existing tooltip mechanism | `Annotations` |

## EexCharts extensions

These are not named in any ApexCharts release note. They were designed here,
mostly for static SVG output (`to_svg/4`) in reports, and sit next to the
v4.7.0 options they extend. v4.7.0 features they build on (data-point
`fillColor`, pattern fills, `goals`, `chart.sparkline`, timeline range bars,
`xaxis.position`, `enableShades`) were ported from the v4.7.0 source.

| Feature | Built from | Module |
|---|---|---|
| Outline-only series and points (`fill: %{type: :none}`) | Own design | `PointStyle` |
| Heatmap per-cell colours and multi-line cell labels | Own design | `Charts.Heatmap` |
| Heatmap rows top to bottom (`reverse_rows`); `xaxis.position: :top` on heatmaps only | Own design | `Charts.Heatmap` |
| Heatmap row groups and summary rows | Own design | `Charts.Heatmap.Rows` |
| Heatmap marked columns (`xaxis.marked`) | Own design | `Charts.Heatmap` |
| Circle goal markers (`goals: [%{shape: :circle, size:}]`) | Own design | `Goals` |
| Level meter (`:level_meter`) | Own design | `Charts.LevelMeter` |
| Line and area end labels | Own design; overlap removal as a 1-D least-squares fit | `EndLabels` |
| Sparkline marker pad of at least the drawn marker; pixel-exact bar sparklines | Own design | `Layout`, `Renderer` |
| Range bar labels past the bar end (`data_labels.position: :outside_end`) | Own design | `Charts.RangeBar` |

Deliberately not rebuilt: the canvas renderer, animations and tweening, wheel
zoom, keyboard navigation, shadow-DOM support (all browser-side), the
add-ons that need a paid licence key (perspectives, storyboard, ink, measure),
pictogram and unit-shape artwork, and locale translation strings (artwork and
text are copyrightable on their own).

How these features are checked to be correct without an upstream reference
to compare against: [VALIDATION.md](VALIDATION.md).
