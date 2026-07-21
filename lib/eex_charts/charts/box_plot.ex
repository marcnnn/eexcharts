defmodule EexCharts.Charts.BoxPlot do
  @moduledoc """
  Box plot series rendering. (Implementation pending.)

  Data shape: `[[min, q1, median, q3, max], ...]` or
  `[%{x: label, y: [min, q1, median, q3, max]}, ...]`.
  """

  @doc "Renders box plot series into the cartesian grid."
  def render(_cfg, _series, _layout, _opts) do
    raise ArgumentError, "box plot charts are not implemented yet"
  end

  @doc "Returns `{y_min, y_max}` across all five-number summaries."
  def data_range(_series) do
    raise ArgumentError, "box plot charts are not implemented yet"
  end

  @doc "Formats one box data point for the tooltip."
  def tooltip_value(_cfg, _v) do
    raise ArgumentError, "box plot charts are not implemented yet"
  end
end
