defmodule EexCharts.EndLabels do
  @moduledoc """
  Direct labels at the end of line and area series, in place of a legend.
  Own design; ApexCharts v4.7.0 has no equivalent.

  A series opts in with an `end_label` key: a string, or `true` for the
  series name. A series without one gets no label, so many faint background
  lines can sit behind a few labelled ones. Series hidden through the legend
  get no label either.

      EexCharts.render("p", :line, [
        %{name: "Group 1", data: [59, 67, 74], end_label: "74 · +15"},
        %{name: "Group 2", data: [61, 63, 64], end_label: true},
        %{name: "Row A", data: [55, 63, 71], opacity: 0.25}
      ], options: %{legend: %{show: false}, end_labels: %{enabled: true}})

  ## Options (`end_labels`)

    * `enabled` - `false` by default. Only when it is on does the plot reserve
      room at the right, so charts without end labels keep their layout.
    * `avoid_overlap` - `true` by default: labels that would overlap are
      pushed apart vertically (see below).
    * `offset_x` - gap in px between the last point and the label (default 8).
    * `min_gap` - extra px kept between two neighbouring labels (default 2).
    * `formatter` - `fn label, %{series_index:, series_name:, value:} -> text`
      (or arity 1, just the label); the result is the label's text.
    * `style` - `font_size`, `font_weight`, `font_family`, `font_metrics` and
      `colors` (one colour or a list indexed by series).

  Each label sits right of its series' last plotted point, vertically centred
  on it. Its colour is the series colour (`style.colors` overrides it). A hex
  series colour that is close to invisible on the page (a near-black series
  on a dark chart) falls back to a readable neutral via `Color.legible/3`;
  `var(...)` colours under the daisyUI theme are left alone, as they follow
  the active theme.

  ## Overlap avoidance

  Labels are sorted by their anchor's y and must keep a pitch of one text
  height plus `min_gap`. Subtracting `k * pitch` from the k-th label turns
  that into "the shifted positions never decrease", so the positions closest
  to the anchors (least squares) are the isotonic regression of the shifted
  anchors, solved exactly in one pass by the pool adjacent violators
  algorithm (Ayer et al., 1955). Clamping that result into the plot keeps it
  monotone, so every label also stays inside the plot vertically whenever
  the whole column fits. The result is deterministic and order-stable.
  """

  import EexCharts.SVG

  alias EexCharts.{Color, Config, Layout}

  # The page the labels sit on when `chart.background` is not a hex colour.
  @light_page "#fff"
  @dark_page "#343434"

  @doc """
  Adds the right-hand reserve the labels need to `cfg.end_labels.reserve`
  (px), read by `EexCharts.Layout`. Measured over all series, hidden ones
  included, so toggling a series does not resize the plot. Line and area
  charts only; `render/3` draws nothing without it.
  """
  def prepare(%{end_labels: %{enabled: true}, chart: %{type: type}} = cfg, series)
      when type in [:line, :area] do
    style = cfg.end_labels.style

    widest =
      series
      |> Enum.map(&text(cfg, &1, last_value(&1.data)))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&Layout.text_width(&1, style.font_size, Layout.metrics(cfg, style)))
      |> Enum.max(fn -> nil end)

    reserve = if widest, do: cfg.end_labels.offset_x + widest, else: 0
    put_in(cfg, [:end_labels, :reserve], reserve)
  end

  def prepare(cfg, _series), do: cfg

  @doc """
  Renders the labels. `anchored` pairs each drawn series with its plotted
  points `[{j, value | nil, {x, y} | nil}]`, as `EexCharts.Charts.Line`
  computes them.
  """
  def render(%{end_labels: %{enabled: true, reserve: _}} = cfg, anchored, %Layout{} = l) do
    o = cfg.end_labels
    fs = o.style.font_size
    half = Layout.text_height(fs) / 2
    pitch = half * 2 + o.min_gap

    labels =
      for {s, points} <- anchored,
          {_j, v, {x, y}} <- [last_point(points)],
          text when text != nil <- [text(cfg, s, v)],
          do: %{series: s, text: text, x: x, y: y}

    ys =
      labels
      |> Enum.map(& &1.y)
      |> place(o.avoid_overlap, pitch, l.grid_y + half, l.grid_y + l.grid_h - half)

    case labels do
      [] ->
        []

      _ ->
        el(
          "g",
          %{class: "eexcharts-end-labels"},
          Enum.zip_with(labels, ys, fn lb, y ->
            el(
              "text",
              %{
                class: "eexcharts-end-label",
                x: lb.x + o.offset_x,
                y: y,
                text_anchor: "start",
                dominant_baseline: "central",
                fill: color(cfg, lb.series.index),
                font_family: o.style.font_family,
                font_size: fs,
                font_weight: o.style.font_weight
              },
              esc(lb.text)
            )
          end)
        )
    end
  end

  def render(_cfg, _anchored, _l), do: []

  @doc """
  Vertical label positions for anchors `ys` (in any order; the result keeps
  that order). With `avoid_overlap` false the anchors are returned as given;
  otherwise neighbours end up at least `pitch` apart and inside `lo..hi`
  when the column fits (see the moduledoc).
  """
  def place(ys, false, _pitch, _lo, _hi), do: ys
  def place([], _avoid, _pitch, _lo, _hi), do: []

  def place(ys, true, pitch, lo, hi) do
    order = ys |> Enum.with_index() |> Enum.sort()
    n = length(order)
    shifted = order |> Enum.with_index(fn {y, _i}, k -> y - k * pitch end)
    top_max = max(hi - (n - 1) * pitch, lo)

    order
    |> Enum.zip(pava(shifted))
    |> Enum.with_index(fn {{_y, i}, z}, k -> {i, (z |> max(lo) |> min(top_max)) + k * pitch} end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  # Pool adjacent violators: least-squares non-decreasing fit. Blocks are
  # `{sum, count}`; a new value merges backwards while it would sit above
  # the block before it.
  defp pava(values) do
    values
    |> Enum.reduce([], fn v, blocks -> merge([{v, 1} | blocks]) end)
    |> Enum.reverse()
    |> Enum.flat_map(fn {sum, c} -> List.duplicate(sum / c, c) end)
  end

  defp merge([{s1, c1}, {s0, c0} | rest]) when s0 / c0 > s1 / c1,
    do: merge([{s0 + s1, c0 + c1} | rest])

  defp merge(blocks), do: blocks

  # The label text of a series, or nil when it has none.
  defp text(cfg, s, value) do
    case s[:end_label] do
      label when label in [nil, false] -> nil
      true -> format(cfg, s, s.name, value)
      label -> format(cfg, s, to_string(label), value)
    end
  end

  defp format(cfg, s, label, value) do
    case cfg.end_labels.formatter do
      f when is_function(f, 2) ->
        to_string(f.(label, %{series_index: s.index, series_name: s.name, value: value}))

      f when is_function(f, 1) ->
        to_string(f.(label))

      _ ->
        label
    end
  end

  defp last_point(points) do
    Enum.find(Enum.reverse(points), {nil, nil, nil}, fn {_j, v, xy} -> v != nil and xy != nil end)
  end

  defp last_value(data) do
    data |> Enum.reverse() |> Enum.find(&is_number/1)
  end

  defp color(cfg, i) do
    case Config.color_for(cfg.end_labels.style.colors, i) do
      nil -> Color.legible(Config.color_at(cfg, i), page(cfg))
      c -> c
    end
  end

  defp page(%{chart: %{background: "#" <> _ = bg}}), do: bg
  defp page(%{theme: %{mode: :dark}}), do: @dark_page
  defp page(_cfg), do: @light_page
end
