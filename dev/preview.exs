# Renders a gallery of charts to dev/preview.html for visual inspection.
# Run: mix run dev/preview.exs
#
# The page inlines the hover-hook JS (standalone, without LiveView) so
# tooltips, crosshairs and hover markers can be tested in a plain browser.

defmodule Preview do
  def chart(title, params) do
    {:safe, io} =
      EexCharts.render(params[:id], params[:type], params[:series], Map.to_list(params))

    """
    <div class="card">
      <h3>#{title}</h3>
      #{IO.iodata_to_binary(io)}
    </div>
    """
  end

  def run do
    charts =
      Enum.map(Dev.ChartExamples.all(), fn example ->
        chart(example.title, Dev.ChartExamples.attributes(example))
      end)

    js =
      "priv/static/eexcharts.js"
      |> File.read!()
      |> String.replace("export default EexCharts;", "")

    css = File.read!("priv/static/eexcharts.css")

    html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>EexCharts preview</title>
      <style>
        body { font-family: Helvetica, Arial, sans-serif; background: #f6f7f8; margin: 24px; }
        .grid { display: grid; grid-template-columns: repeat(2, minmax(380px, 640px)); gap: 24px; }
        .card { background: #fff; border-radius: 8px; padding: 16px; box-shadow: 0 1px 4px rgba(0,0,0,.08); }
        .card h3 { margin: 0 0 8px; font-size: 14px; color: #373d3f; }
        #{css}
      </style>
    </head>
    <body>
      <h1>EexCharts preview</h1>
      <div class="grid">
        #{Enum.join(charts, "\n")}
      </div>
      <script>
        #{js}
        document.querySelectorAll(".eexcharts").forEach((el) => {
          const inst = Object.create(EexCharts);
          inst.el = el;
          inst.pushEvent = () => {};
          inst.mounted();
        });
      </script>
    </body>
    </html>
    """

    File.write!("dev/preview.html", html)
    IO.puts("wrote dev/preview.html")
  end
end

Preview.run()
