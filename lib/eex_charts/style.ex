defmodule EexCharts.Style do
  @moduledoc """
  A style is the look of a chart family: stroke widths, fill opacity, marker
  and legend shapes, fonts, grid weight. Where `theme.mode` decides which
  colors the chrome is painted in, a style decides how the marks are drawn, so
  the two compose: `%{style: :chartjs, theme: %{mode: :daisy}}` is Chart.js
  shapes in daisyUI colors.

  A style is a module implementing this behaviour. Its `c:defaults/1` returns
  option overrides (the same shape as the `options` a chart takes) for one
  chart type. `EexCharts.Config.build/2` layers them between ApexCharts'
  per-type defaults and the user's options:

      base defaults → type defaults → style → user options → theme

  so anything the user sets still wins, and dark/daisy theming still applies
  on top.

  Built-in styles:

    * `:apexcharts` (default) — `EexCharts.Style.ApexCharts`, no overrides
    * `:chartjs` — `EexCharts.Style.ChartJS`, Chart.js v4 defaults

  Pick one per chart with `options={%{style: :chartjs}}`, or for the whole app:

      config :eexcharts, style: :chartjs

  A custom style is any module implementing the behaviour, passed in place of
  the atom: `%{style: MyApp.ChartStyle}`.
  """

  @doc "Option overrides for `chart_type`, merged over its ApexCharts defaults."
  @callback defaults(chart_type :: atom()) :: map()

  @builtin %{apexcharts: EexCharts.Style.ApexCharts, chartjs: EexCharts.Style.ChartJS}

  @doc "The application-wide default style (`config :eexcharts, style: ...`)."
  def default, do: Application.get_env(:eexcharts, :style, :apexcharts)

  @doc "Resolves a built-in style name or a custom module to its module."
  def module(name) when is_map_key(@builtin, name), do: Map.fetch!(@builtin, name)

  def module(mod) when is_atom(mod) do
    Code.ensure_loaded(mod)

    if function_exported?(mod, :defaults, 1) do
      mod
    else
      raise ArgumentError,
            "unknown chart style #{inspect(mod)}: expected one of " <>
              "#{inspect(Map.keys(@builtin))} or a module implementing EexCharts.Style"
    end
  end

  @doc "The overrides `style` contributes for `chart_type`."
  def defaults(style, chart_type), do: module(style).defaults(chart_type)
end

defmodule EexCharts.Style.ApexCharts do
  @moduledoc """
  The default style. `EexCharts.Config.defaults/0` already is ApexCharts
  v4.7.0, so it contributes nothing.
  """
  @behaviour EexCharts.Style

  @impl true
  def defaults(_chart_type), do: %{}
end
