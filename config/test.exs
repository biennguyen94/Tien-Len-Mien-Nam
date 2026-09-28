import Config

# Only in tests, bcrypt runs with the minimum cost so tests stay fast.
config :bcrypt_elixir, :log_rounds, 1

# Test database (same container as dev, database tien_len_test + partition for parallel runs).
config :tien_len, TienLen.Repo,
  url:
    System.get_env(
      "TEST_DATABASE_URL",
      "ecto://tien_len:tien_len_dev_only@127.0.0.1:5434/tien_len_test#{System.get_env("MIX_TEST_PARTITION")}"
    ),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Game results are not written by room processes in tests unless a test asks for it
# (see TienLen.Stats and the :recorder room option).
config :tien_len, :results_recorder, nil

# Coins are not settled by room processes in tests unless a test asks (room option :economy).
config :tien_len, :economy, nil

# Settings are not loaded from the database at start in tests (the sandbox is manual).
config :tien_len, :load_settings, false

# All test requests come from 127.0.0.1: count failed logins per username only (F8).
config :tien_len, :throttle_by_ip, false

config :tien_len, :sql_sandbox, Ecto.Adapters.SQL.Sandbox

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :tien_len, TienLenWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Vgbwh97co8uxLsdwKLCTnfiTx0N/G6nglC53dXpI1grEs5G027/bYu7YbHP/5bwm",
  server: false

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

# Bots act at once in tests (B5)
config :tien_len, :bot_delay, 0

# Seasons are paid by tests explicitly (S2)
config :tien_len, :season_payouts, false
