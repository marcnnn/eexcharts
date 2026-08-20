defmodule EexCharts.Theme do
  @moduledoc """
  Theme handling, ported from ApexCharts.js v4.7.0 `src/modules/Theme.js`
  (`updateThemeOptions`/`predefined`) and `settings/Config.js`
  (`checkForDarkTheme`).

  `:light` (the default) leaves the config untouched so per-chart-type defaults
  (e.g. the pie's dark tooltip) survive. `:dark` is ApexCharts' own dark theme.
  `:daisy` is an EexCharts addition that maps the chart onto
  [daisyUI](https://daisyui.com) theme variables — see `apply/2`.
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

  # ── daisyUI ────────────────────────────────────────────────────────────────
  #
  # daisyUI (v5) publishes the active theme as CSS custom properties on the
  # element tree: `--color-primary`, `--color-base-100`, and so on. We only
  # ever emit the *variable name*, so the browser resolves whichever theme is
  # active — switching `data-theme` on an ancestor re-themes an already
  # rendered chart with no server round-trip, and dark mode comes for free.
  #
  # Every value carries the ApexCharts literal it replaces as its var()
  # fallback. A chart rendered in `:daisy` mode on a page without daisyUI
  # therefore still looks like the light theme rather than degrading to black.
  #
  # The series palette walks daisyUI's semantic colors in the order a
  # categorical scale wants them. Fallbacks continue to cycle palette1, so
  # without daisyUI the first five series are pixel-identical to `:light` and
  # series 6-8 land on the colors ApexCharts' own 5-color cycle would pick.
  @daisy_series [
    {"primary", "#008FFB"},
    {"secondary", "#00E396"},
    {"accent", "#FEB019"},
    {"info", "#FF4560"},
    {"success", "#775DD0"},
    {"warning", "#008FFB"},
    {"error", "#00E396"},
    {"neutral", "#FEB019"}
  ]

  @daisy_colors Enum.map(@daisy_series, fn {name, fb} -> "var(--color-#{name}, #{fb})" end)

  # Labels drawn *on* a mark use daisyUI's paired content color, which is
  # guaranteed to contrast with its partner in every theme. ApexCharts instead
  # hardcodes white here, so this is strictly better than the port it replaces.
  @daisy_label_colors Enum.map(@daisy_series, fn {name, _fb} ->
                        "var(--color-#{name}-content, #fff)"
                      end)

  @daisy_fore "var(--color-base-content, #373d3f)"
  # The chart surface: what ApexCharts assumes is a white page. Separators
  # between adjacent marks and marker rings are cut out of it.
  @daisy_surface "var(--color-base-100, #fff)"
  @daisy_track "var(--color-base-200, #f2f2f2)"
  @daisy_border "var(--color-base-300, #e0e0e0)"
  @daisy_border_soft "var(--color-base-300, #e8e8e8)"

  @doc "Returns the named palette (`:palette1`..`:palette10`), or palette1."
  def palette(name), do: Map.get(@palettes, name, @palettes.palette1)

  @doc "The daisyUI series palette: one `var(--color-*)` per semantic color."
  def daisy_palette, do: @daisy_colors

  @doc "The daisyUI on-mark label palette, paired 1:1 with `daisy_palette/0`."
  def daisy_label_palette, do: @daisy_label_colors

  @doc """
  Applies theme adjustments to a fully-merged config. `opts` is the raw user
  option map, used (like ApexCharts) to only override values the user did not
  explicitly set.

  Under `mode: :daisy` the following are mapped to daisyUI variables: the
  series palette, on-mark data label colors, `chart.fore_color`, the grid and
  x-axis border/tick colors, the white separator between adjacent marks, marker
  stroke rings, the radial-bar track, the radar/polar-area rings and spokes,
  and the tooltip. Setting `theme.palette` keeps daisyUI chrome but restores an
  ApexCharts palette for the series.
  """
  def apply(cfg, opts \\ %{}) do
    case cfg.theme.mode do
      :dark -> apply_dark(cfg, opts)
      :daisy -> apply_daisy(cfg, opts)
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

  defp apply_daisy(cfg, opts) do
    cfg
    |> daisy_series(opts)
    |> put_unless_set([:chart, :fore_color], @daisy_fore, opts)
    |> put_unless_set([:grid, :border_color], @daisy_border, opts)
    |> put_unless_set([:xaxis, :axis_border, :color], @daisy_border, opts)
    |> put_unless_set([:xaxis, :axis_ticks, :color], @daisy_border, opts)
    |> put_unless_set([:markers, :stroke_colors], @daisy_surface, opts)
    |> put_unless_set([:plot_options, :radial_bar, :track, :background], @daisy_track, opts)
    |> put_unless_set(
      [:plot_options, :radar, :polygons, :stroke_colors],
      @daisy_border_soft,
      opts
    )
    |> put_unless_set(
      [:plot_options, :radar, :polygons, :connector_colors],
      @daisy_border_soft,
      opts
    )
    |> put_unless_set(
      [:plot_options, :polar_area, :rings, :stroke_color],
      @daisy_border_soft,
      opts
    )
    |> put_unless_set(
      [:plot_options, :polar_area, :spokes, :connector_colors],
      @daisy_border_soft,
      opts
    )
    |> daisy_separator_stroke(opts)
    |> put_unless_set([:tooltip, :theme], :daisy, opts)
  end

  # An explicit `theme.palette` means "daisyUI chrome, ApexCharts series", so
  # the palette (and the label colors paired with it) stay hex.
  defp daisy_series(cfg, opts) do
    cond do
      not is_nil(cfg.colors) or not is_nil(opts[:colors]) -> cfg
      pal = cfg.theme.palette -> %{cfg | colors: palette(pal)}
      true -> cfg |> Map.put(:colors, @daisy_colors) |> daisy_label_colors(opts)
    end
  end

  # `data_labels.style.colors` is nil for the chart types whose labels float
  # over the chart background (where a content color would be invisible) and a
  # list for the types that draw labels on top of a filled mark. Only the
  # latter want daisyUI's paired content colors.
  defp daisy_label_colors(cfg, opts) do
    if is_list(cfg.data_labels.style.colors) do
      put_unless_set(cfg, [:data_labels, :style, :colors], @daisy_label_colors, opts)
    else
      cfg
    end
  end

  # ApexCharts separates adjacent slices/cells/tiles with a white stroke that
  # assumes a white page; under daisyUI it has to follow the surface color.
  # Deliberate dark outlines (candlestick "#333", box plot "#24292e") are left
  # alone — they are a mark's own border, not a cut-out.
  defp daisy_separator_stroke(cfg, opts) do
    if cfg.stroke.colors == ["#fff"] do
      put_unless_set(cfg, [:stroke, :colors], [@daisy_surface], opts)
    else
      cfg
    end
  end

  defp put_unless_set(cfg, path, value, opts) do
    if is_nil(get_in(opts, path)), do: put_in(cfg, path, value), else: cfg
  end
end
