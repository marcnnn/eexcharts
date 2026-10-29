defmodule EexCharts.Config do
  @moduledoc """
  Chart configuration: defaults ported from ApexCharts.js v4.7.0
  (`src/modules/settings/Options.js` and `Defaults.js`), expressed as nested
  maps with snake_case atom keys.

  `build/2` merges (in order): base defaults, per-chart-type overrides, and
  user options — the same layering ApexCharts applies. A `style` other than
  the default (see `EexCharts.Style`) slots its overrides in just before the
  user options.
  """

  @palette ["#008FFB", "#00E396", "#FEB019", "#FF4560", "#775DD0"]

  @doc "The default color palette (ApexCharts `palette1`)."
  def palette, do: @palette

  @doc """
  The application-wide default for `theme.mode`.

  A Phoenix app with daisyUI set up (the default since Phoenix 1.8) opts every
  chart into daisyUI theming with one line in `config/config.exs`:

      config :eexcharts, theme_mode: :daisy

  Per-chart `%{theme: %{mode: ...}}` options still win.
  """
  def theme_mode, do: Application.get_env(:eexcharts, :theme_mode, :light)

  @doc """
  Builds the effective config for a chart type (`:line`, `:area`, `:bar`,
  `:pie`, `:donut`) by deep-merging user options over the defaults.
  """
  def build(type, opts \\ %{}) when is_map(opts) do
    style = opts[:style] || EexCharts.Style.default()

    defaults()
    |> deep_merge(type_defaults(type))
    |> deep_merge(EexCharts.Style.defaults(style, type))
    |> deep_merge(EexCharts.Charts.BarFamily.option_defaults(type, opts))
    |> deep_merge(sparkline_defaults(opts))
    |> deep_merge(opts)
    |> hide_sparkline_y_axis()
    |> Map.put(:style, style)
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
        # `:auto` caps the rendered chart at `width` px; `false` lets it scale
        # to fill a wider container (the SVG keeps its aspect ratio).
        max_width: :auto,
        # Render the SVG at exactly `width` x `height` CSS pixels instead of
        # letting it stretch to the container. One SVG unit is then one device
        # pixel, which matters when the container width is fractional: a
        # viewBox of 1242 stretched into a 1242.4px box shifts the right-hand
        # side of the chart by half a pixel and everything there re-antialiases.
        pixel_perfect: false,
        # Extra height reserved below the chart, matching ApexCharts'
        # `chart.parentHeightOffset` (it sets the host element's `min-height`
        # to `height + 15`). Only applied to fixed-size charts.
        parent_height_offset: 15,
        font_family: "Helvetica, Arial, sans-serif",
        # Advance-width table used to size text server-side: `:arial`,
        # `:dejavu`, or a `%{codepoint => em}` map (see EexCharts.FontMetrics).
        # It has to match the font the browser actually picks, or every gutter
        # the width feeds into drifts.
        font_metrics: :arial,
        fore_color: "#373d3f",
        background: "",
        stacked: false,
        # `"normal"` or `"100%"` (ApexCharts `chart.stackType`); see
        # EexCharts.Stacking for line/area stacking.
        stack_type: "normal",
        # Strip axes, grid, legend, labels and padding so the chart fits a
        # table cell (ApexCharts `chart.sparkline`); see `sparkline?/1`.
        sparkline: %{enabled: false},
        offset_x: 0,
        offset_y: 0
      },
      colors: nil,
      theme: %{mode: theme_mode(), palette: nil, monochrome: %{enabled: false}},
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
        # A color, a per-series list, or `nil` for each series' own color.
        stroke_colors: "#fff",
        stroke_width: 2,
        stroke_opacity: 0.9,
        fill_opacity: 1,
        # `:circle`, `:square`, `:triangle` or `:diamond`; a list assigns one
        # shape per series (ApexCharts `markers.shape` array form).
        shape: :circle,
        # Per-point overrides (ApexCharts `markers.discrete`); see
        # `EexCharts.Charts.Scatter.render/5`.
        discrete: [],
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
        # Drop labels whose estimated boxes collide, balanced across series
        # (see `EexCharts.DataLabels`).
        hide_overlapping: false,
        style: %{
          font_size: 12,
          font_weight: 600,
          colors: nil,
          font_family: nil,
          font_metrics: nil
        },
        background: %{
          enabled: true,
          fore_color: "#fff",
          border_radius: 2,
          padding: 4,
          # Vertical padding; ApexCharts derives it as `padding / 2`, but the
          # box it pads comes from a real `getBBox`, so a chart whose text
          # metrics are estimated may need to say what it wants.
          padding_y: nil,
          # Nudge for the box alone. Our text box is estimated from font
          # metrics while ApexCharts measures the rendered glyphs, so the two
          # can disagree about where the text sits inside its own box; this
          # re-centres the pill without moving the label.
          offset_y: 0,
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
        title: %{
          text: nil,
          offset_x: 0,
          offset_y: 0,
          style: %{
            font_size: 12,
            font_weight: 900,
            color: nil,
            font_family: nil,
            font_metrics: nil
          }
        },
        labels: %{
          show: true,
          formatter: nil,
          datetime_formatter: %{},
          rotate: 0,
          rotate_always: false,
          hide_overlapping_labels: true,
          # Ceiling on the vertical space rotated labels may claim, matching
          # ApexCharts' `xaxis.labels.maxHeight`. Without it a long rotated
          # category label eats most of the plot.
          max_height: 120,
          offset_x: 0,
          offset_y: 0,
          style: %{
            colors: nil,
            font_size: 12,
            font_weight: 400,
            font_family: nil,
            font_metrics: nil
          }
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
        title: %{
          text: nil,
          offset_x: 0,
          offset_y: 0,
          style: %{
            font_size: 11,
            font_weight: 900,
            color: nil,
            font_family: nil,
            font_metrics: nil
          }
        },
        labels: %{
          show: true,
          min_width: 0,
          max_width: 160,
          offset_x: 0,
          offset_y: 0,
          style: %{
            colors: nil,
            font_size: 11,
            font_weight: 400,
            font_family: nil,
            font_metrics: nil
          }
        }
      },
      legend: %{
        show: true,
        show_for_single_series: false,
        position: :bottom,
        horizontal_align: :center,
        font_size: 12,
        font_weight: 400,
        font_family: nil,
        font_metrics: nil,
        # `width` caps the row-wrapping width (ApexCharts `legend.width`);
        # `nil` wraps at the chart width.
        width: nil,
        offset_x: 0,
        offset_y: 0,
        # Render the legend as HTML in a `foreignObject` instead of SVG text.
        # ApexCharts' legend is an HTML flex overlay, so its item widths and
        # row pitch come from the browser's own layout; ours can only estimate
        # them from font metrics. Opting in hands the same job to the same
        # engine and the two agree exactly.
        html: false,
        # `width`/`height` stretch a `:square` marker into a box (`nil` keeps
        # it `2 * size` square); a `nil` `stroke_color` is the series color.
        markers: %{
          size: 6,
          shape: :circle,
          width: nil,
          height: nil,
          fill_opacity: 1,
          stroke_width: 0,
          stroke_color: nil,
          radius: nil,
          # Per-item marker colours (ApexCharts `legend.markers.fillColors`).
          fill_colors: nil
        },
        # Legend entries that replace the series names (ApexCharts
        # `legend.customLegendItems`); toggling is off while they are set.
        custom_legend_items: [],
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
          data_labels: %{position: :top},
          # ApexCharts v4.7.0 funnel / dumbbell switches (see
          # `EexCharts.Charts.Funnel` and `EexCharts.Charts.Dumbbell`).
          is_funnel: false,
          is_funnel_3d: true,
          is_dumbbell: false,
          dumbbell_colors: nil
        },
        candlestick: %{
          colors: %{upward: "#00B746", downward: "#EF403C"},
          wick: %{use_fill_color: true}
        },
        box_plot: %{
          colors: %{upper: "#00E396", lower: "#008FFB"},
          # Raw-observation boxes: Tukey fence multiple (see EexCharts.Stats).
          whisker: 1.5
        },
        # See EexCharts.Charts.Histogram.
        histogram: %{
          bins: :auto,
          bin_width: nil,
          normalize: :count,
          cumulative: false,
          overlay_opacity: 0.5
        },
        # See EexCharts.Charts.Violin.
        violin: %{
          bandwidth: :silverman,
          cut: 2,
          points: 64,
          scale: :width,
          inner: :box,
          raincloud: false,
          point_size: 2.5
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
          border_radius: 4,
          # Nested treemaps (nodes with `children`): gap between a group's
          # frame and its children, and the name band at the top of a group.
          group_padding: 3,
          group_header: %{show: true, font_size: 12, font_weight: 600, color: "#fff"}
        },
        sunburst: %{
          start_angle: 0,
          end_angle: 360,
          offset_x: 0,
          offset_y: 0,
          hole_size: "25%",
          shade_intensity: 0.5,
          labels: %{orientation: :auto, padding: 4},
          total: %{show: true, label: "Total", formatter: nil}
        },
        unit: %{
          layout: :grid,
          per_unit: 1,
          max_units: 2000,
          # `nil`: :square for grid and parliament, :circle for the beeswarm.
          shape: nil,
          size: nil,
          gap: 2,
          radius: nil,
          rows: nil,
          columns: nil,
          fill_order: :row,
          parliament: %{inner_radius: 0.4, rows: nil, show_total: true}
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
          # Target markers per series (see EexCharts.Charts.RadialBar).
          targets: [],
          target: %{color: nil, width: 3, overhang: 3},
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
        gauge: %{
          start_angle: -90,
          end_angle: 90,
          min: 0,
          max: 100,
          offset_x: 0,
          offset_y: 0,
          thickness: "18%",
          track: %{show: true, background: "#f2f2f2"},
          value_arc: %{show: true, color: nil},
          bands: [],
          band_gap: 2,
          ticks: %{
            show: true,
            amount: 10,
            length: 8,
            width: 1,
            color: nil,
            offset: 4,
            minor: %{amount: 0, length: 4}
          },
          tick_labels: %{show: true, font_size: 11, color: nil, offset: 4, formatter: nil},
          needle: %{show: true, length: "90%", width: 8, color: nil},
          hub: %{radius: 8, color: nil, stroke_color: "#fff", stroke_width: 2},
          data_labels: %{
            show: true,
            value: %{font_size: 24, font_weight: 600, color: nil, offset_y: 0, formatter: nil},
            name: %{show: true, font_size: 13, font_weight: 400, color: nil, offset_y: 0}
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
          # Rounded slice corners and a constant pixel gap between slices
          # (pie, donut, polar area); see EexCharts.Charts.Pie.
          border_radius: 0,
          spacing: 0,
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

  defp type_defaults(:histogram) do
    %{
      data_labels: %{enabled: false},
      stroke: %{width: 0},
      fill: %{opacity: 0.85},
      legend: %{markers: %{shape: :square}},
      tooltip: %{shared: false, intersect: true},
      xaxis: %{type: :numeric}
    }
  end

  defp type_defaults(:violin) do
    %{
      data_labels: %{enabled: false},
      stroke: %{width: 1},
      fill: %{opacity: 0.5},
      legend: %{markers: %{shape: :square}},
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

  defp type_defaults(:waterfall), do: EexCharts.Charts.Waterfall.type_defaults()

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

  defp type_defaults(:gauge) do
    %{
      data_labels: %{enabled: false},
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

  defp type_defaults(:sunburst) do
    %{
      # `colors: nil` (the default) picks white or dark text per arc.
      data_labels: %{enabled: true, style: %{font_size: 11}},
      stroke: %{colors: ["#fff"], width: 1},
      fill: %{opacity: 1},
      tooltip: %{theme: :dark},
      legend: %{position: :right}
    }
  end

  defp type_defaults(:unit) do
    %{
      data_labels: %{enabled: false},
      fill: %{opacity: 1},
      tooltip: %{shared: false, intersect: true}
    }
  end

  defp type_defaults(:waffle) do
    :unit
    |> type_defaults()
    |> deep_merge(%{plot_options: %{unit: %{layout: :grid, rows: 10, columns: 10}}})
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

  # Streamgraph: smooth stacked areas around a moving baseline (see
  # EexCharts.Stacking). The baseline makes the y-axis meaningless, so it and
  # the horizontal grid lines are off by default.
  defp type_defaults(:streamgraph) do
    %{
      chart: %{stacked: true},
      plot_options: %{streamgraph: %{offset: :wiggle, order: :none}},
      data_labels: %{enabled: false},
      stroke: %{width: 1, curve: :smooth, colors: ["#fff"]},
      fill: %{type: :solid, opacity: 0.9},
      markers: %{size: 0, hover: %{size_offset: 6}},
      yaxis: %{show: false},
      grid: %{yaxis_lines: false}
    }
  end

  defp type_defaults(_), do: %{}

  @doc """
  True when `chart.sparkline.enabled` is set.

  A sparkline (ApexCharts v4.7.0 `chart.sparkline`) is a bare chart. The
  options below become defaults under the user's own options, so each can be
  switched back on (`data_labels: %{enabled: true}`, a `grid.padding` that
  makes room for labels). As in ApexCharts, the first y-axis is hidden
  regardless.

    * `grid.show: false` and zero `grid.padding`
    * `legend.show: false`
    * `xaxis.labels`, `axis_border` and `axis_ticks` hidden
    * `data_labels.enabled: false`
    * `chart.parent_height_offset: 0`
    * `chart.pixel_perfect: true`: the SVG keeps its `width` x `height`
      instead of stretching to the container, and bar edges are snapped to
      whole pixels (`shape-rendering="crispEdges"`)

  `EexCharts.Layout` then gives the plot the whole SVG: no axis gutters, no
  label band, no legend space. Only the stroke and the markers keep a margin
  (half the stroke width at the top and bottom, the marker radius plus its
  stroke on every side), so lines, bar edges and markers are not clipped at
  sizes like 160 x 24. Annotations still render.

  Supported: `:line`, `:area`, `:bar` (also distributed and per-point
  `fill_color`), `:range_bar`, `:scatter`, `:pie`, `:donut`, `:radial_bar`.

      chart: %{width: 160, height: 24, sparkline: %{enabled: true}}
  """
  def sparkline?(cfg), do: get_in(cfg, [:chart, :sparkline, :enabled]) == true

  # ApexCharts `Defaults.sparkline()`, layered below the user's options.
  defp sparkline_defaults(opts) do
    if sparkline?(opts) do
      %{
        chart: %{parent_height_offset: 0, pixel_perfect: true},
        grid: %{show: false, padding: %{top: 0, right: 0, bottom: 0, left: 0}},
        legend: %{show: false},
        xaxis: %{
          labels: %{show: false},
          axis_border: %{show: false},
          axis_ticks: %{show: false}
        },
        data_labels: %{enabled: false}
      }
    else
      %{}
    end
  end

  # ApexCharts' `hideYAxis()` writes into the user's options, so the first
  # y-axis is hidden even when they ask for it.
  defp hide_sparkline_y_axis(cfg) do
    if sparkline?(cfg) do
      hide = &deep_merge(&1, %{show: false, labels: %{show: false}, title: %{text: nil}})

      case cfg.yaxis do
        [first | rest] -> %{cfg | yaxis: [hide.(first) | rest]}
        %{} = axis -> %{cfg | yaxis: hide.(axis)}
      end
    else
      cfg
    end
  end

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

  @doc """
  Resolves a per-series color option: ApexCharts accepts either one value or a
  list indexed by series (`markers.colors`, `markers.strokeColors`,
  `stroke.colors`…). A list handed straight to an SVG attribute would be
  concatenated into one nonsense value, so always read it through here.
  """
  def color_for(nil, _i), do: nil
  def color_for([], _i), do: nil
  def color_for(list, i) when is_list(list), do: Enum.at(list, rem(i, length(list)))
  def color_for(value, _i), do: value

  @doc "Color for series/slice `i`, cycling through the configured palette."
  def color_at(cfg, i) do
    colors = colors(cfg)
    Enum.at(colors, rem(i, length(colors)))
  end
end
