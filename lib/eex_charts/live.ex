defmodule EexCharts.Live do
  @moduledoc """
  A chart that lays itself out at the container's real pixel size.

  `EexCharts.chart/1` renders at whatever `width` / `height` you configure and
  scales to fit — fine when the chart has a fixed size, wrong when it is
  supposed to fill a responsive box. ApexCharts solves this by measuring the
  host element in the browser; server-side there is no DOM to measure, so this
  LiveComponent borrows the browser's: a small hook reports the container's
  `clientWidth` / `clientHeight` on mount and on resize, and the chart
  re-renders at exactly that size, one SVG unit per CSS pixel. Font sizes,
  stroke widths and marker radii then mean pixels, instead of being scaled by
  whatever ratio the container happened to have.

  Before the first measurement arrives (and with JS disabled entirely) it
  renders at the configured `width` / `height`, so there is always a chart.

      <.live_component
        module={EexCharts.Live}
        id="revenue"
        type={:area}
        series={@series}
        width={800}
        height={400}
        measure={:both}
      />

  `measure` is `:width` (height stays as configured — the common case for a
  chart with a fixed row height), `:both`, or `false` to opt out.

  Register the hook alongside the tooltip one:

      import EexCharts from "../../deps/eexcharts/priv/static/eexcharts"
      hooks: { EexCharts, EexChartsMeasure: EexCharts.Measure }
  """

  use Phoenix.LiveComponent

  @impl true
  def mount(socket) do
    {:ok, assign(socket, measured_width: nil, measured_height: nil)}
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:type, fn -> :line end)
     |> assign_new(:series, fn -> [] end)
     |> assign_new(:categories, fn -> nil end)
     |> assign_new(:labels, fn -> nil end)
     |> assign_new(:options, fn -> %{} end)
     |> assign_new(:width, fn -> nil end)
     |> assign_new(:height, fn -> nil end)
     |> assign_new(:measure, fn -> :width end)
     |> assign_new(:class, fn -> nil end)
     |> assign_new(:box_class, fn -> nil end)
     |> assign_new(:box_style, fn -> "width:100%;height:100%;" end)
     |> assign_new(:on_click, fn -> nil end)
     |> assign_new(:on_legend_click, fn -> nil end)
     |> assign_new(:hidden_series, fn -> [] end)
     |> assign_new(:push_hover, fn -> nil end)}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(:chart_width, chart_width(assigns))
      |> assign(:chart_height, chart_height(assigns))

    ~H"""
    <div
      id={"#{@id}-measure"}
      phx-hook="EexChartsMeasure"
      phx-target={@myself}
      data-measure={to_string(@measure)}
      class={@box_class}
      style={@box_style}
    >
      <EexCharts.chart
        id={@id}
        type={@type}
        series={@series}
        categories={@categories}
        labels={@labels}
        width={@chart_width}
        height={@chart_height}
        options={@options}
        on_click={@on_click}
        on_legend_click={@on_legend_click}
        hidden_series={@hidden_series}
        push_hover={@push_hover}
        class={@class}
      />
    </div>
    """
  end

  @impl true
  def handle_event("measured", %{"width" => w, "height" => h}, socket) do
    {:noreply,
     socket
     |> assign(:measured_width, positive(w))
     |> assign(:measured_height, positive(h))}
  end

  defp positive(v) when is_number(v) and v > 0, do: round(v)
  defp positive(_), do: nil

  defp chart_width(%{measure: false}), do: nil
  defp chart_width(assigns), do: assigns.measured_width || assigns.width

  defp chart_height(%{measure: :both} = assigns),
    do: assigns.measured_height || assigns.height

  defp chart_height(assigns), do: assigns.height
end
