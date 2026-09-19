import Config

config :audit_trail_ex, AuditTrailEx.TestRepo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "audit_trail_ex_dev",
  port: 5432,
  pool_size: 10
