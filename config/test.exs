import Config

# Dedicated port for the dev endpoint under test (distinct from `mix dev`'s
# 4444 so a running catalog doesn't collide with the visual suite).
port = 4488

# The storybook endpoint the visual suite drives. Started by test_helper.exs
# only when the `:visual` tests are included, so the fast SVG gate stays
# serverless and browserless.
config :eexcharts, Dev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {127, 0, 0, 1}, port: port],
  server: true,
  secret_key_base: String.duplicate("eexcharts", 8),
  live_view: [signing_salt: "eexchartsSB"],
  pubsub_server: Dev.PubSub,
  check_origin: false

config :phoenix, :json_library, Jason

# phoenix_test_playwright: drive Chromium against the endpoint above.
# assert_screenshot/3 reads/writes baselines under :snapshot_dir and writes
# diffs to <snapshot_dir>/__diff__/ on mismatch.
config :phoenix_test,
  otp_app: :eexcharts,
  endpoint: Dev.Endpoint,
  base_url: "http://127.0.0.1:#{port}",
  playwright: [
    browser: :chromium,
    headless: true,
    snapshot_dir: "test/visual/baseline",
    screenshot_dir: "test/visual/actual"
  ]
