# Visual (browser) tests are excluded by default; run them with
# `mix test --only visual` (see test/visual_test.exs). The SVG golden gate and
# the unit tests need neither a browser nor a running server.
ExUnit.start(exclude: [:visual])

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
end
