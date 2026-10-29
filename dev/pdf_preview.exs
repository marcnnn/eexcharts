# Writes one sample PDF per chart family for visual inspection of the PDF
# backend. Run: mix run dev/pdf_preview.exs
#
#   OUT=/tmp/eexcharts_pdf mix run dev/pdf_preview.exs
#
# Each chart is scaled to fit A4 (landscape when it is wider than it is tall)
# and centred, so the whole drawing is on the page — a chart running off the
# right edge looks a lot like a clipping bug otherwise.
#
# There is no PDF rasterizer in the dev deps; to look at the result use
# whatever the host has (`pdftoppm -png`, `mutool draw`, a PDF viewer).

defmodule PdfPreview do
  # The examples worth eyeballing: one per family, biased towards the features
  # that are easy to get wrong (gradients, rounded corners, negative bars,
  # rotated labels, arcs, transformed groups).
  @ids ~w(c1 c3 c5 c6 c7 c8 c9 n5 n7 n8 n9 n11 n13)

  @margin 28

  def run do
    out = System.get_env("OUT") || "/tmp/eexcharts_pdf"
    File.mkdir_p!(out)

    Dev.ChartExamples.all()
    |> Enum.filter(&(&1.id in @ids))
    |> Enum.each(&write(&1, out))
  end

  defp write(example, out) do
    attrs = Dev.ChartExamples.attributes(example)
    opts = attrs |> Map.drop([:id, :type, :series, :on_legend_click]) |> Map.to_list()

    {w, h} = chart_size(example, opts)
    page = if w > h, do: {:a4, :landscape}, else: :a4
    {page_w, page_h} = PrawnEx.Units.page_size(page)

    scale = min((page_w - 2 * @margin) / w, (page_h - 2 * @margin) / h)
    x = (page_w - scale * w) / 2
    y = (page_h - scale * h) / 2

    pdf =
      EexCharts.PDF.to_pdf(
        example.id,
        example.type,
        example.series,
        opts ++ [page_size: page, x: x, y: y, scale: scale]
      )

    path = Path.join(out, "#{example.id}-#{example.type}.pdf")
    File.write!(path, pdf)
    IO.puts("wrote #{path} (#{byte_size(pdf)} bytes)")
  end

  defp chart_size(example, opts) do
    %{id: example.id, type: example.type, series: example.series, static: true}
    |> Map.merge(Map.new(opts))
    |> EexCharts.Renderer.render()
    |> EexCharts.PDF.Ops.size()
  end
end

PdfPreview.run()
