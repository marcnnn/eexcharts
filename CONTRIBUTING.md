# Contributing to EexCharts

Thanks for helping out. One thing makes this project unusual, so please read the
license boundary before touching anything ApexCharts-related.

## License boundary (important)

EexCharts is a re-implementation of **ApexCharts.js v4.7.0**, the last release
published under the MIT license. Every release from **v5.0.0 onward is
dual-licensed** (Community / Commercial) and is **not** MIT. EexCharts must stay
MIT-licensable, which means the project cannot contain code derived from
ApexCharts v5 or later.

ApexCharts **v4.7.0** source is MIT and is already this port's basis, so it stays
fair game. Anything newer does not.

### Do not read, fetch, clone, install, or copy from

- Any ApexCharts source at v5.0.0 or later — `/blob/`, `raw.githubusercontent`,
  `/commit/`, `/pull/*/files`, `.diff`, `.patch`, `git clone`, `git fetch`.
- `npm install apexcharts@>=5`, unpkg / jsDelivr `dist` bundles, minified
  bundles, or sourcemaps.
- The docs site's bundled JavaScript.

Practical rule: **never open a URL containing `/blob/`, `/commit/`,
`/pull/<n>/files`, or `.patch`**, and never call `gh api .../compare` or
`.../commits/{sha}` — those return patches.

### If you are accidentally exposed

If you hit a v5+ diff or code snippet — they turn up in threads and search
results without warning:

1. Stop reading immediately.
2. Keep only the behavior you had already established on your own.
3. Say so on the issue, so the fix is written from behavior rather than from
   what you saw.

PR checklist item: *"I did not read ApexCharts v5+ source while writing this
change."*

See [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md) for the open defects and the
edge-case behavior our guard tests pin.

## Development

```sh
mix deps.get
mix test                     # unit + SVG golden tests, no browser needed
mix dev                      # storybook at http://localhost:4004
```

### Test suites

- `mix test` — unit tests plus the byte-for-byte SVG golden gate
  (`test/svg_snapshot_test.exs`). Regenerate goldens with
  `EEXCHARTS_UPDATE_SNAPSHOTS=1 mix test test/svg_snapshot_test.exs` when an
  output change is intentional.
- `mix test --only visual` — headless-Chromium screenshot diffs. Baselines are
  environment-sensitive; see the README.

### Edge cases

`test/edge_cases_test.exs` is the boundary-condition suite: pathological option
values, degenerate data, and awkward ranges. It runs as part of `mix test` and
every case must stay green. When you find a new defect, add the failing test
there first and record it in `docs/KNOWN_ISSUES.md`.
