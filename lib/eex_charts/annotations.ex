defmodule EexCharts.Annotations do
  @moduledoc """
  Chart annotations (x-axis bands/lines, y-axis lines, labeled points),
  modeled on ApexCharts' `annotations` option. (Implementation pending.)

  Config shape:

      annotations: %{
        yaxis: [%{y: 40, border_color: "#00E396", label: %{text: "target"}}],
        xaxis: [%{x: "Mar", x2: "May", fill_color: "#B3F7CA", label: %{text: "spring"}}],
        points: [%{x: "Apr", y: 55, marker: %{size: 6}, label: %{text: "peak"}}]
      }
  """

  alias EexCharts.Layout

  @doc "Renders all configured annotations into the cartesian grid."
  def render(_cfg, %Layout{} = _layout), do: []
end
