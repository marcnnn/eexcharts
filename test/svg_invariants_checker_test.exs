defmodule EexCharts.SvgInvariantsCheckerTest do
  @moduledoc """
  Proves the invariant checker catches what it claims to (a lint that never
  fires is indistinguishable from one that is broken).
  """
  use ExUnit.Case, async: true

  alias EexCharts.SvgInvariants

  defp svg(body, view_box),
    do: ~s|<svg xmlns="http://www.w3.org/2000/svg" viewBox="#{view_box}">#{body}</svg>|

  defp checks(body, view_box \\ "0 0 100 100"),
    do: body |> svg(view_box) |> SvgInvariants.check() |> Enum.map(& &1.check)

  test "a clean document passes" do
    assert checks(~s|<rect x="10" y="10" width="20" height="20"/><text x="50" y="50">ok</text>|) ==
             []
  end

  test "malformed markup" do
    assert SvgInvariants.check("<svg><g></svg>") |> Enum.map(& &1.check) == [:xml]
  end

  test "NaN, nil and empty numbers" do
    assert :bad_token in checks(~s|<circle cx="NaN" cy="5" r="2"/>|)
    assert :bad_token in checks(~s|<text x="5" y="5">nil</text>|)
    assert :numeric in checks(~s|<rect x="" y="0" width="1" height="1"/>|)
    assert :numeric in checks(~s|<path d="M 0 0 L 5"/>|)
  end

  test "negative sizes" do
    assert :negative_size in checks(~s|<rect x="5" y="5" width="-3" height="2"/>|)
  end

  test "elements outside the viewBox, through transforms" do
    assert :bounds in checks(~s|<rect x="90" y="10" width="20" height="5"/>|)

    assert :bounds in checks(
             ~s|<g transform="translate(60, 0)"><circle cx="40" cy="50" r="5"/></g>|
           )

    assert checks(~s|<g transform="translate(-60, 0)"><circle cx="70" cy="50" r="5"/></g>|) == []
    # Hidden and non-drawn elements are exempt.
    assert checks(~s|<rect x="200" y="0" width="1" height="1" display="none"/>|) == []
  end

  test "relative path commands" do
    assert :bounds in checks(~s|<path d="m 10 10 l 50 0 l 50 0"/>|)
    assert checks(~s|<path d="m 10 10 h 50 v 50 z"/>|) == []
  end

  test "curves are bounded by their extrema, not their control points" do
    # Control points at y = -20, but the curve itself only reaches y = -2.5.
    assert checks(~s|<path d="M 0 50 C 0 -20 100 -20 100 50"/>|, "0 -3 100 100") == []
    assert :bounds in checks(~s|<path d="M 0 50 C 0 -20 100 -20 100 50"/>|, "0 0 100 100")
  end

  test "arcs are bounded by the arc, not the chord" do
    arc = ~s|<path d="M 10 50 A 40 40 0 0 1 90 50"/>|
    # Clockwise from (10,50) to (90,50) bulges up to y = 10.
    assert checks(arc, "0 0 100 100") == []
    assert :bounds in checks(arc, "0 20 100 80")
  end

  test "ids and references" do
    assert :duplicate_id in checks(~s|<g id="a"/><g id="a"/>|)
    assert :dangling_ref in checks(~s|<rect width="1" height="1" fill="url(#missing)"/>|)

    assert checks(
             ~s|<defs><linearGradient id="g"/></defs><rect width="1" height="1" fill="url(#g)"/>|
           ) == []
  end

  test "overlapping labels in one group" do
    assert :text_overlap in checks(
             ~s|<g class="labels"><text x="20" y="50">Alpha</text><text x="30" y="50">Beta</text></g>|
           )

    # Different groups may overlap (e.g. a data label over an axis label is a
    # different concern).
    assert checks(
             ~s|<text class="a" x="20" y="50">Alpha</text><text class="b" x="30" y="50">Beta</text>|
           ) ==
             []
  end

  test "labels must be readable on their own background box" do
    box = ~s|<rect x="10" y="40" width="40" height="15" fill="#fff"/>|
    assert :contrast in checks(box <> ~s|<text x="30" y="47" fill="#f6f7f8">hi</text>|)
    assert checks(box <> ~s|<text x="30" y="47" fill="#373d3f">hi</text>|) == []
  end

  test "rotated labels are compared as rotated boxes" do
    # Two -45 degree labels 15px apart: their axis-aligned boxes overlap,
    # their rotated boxes do not.
    labels =
      for x <- [40, 55] do
        ~s|<text x="#{x}" y="80" font-size="11" text-anchor="end" transform="rotate(-45 #{x} 80)">Long label</text>|
      end

    assert checks(~s|<g class="x">#{Enum.join(labels)}</g>|, "0 0 120 120") == []
  end

  test "multi-line labels are one box per line" do
    two_lines =
      ~s|<text x="50" y="20" font-size="10" text-anchor="middle"><tspan x="50" dy="0">Top</tspan><tspan x="50" dy="1.2em">Bottom</tspan></text>|

    assert checks(~s|<g class="l">#{two_lines}</g>|) == []

    clash = ~s|<text x="50" y="32" font-size="10" text-anchor="middle">Other</text>|
    assert :text_overlap in checks(~s|<g class="l">#{two_lines}#{clash}</g>|)
  end
end
