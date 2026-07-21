defmodule EexCharts.Charts.Scatter do
  @moduledoc """
  Scatter and bubble series rendering. (Implementation pending.)

  Data shapes: scatter `[y, ...]` or `[[x, y], ...]`; bubble `[[x, y, z], ...]`.
  """

  @doc "Renders scatter/bubble series into the cartesian grid."
  def render(_cfg, _series, _layout, _id) do
    raise ArgumentError, "scatter/bubble charts are not implemented yet"
  end

  @doc "Returns `{y_min, y_max}` for the given series."
  def data_range(_series) do
    raise ArgumentError, "scatter/bubble charts are not implemented yet"
  end

  @doc "Formats one data point for the tooltip."
  def tooltip_value(_cfg, _v) do
    raise ArgumentError, "scatter/bubble charts are not implemented yet"
  end
end
