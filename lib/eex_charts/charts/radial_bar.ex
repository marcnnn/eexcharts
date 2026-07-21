defmodule EexCharts.Charts.RadialBar do
  @moduledoc """
  Radial bar (circular gauge) chart. (Implementation pending.)

  Owns its full SVG assembly: `render_chart/3` returns the complete container
  (svg + tooltips), like `EexCharts.Renderer.render_cartesian/3` does for
  cartesian types.
  """

  @doc "Renders the complete radial bar chart container."
  def render_chart(_cfg, _params, _id) do
    raise ArgumentError, "radial bar charts are not implemented yet"
  end
end
