# Used by "mix format"
[
  inputs:
    ["{mix,.formatter}.exs", "{config,lib,test,dev}/**/*.{ex,exs}"]
    |> Enum.flat_map(&Path.wildcard/1)
    # The Arial/Helvetica advance-width tables are laid out as tables on
    # purpose: the formatter would give each of their ~100 entries a line of
    # its own, turning readable data into 200 lines of scroll.
    |> Kernel.--(["lib/eex_charts/font_metrics.ex"])
]
