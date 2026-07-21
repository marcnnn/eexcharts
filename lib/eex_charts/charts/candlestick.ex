defmodule EexCharts.Charts.Candlestick do
  @moduledoc """
  Candlestick series rendering. (Implementation pending.)

  Data shape: `[[open, high, low, close], ...]` or `[%{x: label, y: [o, h, l, c]}, ...]`.
  """

  @doc "Renders candlestick series into the cartesian grid."
  def render(_cfg, _series, _layout, _opts) do
    raise ArgumentError, "candlestick charts are not implemented yet"
  end

  @doc "Returns `{y_min, y_max}` across all OHLC values."
  def data_range(_series) do
    raise ArgumentError, "candlestick charts are not implemented yet"
  end

  @doc "Formats one OHLC data point for the tooltip."
  def tooltip_value(_cfg, _v) do
    raise ArgumentError, "candlestick charts are not implemented yet"
  end
end
