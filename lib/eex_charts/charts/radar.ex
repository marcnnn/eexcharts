defmodule EexCharts.Charts.Radar do
  @moduledoc """
  Radar (spider) chart. (Implementation pending.)

  Owns its full SVG assembly: `render_chart/3` returns the complete container
  (svg + tooltips).
  """

  @doc "Renders the complete radar chart container."
  def render_chart(_cfg, _params, _id) do
    raise ArgumentError, "radar charts are not implemented yet"
  end
end
