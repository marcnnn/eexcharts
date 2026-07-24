# Boots the dev-only Phoenix server that hosts the eexcharts storybook catalog.
#
#   mix dev            # -> http://localhost:4444/storybook
#   PORT=4000 mix dev
#
# Modeled on Phoenix.LiveDashboard's dev.exs: endpoint config is set inline via
# Application.put_env (no config/dev.exs needed), then PubSub + the endpoint are
# started under a supervisor. None of this ships in the Hex package.

require Logger

port = String.to_integer(System.get_env("PORT", "4444"))

Application.put_env(:eexcharts, Dev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: port],
  server: true,
  secret_key_base: String.duplicate("eexcharts", 8),
  live_view: [signing_salt: "eexchartsSB"],
  pubsub_server: Dev.PubSub,
  check_origin: false,
  debug_errors: true,
  code_reloader: false
)

children = [
  {Phoenix.PubSub, name: Dev.PubSub},
  Dev.Endpoint
]

{:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

Logger.info("EexCharts storybook running at http://localhost:#{port}/storybook")

Process.sleep(:infinity)
