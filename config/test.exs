import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Run Oban jobs inline/manually in tests (no queues, no cron)
config :feed_pug, Oban, testing: :manual

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :feed_pug, FeedPug.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  port: String.to_integer(System.get_env("DB_PORT") || "5432"),
  database: "feed_pug_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :feed_pug, FeedPugWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "jRq6jUSVTd80cuwvrxpg3cUOXlk74CDNvd2mMNYWCipVR6kHXnbDp/I+NU+ao12+",
  server: false

# In test we don't send emails
config :feed_pug, FeedPug.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# The generated registration tests self-register without an invite.
config :feed_pug, :registration_open, true
