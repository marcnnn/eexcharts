defmodule EexCharts.Charts.BarFamily do
  @moduledoc """
  Entry points that turn the bar-family shorthand types into the chart types
  that draw them, and the option-dependent defaults those need.

    * `:funnel` / `:pyramid` → `:bar` with `plot_options.bar.is_funnel`
      (`EexCharts.Charts.Funnel`)
    * `:dumbbell` → `:range_bar` with `plot_options.bar.is_dumbbell`
      (`EexCharts.Charts.Dumbbell`)
    * `:waterfall` stays its own type; its data is turned into floating
      ranges here (`EexCharts.Charts.Waterfall`)

  Shorthand defaults sit *under* the caller's options, so every one of them
  can be overridden.
  """

  alias EexCharts.Charts.{Dumbbell, Funnel, Waterfall}
  alias EexCharts.Config

  @doc "Maps a requested chart type and render params to the ones that draw it."
  def resolve(:funnel, params), do: {:bar, put_defaults(params, Funnel.alias_defaults())}

  def resolve(:pyramid, params) do
    {:bar, params |> Funnel.reverse() |> put_defaults(Funnel.alias_defaults())}
  end

  def resolve(:dumbbell, params) do
    {:range_bar, params |> with_x_categories() |> put_defaults(Dumbbell.alias_defaults())}
  end

  def resolve(:waterfall, params),
    do: {:waterfall, params |> with_x_categories() |> Waterfall.prepare()}

  def resolve(type, params), do: {type, params}

  @doc """
  Defaults that depend on the user's options rather than only the type, like
  ApexCharts' `Config.js` swapping in `defaults.funnel()` when `isFunnel` is
  set. Merged between the type defaults and the user options.
  """
  def option_defaults(:bar, opts) do
    if flag?(opts, :is_funnel), do: Funnel.defaults(), else: %{}
  end

  def option_defaults(:range_bar, opts) do
    if flag?(opts, :is_dumbbell), do: Dumbbell.defaults(), else: %{}
  end

  def option_defaults(_type, _opts), do: %{}

  @doc "Post-build adjustments that need the resolved config (dumbbell legend)."
  def finalize(
        %{chart: %{type: :range_bar}, plot_options: %{bar: %{is_dumbbell: true}}} = cfg,
        params
      ) do
    Dumbbell.legend_config(cfg, params[:series])
  end

  def finalize(cfg, _params), do: cfg

  defp flag?(opts, key) do
    case opts do
      %{plot_options: %{bar: %{^key => true}}} -> true
      _ -> false
    end
  end

  defp put_defaults(params, defaults) do
    Map.put(params, :options, Config.deep_merge(defaults, params[:options] || %{}))
  end

  # `%{x: label, ...}` points name their category; use those labels when the
  # caller gave no categories.
  defp with_x_categories(params) do
    given? =
      params[:categories] not in [nil, []] or
        match?(%{xaxis: %{categories: [_ | _]}}, params[:options] || %{})

    labels =
      case params[:series] do
        [%{data: [_ | _] = data} | _] ->
          if Enum.all?(data, &match?(%{x: _}, &1)), do: Enum.map(data, & &1.x)

        _ ->
          nil
      end

    if given? or labels == nil, do: params, else: Map.put(params, :categories, labels)
  end
end
