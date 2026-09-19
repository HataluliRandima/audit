defmodule AuditTrailEx.TestRepo do
  @moduledoc false
  use Ecto.Repo,
    otp_app: :audit_trail_ex,
    adapter: Ecto.Adapters.Postgres
end
