defmodule EexCharts.Charts.Heatmap do
  @moduledoc """
  Heatmap chart. (Implementation pending.)

  Series are rows (name = y label); `data` holds one number per x category.
  Owns its full SVG assembly: `render_chart/3` returns the complete container
  (svg + tooltips).
  """

  @doc "Renders the complete heatmap container."
  def render_chart(_cfg, _params, _id) do
    raise ArgumentError, "heatmap charts are not implemented yet"
  end
end
