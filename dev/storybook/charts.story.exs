defmodule EexChartsStorybook.Charts do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  # Render the real library component, one variation per canonical example so
  # each chart lands in its own isolated iframe for element-scoped screenshots.
  def function, do: &EexCharts.chart/1

  def variations do
    for example <- Dev.ChartExamples.all() do
      %Variation{
        id: String.to_atom(example.id),
        description: example.title,
        attributes: Dev.ChartExamples.attributes(example)
      }
    end
  end
end
