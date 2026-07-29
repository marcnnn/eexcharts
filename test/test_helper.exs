# Visual (browser) tests are excluded by default; run them with
# `mix test --only visual` (see test/visual_test.exs). The SVG golden gate and
# the unit tests need neither a browser nor a running server.
#
# `:pending` marks the known-failing tests in test/edge_cases_test.exs — one per
# tracked defect. Run them with `mix test --include pending`.
ExUnit.start(exclude: [:visual, :pending])

# Boot the storybook endpoint only when the visual suite is actually included,
# so the everyday `mix test` stays serverless.
if :visual in (ExUnit.configuration()[:include] || []) do
  {:ok, _} =
    Supervisor.start_link(
      [
        {Phoenix.PubSub, name: Dev.PubSub},
        Dev.Endpoint
      ],
      strategy: :one_for_one
    )

  # phoenix_test_playwright has no OTP `mod:`, so its browser pool
  # (:default_pool, which every :visual test checks out in setup_all) is not
  # started automatically — start it here, only when the visual suite runs.
  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
end
