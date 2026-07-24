import Config

# This project is a library, so there is no base config. Only the dev/test
# harness (the storybook server + visual suite) needs configuration; load the
# per-environment file when it exists.
env_config = Path.expand("#{config_env()}.exs", __DIR__)
if File.exists?(env_config), do: import_config("#{config_env()}.exs")
