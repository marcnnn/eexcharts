defmodule Dev.Router do
  @moduledoc """
  Dev/test-only router mounting the phoenix_storybook catalog at `/storybook`.
  """
  use Phoenix.Router

  import PhoenixStorybook.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  scope "/" do
    # phoenix_storybook's own framework JS/CSS (served by its controllers).
    storybook_assets()
  end

  scope "/" do
    pipe_through(:browser)

    live_storybook("/storybook", backend_module: Dev.Storybook)
  end
end
