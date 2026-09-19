import Config

config :logger, level: :warning

config :audit_trail_ex, AuditTrailEx.TestRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "audit_trail_ex_test",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10

config :audit_trail_ex,
  ecto_repos: [AuditTrailEx.TestRepo]
