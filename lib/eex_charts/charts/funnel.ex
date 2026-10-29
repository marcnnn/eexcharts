defmodule EexCharts.Charts.Funnel do
  @moduledoc """
  Funnel and pyramid charts: horizontal bars centred on the plot's vertical
  midline, ported from ApexCharts v4.7.0 `plotOptions.bar.isFunnel`.

  ## Usage

      EexCharts.chart(id: "f", type: :funnel,
        series: [%{name: "Visitors", data: [1380, 1100, 990, 880, 740]}],
        categories: ~w(Visit Signup Trial Paid Renewed))

  `type: :funnel` and `type: :pyramid` are shorthands for a `:bar` chart with
  `plot_options.bar.is_funnel: true` (the v4.7.0 spelling, which also works on
  its own). Each bar is `value` wide on a `0..max` value scale and is centred,
  so equal values give equal widths and the widest stage spans the plot.

    * `:funnel` draws the data top to bottom in the order given.
    * `:pyramid` reverses the order, so the first data point sits at the
      bottom (pass the widest stage first to get a pyramid).

  The shorthands keep the category labels on the left; plain
  `is_funnel: true` hides every axis like ApexCharts does (put the stage name
  in a data label formatter instead). Grid and value axis are hidden either
  way; the defaults sit under your options, so any of them can be turned back
  on.

  ## Options

    * `plot_options.bar.is_funnel` (`false`) — centre horizontal bars.
    * `plot_options.bar.is_funnel_3d` (`true`) — fill the gap between
      consecutive stages with a trapezoid in a 50% lighter shade of the bar
      colour, so the stages read as one tapering shape.
    * `plot_options.bar.bar_height` (`"70%"`) — stage thickness; the
      remainder of each slot is the gap the connector fills.
  """

  import EexCharts.SVG

  alias EexCharts.{Color, Layout}

  @doc "Config defaults applied when `is_funnel` is on (ApexCharts `Defaults.funnel()`)."
  def defaults do
    %{
      plot_options: %{
        bar: %{
          horizontal: true,
          border_radius_application: :around,
          border_radius: 0,
          data_labels: %{position: :center}
        }
      },
      grid: %{show: false, padding: %{left: 0, right: 0}},
      xaxis: %{
        labels: %{show: false},
        axis_border: %{show: false},
        axis_ticks: %{show: false}
      },
      yaxis: %{show: false, labels: %{show: false}, title: %{text: nil}}
    }
  end

  @doc "Extra defaults for the `:funnel` / `:pyramid` shorthands: stage names on the left."
  def alias_defaults do
    %{
      plot_options: %{bar: %{is_funnel: true}},
      grid: %{padding: %{left: 12}},
      xaxis: %{labels: %{show: true}},
      yaxis: %{labels: %{show: true}}
    }
  end

  @doc "Reverses data and categories so the first point is the pyramid's base."
  def reverse(params) do
    params
    |> Map.update(:series, nil, fn
      series when is_list(series) ->
        Enum.map(series, fn
          %{data: data} = s when is_list(data) -> %{s | data: Enum.reverse(data)}
          other -> other
        end)

      other ->
        other
    end)
    |> Map.update(:categories, nil, &reverse_list/1)
    |> Map.update(:options, %{}, fn opts ->
      case opts do
        %{xaxis: %{categories: cats} = x} ->
          %{opts | xaxis: %{x | categories: reverse_list(cats)}}

        _ ->
          opts
      end
    end)
  end

  defp reverse_list(list) when is_list(list), do: Enum.reverse(list)
  defp reverse_list(other), do: other

  @doc """
  Re-centres horizontal bar rectangles on the plot's midline when `is_funnel`
  is on; returns them untouched otherwise.
  """
  def center(rects, cfg, %Layout{} = l) do
    if funnel?(cfg) do
      mid = l.grid_x + l.grid_w / 2
      Enum.map(rects, fn r -> %{r | x: mid - r.w / 2, positive: true} end)
    else
      rects
    end
  end

  @doc """
  The trapezoids joining consecutive stages of one series (`is_funnel_3d`):
  from the previous bar's bottom edge to the next bar's top edge.
  """
  def connectors(cfg, rects) do
    if funnel?(cfg) and cfg.plot_options.bar.is_funnel_3d do
      rects
      |> Enum.sort_by(& &1.index)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [prev, curr] ->
        bottom = prev.y + prev.h

        el("path", %{
          class: "eexcharts-funnel-connector",
          d: [
            move(prev.x, bottom),
            line(prev.x + prev.w, bottom),
            line(curr.x + curr.w, curr.y),
            line(curr.x, curr.y),
            close()
          ],
          fill: Color.shade(curr.color, 0.5),
          fill_opacity: 1,
          stroke: "none"
        })
      end)
    else
      []
    end
  end

  defp funnel?(cfg), do: cfg.plot_options.bar[:is_funnel] == true
end
