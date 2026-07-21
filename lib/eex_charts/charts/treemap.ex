defmodule EexCharts.Charts.Treemap do
  @moduledoc """
  Treemap chart. (Implementation pending.)

  Data shape: `[%{x: label, y: value}, ...]` per series.
  Owns its full SVG assembly: `render_chart/3` returns the complete container
  (svg + tooltips).
  """

  @doc "Renders the complete treemap container."
  def render_chart(_cfg, _params, _id) do
    raise ArgumentError, "treemap charts are not implemented yet"
  end
end
