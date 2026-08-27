defmodule EexChartsStorybook.Root do
  @moduledoc """
  Sidebar index for the chart catalog.

  Without this, phoenix_storybook derives each entry's label from its file name
  and lists them alphabetically. Here we give the chart families a reading
  order (cartesian first, then circular, then the specialised types) and the
  labels people actually search for.
  """
  use PhoenixStorybook.Index

  def folder_open?, do: true

  def entry("line"), do: [name: "Line", index: 0]
  def entry("area"), do: [name: "Area", index: 1]
  def entry("bar"), do: [name: "Bar & column", index: 2]
  def entry("range_bar"), do: [name: "Range bar", index: 3]
  def entry("scatter"), do: [name: "Scatter & bubble", index: 4]
  def entry("pie"), do: [name: "Pie & donut", index: 5]
  def entry("polar_area"), do: [name: "Polar area", index: 6]
  def entry("radial_bar"), do: [name: "Radial bar", index: 7]
  def entry("radar"), do: [name: "Radar", index: 8]
  def entry("heatmap"), do: [name: "Heatmap", index: 9]
  def entry("treemap"), do: [name: "Treemap", index: 10]
  def entry("candlestick"), do: [name: "Candlestick", index: 11]
  def entry("box_plot"), do: [name: "Box plot", index: 12]
end
