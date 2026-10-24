# Contact sheet: every example in Dev.ChartExamples.all/0 as static SVG, light
# and dark side by side, for fast human review (layer 4 of docs/VALIDATION.md).
#
#   mix run dev/contact_sheet.exs                  # writes tmp/contact_sheet.html
#   mix run dev/contact_sheet.exs --png            # ... and tmp/contact_sheet.png
#   mix run dev/contact_sheet.exs --group radar    # only one group
#   mix run dev/contact_sheet.exs --only c1,n2     # only these ids
#
# The PNG is taken with headless Chrome; override the binary with
# CHROME=/path/to/chrome.

defmodule ContactSheet do
  @dark_bg "#343434"
  @chrome "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv, strict: [png: :boolean, group: :string, only: :string])

    examples =
      Dev.ChartExamples.all()
      |> filter_group(opts[:group])
      |> filter_ids(opts[:only])

    File.mkdir_p!("tmp")
    html_path = Path.expand("tmp/contact_sheet.html")
    File.write!(html_path, page(examples))
    IO.puts("wrote #{html_path} (#{length(examples)} examples)")

    if opts[:png], do: screenshot(html_path, length(examples))
  end

  defp filter_group(examples, nil), do: examples
  defp filter_group(examples, g), do: Enum.filter(examples, &(Atom.to_string(&1.group) == g))

  defp filter_ids(examples, nil), do: examples

  defp filter_ids(examples, ids) do
    wanted = String.split(ids, ",", trim: true)
    Enum.filter(examples, &(&1.id in wanted))
  end

  defp page(examples) do
    """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8" />
      <title>EexCharts contact sheet</title>
      <style>
        body { font-family: Helvetica, Arial, sans-serif; background: #e9ebee; margin: 16px; color: #222; }
        h1 { font-size: 18px; margin: 0 0 12px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(880px, 1fr)); gap: 12px; }
        .card { background: #fff; border-radius: 6px; padding: 8px 10px 10px; box-shadow: 0 1px 3px rgba(0,0,0,.1); }
        .meta { font-size: 12px; margin-bottom: 6px; display: flex; gap: 10px; align-items: baseline; }
        .meta b { font-size: 13px; }
        .meta code { background: #f1f2f4; padding: 1px 4px; border-radius: 3px; }
        .pair { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; align-items: start; }
        .panel { border: 1px solid #e3e5e8; border-radius: 4px; padding: 4px; }
        .panel.dark { background: #{@dark_bg}; border-color: #{@dark_bg}; }
        .panel svg { max-height: 420px; }
        .error { color: #b00020; font-size: 12px; white-space: pre-wrap; }
      </style>
    </head>
    <body>
      <h1>EexCharts contact sheet: #{length(examples)} examples, light | dark</h1>
      <div class="grid">
        #{Enum.map_join(examples, "\n", &card/1)}
      </div>
    </body>
    </html>
    """
  end

  defp card(example) do
    """
    <div class="card" id="card-#{example.id}">
      <div class="meta">
        <code>#{example.id}</code><b>#{esc(example.title)}</b>
        <span>group: #{example.group}</span><span>type: #{example.type}</span>
      </div>
      <div class="pair">
        <div class="panel">#{svg(example, :light)}</div>
        <div class="panel dark">#{svg(example, :dark)}</div>
      </div>
    </div>
    """
  end

  defp svg(example, mode) do
    attrs = Dev.ChartExamples.attributes(example)
    options = deep_merge(attrs[:options] || %{}, theme(mode))

    opts =
      attrs
      |> Map.drop([:id, :type, :series, :on_legend_click])
      |> Map.put(:options, options)
      |> Map.to_list()

    # Distinct ids per panel keep gradient/clip references from colliding.
    EexCharts.to_svg("#{example.id}-#{mode}", example.type, example.series, opts)
  rescue
    e -> ~s(<div class="error">#{esc(Exception.format(:error, e, __STACKTRACE__))}</div>)
  end

  defp theme(:light), do: %{}
  defp theme(:dark), do: %{theme: %{mode: :dark}, chart: %{background: @dark_bg}}

  defp deep_merge(a, b) do
    Map.merge(a, b, fn
      _k, %{} = x, %{} = y -> deep_merge(x, y)
      _k, _x, y -> y
    end)
  end

  defp esc(s), do: s |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp screenshot(html_path, count) do
    chrome = System.get_env("CHROME") || @chrome
    png = Path.expand("tmp/contact_sheet.png")
    # Two cards per row at 1880px; ~330px per card row plus the header.
    height = 80 + div(count + 1, 2) * 330

    {out, status} =
      System.cmd(
        chrome,
        [
          "--headless",
          "--disable-gpu",
          "--hide-scrollbars",
          "--screenshot=#{png}",
          "--window-size=1880,#{height}",
          "file://#{html_path}"
        ],
        stderr_to_stdout: true
      )

    if status == 0,
      do: IO.puts("wrote #{png}"),
      else: IO.puts(:stderr, "chrome failed (#{status}):\n#{out}")
  end
end

ContactSheet.run(System.argv())
