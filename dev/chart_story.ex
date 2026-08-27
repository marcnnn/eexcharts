defmodule Dev.ChartStory do
  @moduledoc """
  Shared body for the per-chart-type storybook stories in `dev/storybook/`.

  Each story file is one chart family and stays a three-liner:

      defmodule EexChartsStorybook.BoxPlot do
        use Dev.ChartStory, group: :box_plot
      end

  The macro renders the real `EexCharts.chart/1` component and turns every
  `Dev.ChartExamples` entry in that group into a variation — id from the
  example's frozen `:id` (so the storybook and the SVG goldens keep talking
  about the same chart), label from its `:title`.
  """

  @doc false
  defmacro __using__(opts) do
    group = Keyword.fetch!(opts, :group)

    quote do
      use PhoenixStorybook.Story, :component

      # Render the real library component, one variation per canonical example
      # so each chart lands in its own isolated iframe for element-scoped
      # screenshots.
      def function, do: &EexCharts.chart/1

      def variations do
        for example <- Dev.ChartExamples.by_group(unquote(group)) do
          %PhoenixStorybook.Stories.Variation{
            id: String.to_atom(example.id),
            description: example.title,
            attributes: Dev.ChartExamples.attributes(example)
          }
        end
      end
    end
  end
end
