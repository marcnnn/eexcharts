defmodule EexCharts.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/marcnnn/eexcharts"

  def project do
    [
      app: :eexcharts,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      name: "EexCharts",
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  # Compile the dev-only server/storybook and test support helpers only where
  # they are needed. None of these ship in the published Hex package.
  defp elixirc_paths(:dev), do: ["lib", "dev"]
  defp elixirc_paths(:test), do: ["lib", "dev", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [dev: "run --no-halt dev/server.exs"]
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},

      # Dev/test-only harness: a standalone Phoenix server hosts a
      # phoenix_storybook catalog of every chart, which the visual suite drives
      # with phoenix_test_playwright. None of these ship in the Hex package.
      {:phoenix_storybook, "~> 1.3", only: [:dev, :test]},
      # phoenix is already a transitive (all-env) dep of phoenix_live_view, so
      # it cannot carry an :only restriction; declared here to pin the endpoint
      # /router macros the dev server needs.
      {:phoenix, "~> 1.7"},
      {:bandit, ">= 0.0.0", only: [:dev, :test]},
      {:jason, ">= 0.0.0", only: [:dev, :test]},
      {:phoenix_test_playwright, "~> 0.14", only: :test, runtime: false},

      # `EexCharts.PDF.ops/4` returns plain tuples and needs nothing at
      # runtime; only `to_pdf/4` and the tests that draw a page need the writer.
      # Pinned to a branch because the backend depends on prawn_ex's
      # graphics-state operators (save/restore, concat_matrix, set_opacity,
      # set_dash, curve_to, fill_stroke), which are unreleased. Once they ship
      # this becomes an optional Hex dep: {:prawn_ex, "~> 0.6", optional: true}.
      {:prawn_ex,
       github: "marcnnn/prawn_ex", branch: "feat/graphics-state-ops", only: [:dev, :test]}
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
