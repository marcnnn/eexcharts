defmodule EexCharts.LabelText do
  @moduledoc """
  Axis-label text as a formatter returns it: measured and drawn the same way
  for radar category labels, cartesian x-axis labels and y-axis labels.

  A label formatter may return

    * a string (or any other value, passed through `to_string/1`): one line;
    * a list of lines, each drawn as its own `tspan` one line-height below
      the previous.

  A line is a string or a list of **segments**. A segment is a string, or a
  map with a `:text` and any of `:fill`, `:font_weight`, `:font_size`,
  `:font_style` and `:font_family`, drawn as a nested `tspan` with those
  attributes. Everything a segment leaves out it inherits from the label.

      formatter: fn label, j ->
        key = String.pad_leading("\#{j + 1}", 2, "0")

        [
          [%{text: key, fill: "#FF4560", font_weight: 700}, " ", label],
          ["second line"]
        ]
      end

  A bare map in the outer list is a line with one segment, so a single
  styled line has to be wrapped twice: `[[%{text: "01", ...}, " Name"]]`.
  """

  import EexCharts.SVG

  alias EexCharts.Layout

  @segment_attrs [:fill, :font_weight, :font_size, :font_style, :font_family]

  @doc """
  The label as lines of segments: `[[{text, attrs}]]`, where `attrs` holds
  only the style keys the segment sets.
  """
  def lines(label) when is_list(label), do: Enum.map(label, &line/1)
  def lines(label), do: [line(label)]

  defp line(segments) when is_list(segments), do: Enum.map(segments, &segment/1)
  defp line(segment), do: [segment(segment)]

  defp segment(%{} = seg) do
    {to_string(Map.get(seg, :text, "")), seg |> Map.take(@segment_attrs) |> reject_nil()}
  end

  defp segment(text), do: {to_string(text), %{}}

  defp reject_nil(map), do: map |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> Map.new()

  @doc "Number of lines the label is drawn on."
  def line_count(label) when is_list(label), do: length(label)
  def line_count(_label), do: 1

  @doc "The label's text without styling, lines joined by a space."
  def plain(label) do
    label
    |> lines()
    |> Enum.map_join(" ", fn segs -> Enum.map_join(segs, fn {text, _} -> text end) end)
  end

  @doc """
  Width (px) of the label's widest line. Segments are summed, each measured
  at its own `font_size` when it sets one.
  """
  def width(label, font_size, metrics) do
    label
    |> lines()
    |> Enum.map(fn segs ->
      segs
      |> Enum.map(fn {text, attrs} ->
        Layout.text_width(text, Map.get(attrs, :font_size, font_size), metrics)
      end)
      |> Enum.sum()
    end)
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  The children of the label's `<text>` element, anchored at `x`.

  A plain string stays bare text. A list becomes one `tspan` per line, each
  1.2em below the previous; `grow` says where the block sits relative to the
  text's own `y`:

    * `:down` (default): the first line is on `y`, the rest below it;
    * `:center`: the block is centred on `y`;
    * `:up`: the last line is on `y`, the rest above it.

  `baseline` is the `dominant-baseline` of the enclosing `<text>`, if it sets
  one. It is repeated on every `tspan` drawn here: browsers inherit it, but
  SVG 1.1 does not make it inherited, and renderers that follow 1.1 (resvg /
  usvg, and with them Typst) set a `tspan` without it on the alphabetic
  baseline. A styled segment then sits higher than the text around it, like
  a superscript.
  """
  def content(label, x, grow \\ :down, baseline \\ nil)

  def content(label, x, grow, baseline) when is_list(label) do
    n = length(label)

    label
    |> lines()
    |> Enum.with_index()
    |> Enum.map(fn {segs, i} ->
      dy = if i == 0, do: first_line_dy(n, grow), else: "1.2em"
      el("tspan", %{x: x, dy: dy, dominant_baseline: baseline}, segments(segs, baseline))
    end)
  end

  def content(%{} = label, _x, _grow, baseline),
    do: label |> lines() |> hd() |> segments(baseline)

  def content(label, _x, _grow, _baseline), do: esc(to_string(label))

  defp segments(segs, baseline) do
    Enum.map(segs, fn
      {text, attrs} when attrs == %{} -> esc(text)
      {text, attrs} -> el("tspan", Map.put(attrs, :dominant_baseline, baseline), esc(text))
    end)
  end

  defp first_line_dy(n, _grow) when n <= 1, do: nil
  defp first_line_dy(_n, :down), do: nil
  defp first_line_dy(n, :center), do: "#{fmt_value(-(n - 1) * 0.6)}em"
  defp first_line_dy(n, :up), do: "#{fmt_value(-(n - 1) * 1.2)}em"
end
