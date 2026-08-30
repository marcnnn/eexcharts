defmodule EexCharts.PDF.ToPdfTest do
  @moduledoc """
  `to_pdf/4` end to end, through PrawnEx's writer.

  The op-list snapshots pin what we draw; this pins that a real PDF comes out
  the other side, that nothing browser-only survived into it, and that two
  runs produce the same bytes — which matters for anything that caches or
  content-addresses a generated report.
  """
  use ExUnit.Case, async: true

  @series [%{name: "Alpha", data: [31, 40, 28, 51]}, %{name: "Beta", data: [11, 32, 45, 32]}]
  @months ~w(Jan Feb Mar Apr)

  defp pdf(type, opts \\ []) do
    opts = Keyword.merge([categories: @months, x: 20, y: 300], opts)
    EexCharts.PDF.to_pdf("smoke", type, series_for(type), opts)
  end

  defp series_for(type) when type in [:pie, :donut], do: [44, 55, 13, 43]
  defp series_for(:radial_bar), do: [76, 61, 90]
  defp series_for(_), do: @series

  describe "the binary is a PDF" do
    for type <- [:line, :bar, :pie, :radar] do
      test "#{type} renders a page" do
        out = pdf(unquote(type))

        assert String.starts_with?(out, "%PDF-")
        assert out =~ "/Type /Page"
        assert String.ends_with?(out, "%%EOF\n")
      end
    end

    test "text reaches the content stream as text" do
      out = pdf(:line)

      # Content streams are uncompressed, so the labels are readable bytes.
      for month <- @months, do: assert(out =~ "(#{month}) Tj")
      assert out =~ "/BaseFont /Helvetica"
    end
  end

  describe "nothing browser-only survives" do
    test "no CSS custom properties, even under the daisy theme" do
      out = pdf(:bar, options: %{theme: %{mode: :daisy}})

      refute out =~ "var("
      refute out =~ "color-mix("
    end

    test "no phx bindings or hover furniture" do
      out = pdf(:line)

      refute out =~ "phx-"
      refute out =~ "eexcharts-zone"
      refute out =~ "crosshair"
    end

    test "ASCII labels transliterate without loss" do
      out =
        EexCharts.PDF.to_pdf("smoke", :bar, [%{name: "A", data: [1, 2]}],
          categories: ~w(Ok Fine),
          x: 20,
          y: 300
        )

      # A `?` in a literal string is what PrawnEx emits for a codepoint it
      # cannot map to WinAnsi; plain Latin text must never produce one.
      refute out =~ "(?"
      refute out =~ "?)"
    end
  end

  describe "determinism" do
    test "the same chart renders byte-identical twice" do
      for type <- [:line, :bar, :donut] do
        assert pdf(type) == pdf(type)
      end
    end

    test "the writer embeds no timestamp" do
      out = pdf(:line)

      refute out =~ "CreationDate"
      refute out =~ "ModDate"
    end
  end

  describe "placement" do
    test ":page_size picks the media box" do
      assert pdf(:line, page_size: {:a4, :landscape}) =~ "/MediaBox [ 0 0 842 595 ]"
      assert pdf(:line, page_size: :letter) =~ "/MediaBox [ 0 0 612 792 ]"
    end

    test ":scale changes the drawing, not the page" do
      small = pdf(:line, scale: 0.5)
      full = pdf(:line)

      assert small =~ "/MediaBox [ 0 0 595 842 ]"
      assert small != full
    end
  end

  describe "ops/4 needs no writer" do
    test "it returns plain tuples with no PrawnEx struct in sight" do
      ops = EexCharts.PDF.ops("smoke", :line, @series, categories: @months)

      assert is_list(ops)
      assert Enum.all?(ops, &(is_tuple(&1) or is_atom(&1)))
      refute Enum.any?(ops, &is_struct/1)
    end

    test "the ops are exactly what the page ends up holding" do
      opts = [categories: @months, x: 20, y: 300]
      ops = EexCharts.PDF.ops("smoke", :line, @series, opts)

      page =
        PrawnEx.Document.new()
        |> PrawnEx.Document.add_page()
        |> PrawnEx.Document.inject_page_ops(0, ops, [])
        |> PrawnEx.Document.current_page()

      assert PrawnEx.Page.content_ops(page) == ops
    end
  end
end
