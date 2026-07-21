defmodule EexCharts.Theme do
  @moduledoc """
  Theme handling, ported from ApexCharts.js v4.7.0 `src/modules/Theme.js`
  (`updateThemeOptions`/`predefined`) and `settings/Config.js`
  (`checkForDarkTheme`).

  Only `mode: :dark` currently changes anything; `:light` (the default) leaves
  the config untouched so per-chart-type defaults (e.g. the pie's dark tooltip)
  survive.
  """

  # predefined() palettes from Theme.js
  @palettes %{
    palette1: ["#008FFB", "#00E396", "#FEB019", "#FF4560", "#775DD0"],
    palette2: ["#3f51b5", "#03a9f4", "#4caf50", "#f9ce1d", "#FF9800"],
    palette3: ["#33b2df", "#546E7A", "#d4526e", "#13d8aa", "#A5978B"],
    palette4: ["#4ecdc4", "#c7f464", "#81D4FA", "#fd6a6a", "#546E7A"],
    palette5: ["#2b908f", "#f9a3a4", "#90ee7e", "#fa4443", "#69d2e7"],
    palette6: ["#449DD1", "#F86624", "#EA3546", "#662E9B", "#C5D86D"],
    palette7: ["#D7263D", "#1B998B", "#2E294E", "#F46036", "#E2C044"],
    palette8: ["#662E9B", "#F86624", "#F9C80E", "#EA3546", "#43BCCD"],
    palette9: ["#5C4742", "#A5978B", "#8D5B4C", "#5A2A27", "#C4BBAF"],
    palette10: ["#A300D6", "#7D02EB", "#5653FE", "#2983FF", "#00B1F2"]
  }

  # ApexCharts' dark theme (`updateThemeOptions`/`checkForDarkTheme`) changes
  # exactly three things: the palette (palette4), the fore color, and the
  # tooltip theme. It does NOT touch the grid border color or the chart
  # background, so neither do we.
  @dark_fore "#f6f7f8"

  @doc "Returns the named palette (`:palette1`..`:palette10`), or palette1."
  def palette(name), do: Map.get(@palettes, name, @palettes.palette1)

  @doc """
  Applies theme adjustments to a fully-merged config. `opts` is the raw user
  option map, used (like ApexCharts) to only override values the user did not
  explicitly set.
  """
  def apply(cfg, opts \\ %{}) do
    case cfg.theme.mode do
      :dark -> apply_dark(cfg, opts)
      _ -> cfg
    end
  end

  defp apply_dark(cfg, opts) do
    cfg
    |> put_colors(opts)
    |> put_fore_color(opts)
    |> put_tooltip_theme(opts)
  end

  # palette4 for dark; only when the user did not pass explicit colors.
  defp put_colors(cfg, opts) do
    if is_nil(cfg.colors) and is_nil(opts[:colors]) do
      pal = cfg.theme.palette || :palette4
      %{cfg | colors: palette(pal)}
    else
      cfg
    end
  end

  defp put_fore_color(cfg, opts) do
    if get_in(opts, [:chart, :fore_color]) do
      cfg
    else
      put_in(cfg, [:chart, :fore_color], @dark_fore)
    end
  end

  # ApexCharts forces tooltip.theme to :dark unless the user explicitly set
  # it to :light (checkForDarkTheme).
  defp put_tooltip_theme(cfg, opts) do
    if get_in(opts, [:tooltip, :theme]) == :light do
      cfg
    else
      put_in(cfg, [:tooltip, :theme], :dark)
    end
  end
end
