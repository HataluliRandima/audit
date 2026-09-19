import Config

config :audit_trail_ex,
  excluded_fields: [:password, :password_hash, :reset_token, :secret],
  redacted_fields: []

import_config "#{config_env()}.exs"
