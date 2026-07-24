defmodule Dev.Endpoint do
  @moduledoc """
  Dev/test-only Phoenix endpoint that hosts the phoenix_storybook catalog.

  Modeled on `Phoenix.LiveDashboard`'s `dev.exs`. Only ever compiled in
  `:dev`/`:test` (see `elixirc_paths/1` in `mix.exs`) and never shipped in the
  Hex package.
  """
  use Phoenix.Endpoint, otp_app: :eexcharts

  @session_options [
    store: :cookie,
    key: "_eexcharts_dev_key",
    signing_salt: "eexchartsSB",
    same_site: "Lax"
  ]

  socket("/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]])

  # Our storybook JS/CSS (hook registration + eexcharts stylesheet import),
  # served straight from source — no bundler.
  plug(Plug.Static,
    at: "/assets",
    from: Path.expand("assets", __DIR__),
    gzip: false,
    only: ~w(storybook.js storybook.css)
  )

  # The published library assets (the hook + stylesheet), reused verbatim.
  plug(Plug.Static,
    at: "/eexcharts",
    from: {:eexcharts, "priv/static"},
    gzip: false
  )

  # Phoenix + LiveView ESM builds, imported by dev/assets/storybook.js so the
  # LiveSocket can connect and drive the EexCharts hook.
  plug(Plug.Static, at: "/vendor/phoenix", from: {:phoenix, "priv/static"}, gzip: false)

  plug(Plug.Static,
    at: "/vendor/live_view",
    from: {:phoenix_live_view, "priv/static"},
    gzip: false
  )

  plug(Plug.Session, @session_options)
  plug(Dev.Router)
end
