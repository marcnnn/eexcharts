defmodule Dev.Storybook do
  @moduledoc """
  Dev/test-only phoenix_storybook backend for the eexcharts catalog.

  Stories live under `dev/storybook/`; the custom JS/CSS (hook registration +
  eexcharts stylesheet) are served from `dev/assets/` by `Dev.Endpoint`. The JS
  is an ES module so it can `import` the library hook and the Phoenix/LiveView
  ESM builds without a bundler.
  """
  use PhoenixStorybook,
    otp_app: :eexcharts,
    content_path: Path.expand("storybook", __DIR__),
    css_path: "/assets/storybook.css",
    js_path: "/assets/storybook.js",
    js_script_type: "module"
end
