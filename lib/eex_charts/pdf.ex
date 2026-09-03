defmodule EexCharts.PDF do
  @moduledoc """
  Charts as PDF drawing operations, for [PrawnEx](https://hex.pm/packages/prawn_ex).

  `to_svg/4` already produces static output, and an SVG rasterizer can turn
  that into a PDF — but only by shelling out to one (resvg, Chromium, Typst)
  and only as a raster or a re-parsed vector. This draws the chart directly
  with PDF operators instead: real vectors, real base-14 text, no external
  binary, and the chart can share a page with the rest of a report.

  ## Two entry points

  `ops/4` returns a plain list of PrawnEx content-operation tuples. It needs
  no PrawnEx at runtime — the operations are just tuples — so a caller can
  place a chart inside a document it is already building:

      doc
      |> PrawnEx.Document.append_op(:save_state)
      |> then(fn doc ->
        Enum.reduce(EexCharts.PDF.ops("cpu", :line, series, x: 40, y: 500),
          doc, &PrawnEx.Document.append_op(&2, &1))
      end)

  `to_pdf/4` is the one-shot version: a complete single-page PDF binary. It
  needs PrawnEx to be available.

  ## Coordinates

  PDF measures in points from the **bottom-left** of the page, with y growing
  upwards. `:x` and `:y` place the chart's bottom-left corner (default
  `{0, 0}`); `:scale` multiplies its size, so a 600×350 chart at `scale: 0.8`
  occupies 480×280 points.

  One SVG user unit is one PDF point at `scale: 1`.

  ## Fonts

  Text is drawn in the base-14 Helvetica (`Helvetica-Bold` where the chart
  asks for a weight of 600 or more), which needs no font embedding and is what
  `chart.font_family` defaults to anyway. Label positions are measured with
  the `:arial` advance-width table, which *is* the Helvetica AFM — so anchors
  and centring are exact, not estimated.

  Non-Latin text is a limitation of the base-14 fonts rather than of this
  module: PrawnEx transliterates to WinAnsi and unmappable characters become
  `?`.

  ## What does not survive

  See `EexCharts.PDF.Ops` for the full list. In short: gradients degrade to
  their first stop, and fill and stroke share one opacity.
  """

  alias EexCharts.PDF.Ops
  alias EexCharts.Renderer

  # prawn_ex is a dev/test-only dependency: `ops/4` is pure data and must work
  # without it, and an application that only ever renders SVG should not have
  # to carry a PDF writer.
  @compile {:no_warn_undefined, [PrawnEx, PrawnEx.Document, PrawnEx.Page]}

  @doc """
  Builds the PDF content operations for one chart.

  Accepts everything `EexCharts.to_svg/4` accepts — `:categories`, `:labels`,
  `:width`, `:height`, `:options`, `:hidden_series` — plus:

    * `:x`, `:y` — where the chart's bottom-left corner sits on the page, in
      points from the page's bottom-left. Defaults to `{0, 0}`.
    * `:scale` — size multiplier. Defaults to `1`.

  The result is a list of `t:PrawnEx.Page.content_op/0` tuples. Nothing in it
  depends on PrawnEx being loaded.

  ## Example

      EexCharts.PDF.ops("cpu", :line, [%{name: "CPU", data: [10, 20, 15]}],
        categories: ~w(a b c),
        x: 40,
        y: 480,
        scale: 0.85
      )
  """
  def ops(id, type, series, opts \\ []) do
    opts = Map.new(opts)

    %{
      id: id,
      type: type,
      series: series,
      categories: opts[:categories],
      labels: opts[:labels],
      width: opts[:width],
      height: opts[:height],
      options: opts[:options] || %{},
      hidden_series: opts[:hidden_series] || [],
      static: true
    }
    |> Renderer.render()
    |> Ops.build(opts[:x] || 0, opts[:y] || 0, opts[:scale] || 1)
  end

  @doc """
  Renders a chart as a complete single-page PDF binary.

  Takes the options `ops/4` takes, plus `:page_size` (any size
  `PrawnEx.Units.page_size/1` knows — `:a4`, `:letter`, `{:a4, :landscape}`,
  …; defaults to `:a4`).

  Requires the optional `:prawn_ex` dependency.

      File.write!("cpu.pdf",
        EexCharts.PDF.to_pdf("cpu", :line, series, x: 40, y: 450))
  """
  def to_pdf(id, type, series, opts \\ []) do
    ensure_prawn_ex!()

    opts = Map.new(opts)
    page_ops = ops(id, type, series, Map.to_list(opts))

    PrawnEx.Document.new(page_size: opts[:page_size] || :a4)
    |> PrawnEx.Document.add_page()
    |> PrawnEx.Document.inject_page_ops(0, page_ops, [])
    |> PrawnEx.to_binary()
  end

  defp ensure_prawn_ex! do
    unless Code.ensure_loaded?(PrawnEx.Document) do
      raise """
      EexCharts.PDF.to_pdf/4 needs the :prawn_ex dependency, which is optional.

      Add it to your deps:

          {:prawn_ex, "~> 0.6"}

      `EexCharts.PDF.ops/4` needs no dependency at all — it returns plain
      tuples — if you would rather build the document yourself.
      """
    end
  end
end
