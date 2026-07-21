defmodule EexCharts.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/marcnickert/eexcharts"

  def project do
    [
      app: :eexcharts,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "EexCharts",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    "Server-side rendered SVG charts for Phoenix LiveView, modeled on ApexCharts.js. " <>
      "Charts render as SVG in Elixir; a minimal JS hook adds hover tooltips."
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "ApexCharts (original)" => "https://apexcharts.com"},
      files: ~w(lib priv/static mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "EexCharts",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end
end
