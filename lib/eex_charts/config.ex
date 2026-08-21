defmodule EexCharts.Config do
  @moduledoc """
  Chart configuration: defaults ported from ApexCharts.js v4.7.0
  (`src/modules/settings/Options.js` and `Defaults.js`), expressed as nested
  maps with snake_case atom keys.

  `build/2` merges (in order): base defaults, per-chart-type overrides, and
  user options — the same layering ApexCharts applies.
  """

  @palette ["#008FFB", "#00E396", "#FEB019", "#FF4560", "#775DD0"]

  @doc "The default color palette (ApexCharts `palette1`)."
  def palette, do: @palette

  @doc """
  Builds the effective config for a chart type (`:line`, `:area`, `:bar`,
  `:pie`, `:donut`) by deep-merging user options over the defaults.
  """
  def build(type, opts \\ %{}) when is_map(opts) do
    defaults()
    |> deep_merge(type_defaults(type))
    |> deep_merge(opts)
    |> Map.update!(:chart, &Map.put(&1, :type, type))
    |> EexCharts.Theme.apply(opts)
  end

  @doc "Deep-merges two nested maps; values in `override` win."
  def deep_merge(base, override) do
    Map.merge(base, override, fn
      _k, %{} = a, %{} = b -> deep_merge(a, b)
      _k, _a, b -> b
    end)
  end

  @doc "ApexCharts base defaults (subset supported by EexCharts)."
  def defaults do
    %{
      chart: %{
        type: :line,
        width: 600,
        height: 350,
        font_family: "Helvetica, Arial, sans-serif",
        fore_color: "#373d3f",
        background: "",
        stacked: false,
        offset_x: 0,
        offset_y: 0
      },
      colors: nil,
      theme: %{mode: :light, palette: nil, monochrome: %{enabled: false}},
      annotations: %{xaxis: [], yaxis: [], points: []},
      title: %{
        text: nil,
        align: :left,
        margin: 10,
        offset_x: 0,
        offset_y: 0,
        style: %{font_size: 14, font_weight: 900, color: nil}
      },
      stroke: %{
        show: true,
        curve: :smooth,
        line_cap: :butt,
        width: 2,
        dash_array: 0,
        colors: nil
      },
      markers: %{
        size: 0,
        colors: nil,
        stroke_colors: "#fff",
        stroke_width: 2,
        stroke_opacity: 0.9,
        fill_opacity: 1,
        # `:circle`, `:square`, `:triangle` or `:diamond`; a list assigns one
        # shape per series (ApexCharts `markers.shape` array form).
        shape: :circle,
        hover: %{size: nil, size_offset: 3}
      },
      data_labels: %{
        enabled: true,
        offset_x: 0,
        offset_y: 0,
        # Nudge applied to point labels on value x-axes, matching ApexCharts'
        # `drawDataLabel({strokeWidth = 2})`.
        stroke_width: 2,
        formatter: nil,
        style: %{font_size: 12, font_weight: 600, colors: nil},
        background: %{
          enabled: true,
          fore_color: "#fff",
          border_radius: 2,
          padding: 4,
          opacity: 0.9,
          border_width: 1,
          border_color: "#fff"
        }
      },
      grid: %{
        show: true,
        border_color: "#e0e0e0",
        border_width: 1,
        stroke_dash_array: 0,
        xaxis_lines: false,
        yaxis_lines: true,
        padding: %{top: 0, right: 10, bottom: 0, left: 12},
        # Plot-area background painted behind the series. `fill` takes any SVG
        # paint value; `gradient` describes a CSS-`linear-gradient`-equivalent
        # ramp across the plot rectangle (`angle` in CSS degrees — 0 points up,
        # measured clockwise — and `stops` as `{offset_percent, color}`).
        background: %{fill: nil, opacity: 1, gradient: nil}
      },
      xaxis: %{
        type: :category,
        categories: [],
        tick_placement: :on,
        min: nil,
        max: nil,
        range: nil,
        tick_amount: nil,
        step_size: nil,
        title: %{text: nil, offset_x: 0, offset_y: 0, style: %{font_size: 11, font_weight: 900, color: nil}},
        labels: %{
          show: true,
          formatter: nil,
          datetime_formatter: %{},
          rotate: 0,
          rotate_always: false,
          hide_overlapping_labels: true,
          offset_x: 0,
          offset_y: 0,
          style: %{colors: nil, font_size: 12, font_weight: 400}
        },
        axis_border: %{show: true, color: "#e0e0e0", height: 1},
        axis_ticks: %{show: true, color: "#e0e0e0", height: 6}
      },
      yaxis: %{
        show: true,
        opposite: false,
        series_name: nil,
        logarithmic: false,
        log_base: 10,
        min: nil,
        max: nil,
        tick_amount: nil,
        step_size: nil,
        force_nice_scale: false,
        decimals_in_float: nil,
        formatter: nil,
        title: %{text: nil, style: %{font_size: 11, font_weight: 900, color: nil}},
        labels: %{
          show: true,
          min_width: 0,
          max_width: 160,
          style: %{colors: nil, font_size: 11, font_weight: 400}
        }
      },
      legend: %{
        show: true,
        show_for_single_series: false,
        position: :bottom,
        horizontal_align: :center,
        font_size: 12,
        font_weight: 400,
        # `width` caps the row-wrapping width (ApexCharts `legend.width`);
        # `nil` wraps at the chart width.
        width: nil,
        offset_x: 0,
        offset_y: 0,
        markers: %{size: 6, shape: :circle, stroke_width: 0, stroke_color: nil, radius: nil},
        item_margin: %{horizontal: 5, vertical: 4},
        labels: %{colors: nil, use_series_colors: false}
      },
      tooltip: %{
        enabled: true,
        theme: :light,
        shared: true,
        intersect: false,
        follow_cursor: false,
        style: %{font_size: 12},
        x_formatter: nil,
        y_formatter: nil
      },
      fill: %{
        type: :solid,
        opacity: 0.85,
        gradient: %{
          shade: :dark,
          type: :horizontal,
          shade_intensity: 0.5,
          opacity_from: 1,
          opacity_to: 1,
          stops: [0, 50, 100]
        }
      },
      plot_options: %{
        bar: %{
          horizontal: false,
          column_width: "70%",
          bar_height: "70%",
          border_radius: 0,
          border_radius_application: :around,
          distributed: false,
          data_labels: %{position: :top}
        },
        candlestick: %{
          colors: %{upward: "#00B746", downward: "#EF403C"},
          wick: %{use_fill_color: true}
        },
        box_plot: %{
          colors: %{upper: "#00E396", lower: "#008FFB"}
        },
        bubble: %{
          min_bubble_radius: nil,
          max_bubble_radius: nil,
          z_scaling: true
        },
        heatmap: %{
          radius: 2,
          shade_intensity: 0.5,
          distributed: false,
          color_scale: %{ranges: [], min: nil, max: nil}
        },
        treemap: %{
          distributed: false,
          enable_shades: true,
          shade_intensity: 0.5,
          border_radius: 4
        },
        radar: %{
          size: nil,
          offset_x: 0,
          offset_y: 0,
          polygons: %{
            stroke_colors: "#e8e8e8",
            stroke_width: 1,
            connector_colors: "#e8e8e8",
            fill: %{colors: nil}
          }
        },
        radial_bar: %{
          start_angle: 0,
          end_angle: 360,
          offset_x: 0,
          offset_y: 0,
          hollow: %{size: "50%", margin: 5, background: "transparent"},
          track: %{show: true, background: "#f2f2f2", stroke_width: "97%", margin: 5, opacity: 1},
          data_labels: %{
            show: true,
            name: %{show: true, font_size: 16, font_weight: 600, color: nil, offset_y: 0},
            value: %{
              show: true,
              font_size: 14,
              font_weight: 400,
              color: nil,
              offset_y: 16,
              formatter: nil
            },
            total: %{
              show: false,
              label: "Total",
              font_size: 16,
              font_weight: 600,
              color: nil,
              formatter: nil
            }
          }
        },
        polar_area: %{
          rings: %{stroke_width: 1, stroke_color: "#e8e8e8"},
          spokes: %{stroke_width: 1, connector_colors: "#e8e8e8"}
        },
        pie: %{
          start_angle: 0,
          end_angle: 360,
          expand_on_click: true,
          offset_x: 0,
          offset_y: 0,
          custom_scale: 1,
          data_labels: %{offset: 0, min_angle_to_show_label: 10},
          donut: %{
            size: "65%",
            background: "transparent",
            labels: %{
              show: false,
              name: %{show: true, font_size: 16, font_weight: 600, color: nil, offset_y: -10},
              value: %{
                show: true,
                font_size: 20,
                font_weight: 400,
                color: nil,
                offset_y: 10,
                formatter: nil
              },
              total: %{
                show: false,
                show_always: false,
                label: "Total",
                font_size: 16,
                font_weight: 400,
                color: nil,
                formatter: nil
              }
            }
          }
        }
      }
    }
  end

  # Per-chart-type overrides, ported from ApexCharts `Defaults.js`.
  defp type_defaults(:line) do
    %{
      data_labels: %{enabled: false},
      stroke: %{width: 5, curve: :straight},
      markers: %{size: 0, hover: %{size_offset: 6}}
    }
  end

  defp type_defaults(:area) do
    %{
      data_labels: %{enabled: false},
      stroke: %{width: 4, curve: :smooth},
      fill: %{
        type: :gradient,
        gradient: %{
          shade: :light,
          type: :vertical,
          inverse_colors: false,
          opacity_from: 0.65,
          opacity_to: 0.5,
          stops: [0, 100, 100]
        }
      },
      markers: %{size: 0, hover: %{size_offset: 6}},
      tooltip: %{follow_cursor: false}
    }
  end

  defp type_defaults(:bar) do
    %{
      chart: %{stacked: false},
      plot_options: %{bar: %{data_labels: %{position: :center}}},
      data_labels: %{
        style: %{colors: ["#fff"]},
        background: %{enabled: false}
      },
      stroke: %{width: 0, line_cap: :square},
      fill: %{opacity: 0.85},
      legend: %{markers: %{shape: :square}},
      tooltip: %{shared: false, intersect: true},
      xaxis: %{tick_placement: :between}
    }
  end

  defp type_defaults(pie) when pie in [:pie, :donut] do
    %{
      data_labels: %{
        enabled: true,
        formatter: :percent,
        style: %{colors: ["#fff"]}
      },
      stroke: %{colors: ["#fff"], width: 2},
      fill: %{opacity: 1},
      tooltip: %{theme: :dark},
      legend: %{position: :right}
    }
  end

  defp type_defaults(:scatter) do
    %{
      data_labels: %{enabled: false},
      stroke: %{width: 0},
      markers: %{size: 6, stroke_width: 1, hover: %{size_offset: 2}},
      tooltip: %{shared: false, intersect: true},
      fill: %{opacity: 1}
    }
  end

  defp type_defaults(:bubble) do
    %{
      data_labels: %{enabled: false, style: %{colors: ["#fff"]}},
      stroke: %{width: 0},
      tooltip: %{shared: false, intersect: true},
      fill: %{opacity: 0.7}
    }
  end

  defp type_defaults(:candlestick) do
    %{
      data_labels: %{enabled: false},
      stroke: %{width: 1, colors: ["#333"]},
      fill: %{opacity: 1},
      tooltip: %{shared: false, intersect: true},
      xaxis: %{tick_placement: :between}
    }
  end

  defp type_defaults(:box_plot) do
    %{
      data_labels: %{enabled: false},
      stroke: %{width: 1, colors: ["#24292e"]},
      fill: %{opacity: 1},
      tooltip: %{shared: false, intersect: true},
      xaxis: %{tick_placement: :between}
    }
  end

  defp type_defaults(:range_bar) do
    %{
      chart: %{stacked: false},
      data_labels: %{enabled: false, style: %{colors: ["#fff"]}, background: %{enabled: false}},
      stroke: %{width: 0, line_cap: :square},
      fill: %{opacity: 0.85},
      legend: %{markers: %{shape: :square}},
      tooltip: %{shared: false, intersect: true},
      xaxis: %{tick_placement: :between}
    }
  end

  defp type_defaults(:radar) do
    %{
      data_labels: %{enabled: false},
      stroke: %{width: 2, curve: :straight},
      markers: %{size: 5, stroke_width: 1, hover: %{size_offset: 2}},
      fill: %{opacity: 0.2},
      grid: %{show: false},
      xaxis: %{labels: %{style: %{colors: ["#a8a8a8"], font_size: 11}}}
    }
  end

  defp type_defaults(:radial_bar) do
    %{
      data_labels: %{enabled: false},
      stroke: %{line_cap: :butt},
      fill: %{opacity: 1},
      tooltip: %{enabled: false},
      legend: %{show: false},
      grid: %{show: false}
    }
  end

  defp type_defaults(:heatmap) do
    %{
      data_labels: %{enabled: false, style: %{colors: ["#fff"]}},
      stroke: %{colors: ["#fff"], width: 2},
      fill: %{opacity: 1},
      legend: %{position: :top},
      grid: %{yaxis_lines: false}
    }
  end

  defp type_defaults(:treemap) do
    %{
      data_labels: %{
        enabled: true,
        style: %{font_size: 14, font_weight: 600, colors: ["#fff"]},
        background: %{enabled: false}
      },
      stroke: %{colors: ["#fff"], width: 2},
      fill: %{opacity: 1},
      legend: %{show: false},
      grid: %{show: false},
      tooltip: %{shared: false, intersect: true}
    }
  end

  defp type_defaults(:polar_area) do
    %{
      data_labels: %{enabled: false},
      stroke: %{colors: ["#fff"], width: 1},
      fill: %{opacity: 0.7},
      tooltip: %{theme: :dark},
      legend: %{position: :right}
    }
  end

  defp type_defaults(_), do: %{}

  @doc """
  Normalizes `cfg.yaxis` into a list of fully-populated axis maps.

  ApexCharts allows `yaxis` to be a single map or a list of axis maps; each
  raw axis is deep-merged over the default y-axis so every key is present.
  """
  def yaxes(cfg) do
    base = defaults().yaxis

    case cfg.yaxis do
      list when is_list(list) -> Enum.map(list, &deep_merge(base, &1))
      %{} = map -> [deep_merge(base, map)]
    end
  end

  @doc "The primary (first) y-axis map — the one that owns the grid lines."
  def yaxis(cfg), do: hd(yaxes(cfg))

  @doc "Resolves the color list, falling back to the default palette."
  def colors(cfg), do: cfg[:colors] || @palette

  @doc "Color for series/slice `i`, cycling through the configured palette."
  def color_at(cfg, i) do
    colors = colors(cfg)
    Enum.at(colors, rem(i, length(colors)))
  end
end
