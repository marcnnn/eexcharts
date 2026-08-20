defmodule EexCharts.ColorTest do
  use ExUnit.Case, async: true

  alias EexCharts.Color

  describe "shade/2 with hex" do
    test "blends toward white and black" do
      assert Color.shade("#808080", 0.5) == "#C0C0C0"
      assert Color.shade("#808080", -0.5) == "#404040"
      assert Color.shade("#008FFB", 0) == "#008FFB"
    end

    test "expands three-digit hex" do
      assert Color.shade("#fff", 0) == "#FFFFFF"
    end
  end

  describe "shade/2 with a browser-resolved color" do
    test "defers the blend to color-mix" do
      assert Color.shade("var(--color-primary, #008FFB)", 0.5) ==
               "color-mix(in oklab, #fff 50%, var(--color-primary, #008FFB))"

      assert Color.shade("var(--color-primary)", -0.25) ==
               "color-mix(in oklab, #000 25%, var(--color-primary))"
    end

    test "clamps the percentage the way the hex path clamps channels" do
      # Treemap shade intensities can exceed 1; >100% is invalid CSS.
      assert Color.shade("var(--x)", 1.25) == "color-mix(in oklab, #fff 100%, var(--x))"
    end

    test "nests when a shaded color is shaded again" do
      once = Color.shade("var(--x)", 0.2)
      assert Color.shade(once, 0.2) == "color-mix(in oklab, #fff 20%, #{once})"
    end
  end

  describe "resolve_vars/1" do
    test "resolves a var() to its fallback literal" do
      assert Color.resolve_vars("var(--color-primary, #008FFB)") == "#008FFB"
    end

    test "resolves nested fallbacks innermost-first" do
      assert Color.resolve_vars("var(--a, var(--b, #fff))") == "#fff"
    end

    test "resolves var() embedded in a larger expression" do
      assert Color.resolve_vars("color-mix(in oklab, #fff 30%, var(--x, #008FFB))") ==
               "color-mix(in oklab, #fff 30%, #008FFB)"
    end

    test "leaves a var() without a fallback untouched" do
      assert Color.resolve_vars("var(--color-primary)") == "var(--color-primary)"
    end

    test "passes plain values through unchanged" do
      assert Color.resolve_vars("#008FFB") == "#008FFB"
      assert Color.resolve_vars("transparent") == "transparent"
    end
  end
end
