defmodule Dev.ChartExamples.Hierarchy do
  @moduledoc false
  # Examples for one feature area, appended to `Dev.ChartExamples.all/0`.
  # Ids must be unique across the whole catalog: they name the SVG goldens.

  def examples do
    [
      %{
        id: "hi1",
        title: "Sunburst",
        group: :sunburst,
        type: :sunburst,
        series: [%{name: "Budget", data: budget()}]
      },
      %{
        id: "hi2",
        title: "Sunburst: three levels, radial labels, no hole",
        group: :sunburst,
        type: :sunburst,
        height: 420,
        series: [%{name: "Disk", data: disk()}],
        options: %{
          plot_options: %{sunburst: %{hole_size: 0, labels: %{orientation: :radial}}},
          legend: %{position: :bottom}
        }
      },
      %{
        id: "hi3",
        title: "Sunburst: one branch per series",
        group: :sunburst,
        type: :sunburst,
        series: [
          %{
            name: "Europe",
            data: [%{x: "Germany", y: 84}, %{x: "France", y: 68}, %{x: "Italy", y: 59}]
          },
          %{name: "Asia", data: [%{x: "Japan", y: 124}, %{x: "Korea", y: 52}]},
          %{
            name: "Americas",
            data: [%{x: "USA", y: 335}, %{x: "Canada", y: 40}, %{x: "Mexico", y: 128}]
          }
        ],
        options: %{title: %{text: "Population (millions)"}}
      },
      %{
        id: "hi4",
        title: "Nested treemap",
        group: :treemap,
        type: :treemap,
        series: [%{name: "Budget", data: budget()}]
      },
      %{
        id: "hi5",
        title: "Nested treemap: three levels",
        group: :treemap,
        type: :treemap,
        height: 420,
        series: [%{name: "Disk", data: disk()}],
        options: %{data_labels: %{style: %{font_size: 12}}}
      }
    ]
  end

  defp budget do
    [
      %{
        x: "Engineering",
        children: [
          %{x: "Platform", y: 420},
          %{x: "Mobile", y: 260},
          %{x: "Web", y: 310},
          %{x: "QA", y: 120}
        ]
      },
      %{
        x: "Sales",
        children: [
          %{x: "EMEA", y: 230},
          %{x: "Americas", y: 340},
          %{x: "APAC", y: 150}
        ]
      },
      %{
        x: "Marketing",
        children: [%{x: "Brand", y: 140}, %{x: "Events", y: 90}, %{x: "Content", y: 70}]
      },
      %{x: "Support", children: [%{x: "Tier 1", y: 110}, %{x: "Tier 2", y: 80}]},
      %{x: "Admin", y: 95}
    ]
  end

  defp disk do
    [
      %{
        x: "src",
        children: [
          %{x: "charts", children: [%{x: "bar", y: 31}, %{x: "line", y: 29}, %{x: "pie", y: 41}]},
          %{x: "core", children: [%{x: "svg", y: 26}, %{x: "scale", y: 37}]},
          %{x: "legend", y: 38}
        ]
      },
      %{
        x: "test",
        children: [
          %{x: "unit", children: [%{x: "axes", y: 22}, %{x: "theme", y: 15}]},
          %{x: "snapshots", y: 64}
        ]
      },
      %{
        x: "docs",
        children: [%{x: "guides", y: 24}, %{x: "api", y: 18}]
      },
      %{x: "assets", y: 21}
    ]
  end
end
