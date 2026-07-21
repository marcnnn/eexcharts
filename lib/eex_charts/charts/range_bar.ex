defmodule EexCharts.Charts.RangeBar do
  @moduledoc """
  Range bar series rendering. (Implementation pending.)

  Data shape: `[[from, to], ...]` or `[%{x: label, y: [from, to]}, ...]`.
  """

  @doc "Renders range bar series into the cartesian grid."
  def render(_cfg, _series, _layout, _opts) do
    raise ArgumentError, "range bar charts are not implemented yet"
  end

  @doc "Returns `{y_min, y_max}` across all ranges."
  def data_range(_series) do
    raise ArgumentError, "range bar charts are not implemented yet"
  end

  @doc "Formats one range data point for the tooltip."
  def tooltip_value(_cfg, _v) do
    raise ArgumentError, "range bar charts are not implemented yet"
  end
end
