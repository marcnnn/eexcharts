# Renders the chart gallery in daisyUI mode to dev/daisy_preview.html.
# Run: mix run dev/daisy_preview.exs
#
# The point of the page is the theme picker: the charts are rendered *once*,
# server-side, in `theme: %{mode: :daisy}`. Switching themes only flips
# `data-theme` on <html> — every chart restyles itself because the SVG carries
# `var(--color-*)` references rather than resolved colors. No re-render, no
# round-trip, no JS beyond the two-line `onchange`.
#
# daisyUI is not a dependency of this dev harness, so the three themes below
# are hand-written stand-ins using daisyUI v5's variable names. Values are
# approximations of daisyUI's light/dark/dracula for eyeballing purposes; the
# library only ever depends on the names.

defmodule DaisyPreview do
  @initial_theme "light"

  @themes %{
    "light" => %{
      "primary" => "oklch(49% 0.24 277)",
      "primary-content" => "oklch(96% 0.02 277)",
      "secondary" => "oklch(69% 0.18 20)",
      "secondary-content" => "oklch(98% 0.01 20)",
      "accent" => "oklch(77% 0.15 163)",
      "accent-content" => "oklch(27% 0.05 163)",
      "neutral" => "oklch(32% 0.02 264)",
      "neutral-content" => "oklch(98% 0 0)",
      "info" => "oklch(72% 0.14 232)",
      "info-content" => "oklch(29% 0.06 232)",
      "success" => "oklch(77% 0.15 163)",
      "success-content" => "oklch(27% 0.05 163)",
      "warning" => "oklch(82% 0.19 84)",
      "warning-content" => "oklch(27% 0.08 84)",
      "error" => "oklch(64% 0.24 25)",
      "error-content" => "oklch(97% 0.01 25)",
      "base-100" => "oklch(100% 0 0)",
      "base-200" => "oklch(96% 0 0)",
      "base-300" => "oklch(92% 0 0)",
      "base-content" => "oklch(21% 0.006 285)"
    },
    "dark" => %{
      "primary" => "oklch(65% 0.24 277)",
      "primary-content" => "oklch(14% 0.05 277)",
      "secondary" => "oklch(74% 0.16 20)",
      "secondary-content" => "oklch(15% 0.04 20)",
      "accent" => "oklch(77% 0.15 163)",
      "accent-content" => "oklch(15% 0.04 163)",
      "neutral" => "oklch(74% 0.02 264)",
      "neutral-content" => "oklch(15% 0.01 264)",
      "info" => "oklch(72% 0.14 232)",
      "info-content" => "oklch(15% 0.04 232)",
      "success" => "oklch(77% 0.15 163)",
      "success-content" => "oklch(15% 0.04 163)",
      "warning" => "oklch(82% 0.19 84)",
      "warning-content" => "oklch(18% 0.05 84)",
      "error" => "oklch(71% 0.19 22)",
      "error-content" => "oklch(15% 0.05 22)",
      "base-100" => "oklch(25% 0.01 264)",
      "base-200" => "oklch(22% 0.01 264)",
      "base-300" => "oklch(19% 0.01 264)",
      "base-content" => "oklch(93% 0.01 264)"
    },
    "dracula" => %{
      "primary" => "oklch(75% 0.18 348)",
      "primary-content" => "oklch(15% 0.05 348)",
      "secondary" => "oklch(74% 0.14 305)",
      "secondary-content" => "oklch(15% 0.04 305)",
      "accent" => "oklch(83% 0.13 200)",
      "accent-content" => "oklch(15% 0.04 200)",
      "neutral" => "oklch(39% 0.03 285)",
      "neutral-content" => "oklch(97% 0.01 285)",
      "info" => "oklch(83% 0.13 200)",
      "info-content" => "oklch(15% 0.04 200)",
      "success" => "oklch(87% 0.19 148)",
      "success-content" => "oklch(15% 0.05 148)",
      "warning" => "oklch(92% 0.14 96)",
      "warning-content" => "oklch(18% 0.04 96)",
      "error" => "oklch(72% 0.18 24)",
      "error-content" => "oklch(15% 0.05 24)",
      "base-100" => "oklch(28% 0.03 285)",
      "base-200" => "oklch(24% 0.03 285)",
      "base-300" => "oklch(21% 0.03 285)",
      "base-content" => "oklch(97% 0.01 285)"
    }
  }

  def run do
    charts =
      Enum.map(Dev.ChartExamples.all(), fn example ->
        attrs = Dev.ChartExamples.attributes(example)
        opts = Map.put(attrs[:options] || %{}, :theme, %{mode: :daisy})

        {:safe, io} =
          EexCharts.render(
            attrs[:id],
            attrs[:type],
            attrs[:series],
            attrs |> Map.put(:options, opts) |> Map.to_list()
          )

        """
        <div class="card">
          <h3>#{example.title}</h3>
          #{IO.iodata_to_binary(io)}
        </div>
        """
      end)

    js =
      "priv/static/eexcharts.js"
      |> File.read!()
      |> String.replace("export default EexCharts;", "")

    html = """
    <!doctype html>
    <html data-theme="#{@initial_theme}">
    <head>
      <meta charset="utf-8" />
      <title>EexCharts — daisyUI theming</title>
      <style>
    #{theme_css()}
    #{File.read!("priv/static/eexcharts.css")}
        body {
          font-family: Helvetica, Arial, sans-serif;
          background: var(--color-base-200);
          color: var(--color-base-content);
          margin: 0;
          padding: 24px;
        }
        header {
          display: flex;
          align-items: baseline;
          gap: 16px;
          margin-bottom: 20px;
        }
        h1 { font-size: 18px; margin: 0; }
        p { margin: 0; opacity: 0.7; font-size: 13px; }
        select {
          font: inherit;
          padding: 4px 8px;
          background: var(--color-base-100);
          color: var(--color-base-content);
          border: 1px solid var(--color-base-300);
          border-radius: 6px;
        }
        .grid {
          display: grid;
          grid-template-columns: repeat(auto-fill, minmax(620px, 1fr));
          gap: 16px;
        }
        .card {
          background: var(--color-base-100);
          border: 1px solid var(--color-base-300);
          border-radius: 10px;
          padding: 12px 16px;
        }
        h3 { font-size: 13px; font-weight: 600; margin: 0 0 8px; opacity: 0.75; }
      </style>
    </head>
    <body>
      <header>
        <h1>EexCharts &mdash; daisyUI theming</h1>
        <select onchange="document.documentElement.dataset.theme = this.value">
    #{Enum.map_join(Map.keys(@themes), "\n", fn t -> ~s(      <option value="#{t}"#{if t == @initial_theme, do: " selected"}>#{t}</option>) end)}
        </select>
        <p>Rendered once on the server. Switching themes only flips
          <code>data-theme</code> &mdash; nothing re-renders.</p>
      </header>
      <div class="grid">
    #{charts}
      </div>
      <script>
    #{js}
        // Stand in for LiveView's hook lifecycle so tooltips work on a static page.
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

    File.write!("dev/daisy_preview.html", html)
    IO.puts("wrote dev/daisy_preview.html")
  end

  defp theme_css do
    Enum.map_join(@themes, "\n", fn {name, vars} ->
      decls = Enum.map_join(vars, "\n", fn {k, v} -> "      --color-#{k}: #{v};" end)
      "    [data-theme=\"#{name}\"] {\n#{decls}\n    }"
    end)
  end
end

DaisyPreview.run()
