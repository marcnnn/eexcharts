defmodule EexCharts.PDF.Text do
  @moduledoc """
  Turning an SVG `<text>` into something PDF can place.

  SVG positions a label by its anchor and its dominant baseline; PDF's
  `text_at` only knows the left end of the alphabetic baseline. Closing that
  gap needs the same measurement the layout engine already does — the advance
  widths in `EexCharts.FontMetrics` — plus the font's vertical metrics.

  Text also arrives escaped, because the chart modules escape it on the way
  into the tree (`EexCharts.SVG.esc/1`) and only the SVG serializer would
  otherwise ever see it.
  """

  alias EexCharts.Layout

  # Helvetica's AFM vertical metrics. The PDF always draws in a base-14
  # Helvetica, so these are the real numbers for the glyphs that land on the
  # page — not an approximation of "some sans-serif" the way
  # `Layout.text_ascent/1` has to be for a browser.
  @ascent 0.718
  @descent 0.207

  @doc """
  Undoes `EexCharts.SVG.esc/1`.

  `&amp;` is replaced last, so `&amp;lt;` — an author who really wrote
  `&lt;` — comes back as `&lt;` and not as `<`.
  """
  def unescape(text) when is_binary(text) do
    text
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&amp;", "&")
  end

  @doc """
  Horizontal shift from an SVG `x` to the start of the baseline, for the given
  `text-anchor`.

  Widths come from the `:arial` table, which is the Helvetica AFM — so for the
  Helvetica the PDF actually draws, the measurement is exact rather than an
  estimate.
  """
  def anchor_dx(text, font_size, anchor) do
    case to_string(anchor || "start") do
      "middle" -> -Layout.text_width(text, font_size, :arial) / 2
      "end" -> -Layout.text_width(text, font_size, :arial)
      _ -> 0
    end
  end

  @doc """
  Vertical shift (in SVG's y-down direction) from an SVG `y` to the alphabetic
  baseline, for the given `dominant-baseline`.

  `central` — the only value the chart modules emit — puts the em box's centre
  on `y`, which is half an em box above the baseline.
  """
  def baseline_dy(font_size, baseline) do
    case to_string(baseline || "auto") do
      b when b in ["central", "middle"] -> (@ascent - @descent) / 2 * font_size
      b when b in ["hanging", "text-before-edge"] -> @ascent * font_size
      "text-after-edge" -> -@descent * font_size
      _ -> 0
    end
  end

  @doc """
  The base-14 font a `font-weight` maps to.

  Only the two weights the library emits are distinguished; there is no
  italic anywhere in a chart.
  """
  def font_name(weight) do
    if bold?(weight), do: "Helvetica-Bold", else: "Helvetica"
  end

  defp bold?(weight) when is_number(weight), do: weight >= 600
  defp bold?("bold"), do: true
  defp bold?("bolder"), do: true

  defp bold?(weight) when is_binary(weight) do
    case Integer.parse(weight) do
      {n, ""} -> n >= 600
      _ -> false
    end
  end

  defp bold?(_), do: false

  @doc """
  Resolves a `dy` — a bare number of user units, or the `1.2em` the
  multi-line label helpers emit — to user units.
  """
  def resolve_dy(nil, _font_size), do: 0
  def resolve_dy(dy, _font_size) when is_number(dy), do: dy

  def resolve_dy(dy, font_size) when is_binary(dy) do
    case Float.parse(dy) do
      {n, "em"} -> n * font_size
      {n, "px"} -> n
      {n, ""} -> n
      _ -> 0
    end
  end
end
