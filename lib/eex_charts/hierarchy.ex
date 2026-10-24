defmodule EexCharts.Hierarchy do
  @moduledoc """
  Normalizes hierarchical chart data (sunburst, nested treemap) into a tree of
  plain maps.

  A data point takes the treemap shape plus an optional `children` list:

      %{x: "Europe", children: [%{x: "France", y: 68}, %{x: "Spain", y: 48}]}

  Children use the same shapes as a top-level point (`%{x:, y:}`,
  `%{label:, value:}`, `{label, value}` or a bare number), to any depth.

  ## Values

  Leaves carry the values. A node with children is worth the sum of its
  children: a `y` given on such a node is ignored, so the rings / rects of the
  children always tile their parent exactly. Leaf values go through the
  chart's `leaf_value` function (`abs/1` for treemaps, matching the flat
  treemap's areas; clamped at zero for sunbursts).

  Every node is `%{label, value, children, index}` where `index` is its
  position among its siblings.
  """

  import EexCharts.SVG

  alias EexCharts.Renderer

  @doc """
  Normalizes a list of data points into nodes. `labels` names bare-number
  points by position (top level only), like the flat treemap does.
  """
  def nodes(data, leaf_value, labels \\ [])

  def nodes(data, leaf_value, labels) when is_list(data) do
    data
    |> Enum.with_index()
    |> Enum.map(fn {pt, j} -> node(pt, j, leaf_value, labels) end)
  end

  def nodes(_data, _leaf_value, _labels), do: []

  defp node(pt, j, leaf_value, labels) do
    {label, raw} = label_value(pt, j, labels)
    children = nodes(children_of(pt), leaf_value, [])

    value =
      case children do
        [] -> leaf_value.(raw)
        _ -> children |> Enum.map(& &1.value) |> Enum.sum()
      end

    %{label: label, value: value, children: children, index: j}
  end

  defp children_of(%{children: children}) when is_list(children), do: children
  defp children_of(_pt), do: []

  defp label_value(%{x: x} = pt, _j, _labels), do: {to_string(x), num(pt[:y])}
  defp label_value(%{label: l} = pt, _j, _labels), do: {to_string(l), num(pt[:value])}
  defp label_value({label, value}, _j, _labels), do: {to_string(label), num(value)}

  defp label_value(v, j, labels) when is_number(v),
    do: {to_string(Enum.at(labels, j) || j + 1), v}

  defp label_value(_v, j, labels), do: {to_string(Enum.at(labels, j) || j + 1), 0}

  defp num(v) when is_number(v), do: v
  defp num(_), do: 0

  @doc "True when any point in any series has a non-empty `children` list."
  def nested?(series) when is_list(series) do
    Enum.any?(series, fn
      %{data: data} when is_list(data) -> Enum.any?(data, &has_children?/1)
      _ -> false
    end)
  end

  def nested?(_series), do: false

  defp has_children?(%{children: [_ | _]}), do: true
  defp has_children?(_), do: false

  @doc "Number of levels in a forest (1 when every node is a leaf, 0 when empty)."
  def depth([]), do: 0
  def depth(nodes), do: 1 + (nodes |> Enum.map(&depth(&1.children)) |> Enum.max())

  @doc "Share of `value` in `total`, as a percentage (0 when the total is 0)."
  def share(_value, total) when total == 0, do: 0.0
  def share(value, total), do: 100 * value / total

  @doc """
  One hover tooltip for a node: the path as title, then the node's value and
  its share of the parent (or of the total, for a top-level node).
  """
  def tooltip(cfg, key, color, path_labels, value, share_label, pct) do
    el("div", %{class: "eexcharts-tip", data_j: key, hidden: true}, [
      el("div", %{class: "eexcharts-tip-title"}, esc(Enum.join(path_labels, " / "))),
      Renderer.tooltip_row(color, List.last(path_labels), Renderer.format_tooltip_y(cfg, value)),
      el("div", %{class: "eexcharts-tip-row"}, [
        el("span", %{class: "eexcharts-tip-label"}, [esc(share_label), ": "]),
        el("span", %{class: "eexcharts-tip-value"}, format_pct(pct))
      ])
    ])
  end

  @doc "Formats a percentage with one decimal, dropping a trailing `.0`."
  def format_pct(pct) do
    rounded = Float.round(pct * 1.0, 1)
    if rounded == trunc(rounded), do: "#{trunc(rounded)}%", else: "#{rounded}%"
  end
end
