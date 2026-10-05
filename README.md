# AuditTrailEx

[![CI](https://github.com/HataluliRandima/audit/actions/workflows/ci.yml/badge.svg)](https://github.com/HataluliRandima/audit/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/audit_trail_ex.svg)](https://hex.pm/packages/audit_trail_ex)
[![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/audit_trail_ex)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**AuditTrailEx** is a transaction-safe audit logging and change-history library for Elixir applications using Ecto.

> **Status:** early release (0.x). The API may change before 1.0. Please read [Limitations](#limitations) before relying on it for compliance.

It provides automated field-level diff calculation, granular sensitive-field exclusion and redaction, flexible actor identification, structured change formatting, and seamless `Ecto.Multi` pipeline integration.

---

## Why AuditTrailEx?

* **Transaction Safety**: Database mutations and audit events commit atomically in the same database transaction.
* **Field-Level Diffing**: Only changed fields are stored for updates (`from` and `to`), not full row snapshots.
* **Sensitive Data Protection**: Virtual fields and associations are never recorded, and configurable exclusion/redaction keeps listed fields out of the log.
* **Framework Agnostic**: Depends on `ecto_sql`, `jason` and `telemetry`. Phoenix and Plug are optional.
* **Flexible Actor Architecture**: Track authenticated users, admins, API keys, workers, or automated system tasks.
* **Human-Readable Presentation**: Structured change descriptions and plain-text summaries.
* **Telemetry Built-in**: Metrics that include field names but never field values.

---

## Installation

Add `audit_trail_ex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:audit_trail_ex, "~> 0.1.0"}
  ]
end
```

---

## Setup & Database Migration

Generate a new Ecto migration:

```bash
mix ecto.gen.migration create_audit_events
```

Invoke `AuditTrailEx.Migration.up/1` inside your migration:

```elixir
defmodule MyApp.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def up do
    AuditTrailEx.Migration.up()
  end

  def down do
    AuditTrailEx.Migration.down()
  end
end
```

Then run:

```bash
mix ecto.migrate
```

### Custom Primary Key or Table Name

The table name and primary key type are set in config, and both `AuditTrailEx.Event` and
`AuditTrailEx.Migration` read them, so the schema and table always match:

```elixir
# config/config.exs
config :audit_trail_ex,
  table_name: "system_audit_logs",   # default: "audit_events"
  primary_key_type: :bigserial       # default: :binary_id (UUID)
```

These settings are read at compile time. After changing them, recompile the dependency:

```bash
mix deps.compile audit_trail_ex --force
```

---

## Configuration

In your `config/config.exs`:

```elixir
config :audit_trail_ex,
  excluded_fields: [:password, :password_hash, :reset_token, :api_secret],
  redacted_fields: [:ssn, :credit_card]
```

* **`excluded_fields`**: Completely omitted from the audit log diff.
* **`redacted_fields`**: Replaced with `"[REDACTED]"` in both `from` and `to` values.

---

## Usage

### 1. Basic Mutations

AuditTrailEx provides drop-in replacements for standard `Repo` mutations that execute atomically within a database transaction:

```elixir
# Insert
{:ok, user} =
  AuditTrailEx.insert(Repo, User.changeset(%User{}, user_params),
    actor: current_user,
    metadata: %{ip: "127.0.0.1", source: "admin_portal"}
  )

# Update (only records modified fields!)
{:ok, updated_user} =
  AuditTrailEx.update(Repo, User.changeset(user, %{name: "Johnny"}),
    actor: current_user
  )

# Delete (records previous values snapshot)
{:ok, deleted_user} =
  AuditTrailEx.delete(Repo, user,
    actor: current_user
  )
```

#### Returning the Audit Event
To receive both the mutated record and the generated `%AuditTrailEx.Event{}`:

```elixir
{:ok, user, audit_event} =
  AuditTrailEx.update(Repo, changeset, actor: current_user, return_audit: true)
```

---

### 2. Ecto.Multi Integration

AuditTrailEx integrates natively into `Ecto.Multi` pipelines:

```elixir
Ecto.Multi.new()
|> AuditTrailEx.Multi.update(:user, user_changeset, actor: current_user)
|> AuditTrailEx.Multi.insert(:profile, profile_changeset, actor: current_user)
|> Repo.transaction()
```

If any mutation or audit log fails, the entire transaction rolls back cleanly.

You can also attach an audit log to an existing step in an `Ecto.Multi`:

```elixir
Ecto.Multi.new()
|> Ecto.Multi.update(:user, user_changeset)
|> AuditTrailEx.Multi.audit(:user_audit, :user, action: :update, changeset: user_changeset, actor: current_user)
|> Repo.transaction()
```

---

### 3. Actor Tracking

The `:actor` option accepts:
* Any Ecto struct (e.g. `%User{id: 42}`) -> records `actor_id: "42"`, `actor_type: "User"`.
* Maps (e.g. `%{id: "admin-1", type: "superadmin"}`).
* String or integer IDs (e.g. `"cron_worker"`).
* `nil` -> records `actor_id: nil`, `actor_type: "system"`.

You can also pass explicit overrides:

```elixir
AuditTrailEx.update(Repo, changeset,
  actor_id: "sec-bot-9",
  actor_type: "security_agent"
)
```

#### Custom Actor Protocol
Implement `AuditTrailEx.Actor` for your custom domain structs:

```elixir
defimpl AuditTrailEx.Actor, for: MyApp.Accounts.Admin do
  def identify(%MyApp.Accounts.Admin{id: id, role: role}) do
    {to_string(id), "admin:\#{role}"}
  end
end
```

---

### 4. Metadata

Attach arbitrary contextual metadata to any audit event:

```elixir
AuditTrailEx.update(Repo, changeset,
  actor: current_user,
  metadata: %{
    request_id: "req_xyz123",
    client_ip: "203.0.113.42",
    user_agent: "Mozilla/5.0 ...",
    reason: "Requested by customer via support ticket #1234"
  }
)
```

#### Optional Web / Plug Integration
AuditTrailEx includes a helper module (`AuditTrailEx.Web`) to extract request metadata safely without hard Plug dependencies:

```elixir
# In a controller or plug:
metadata = AuditTrailEx.Web.extract_metadata(conn)
AuditTrailEx.update(Repo, changeset, actor: current_user, metadata: metadata)
```

---

### 5. Sensitive-Field Filtering & Redaction

Protection rules follow a 3-tier precedence hierarchy:
1. **Per-Call Options**: Passed directly to `AuditTrailEx.update(Repo, changeset, excluded_fields: [:pin])`.
2. **Per-Schema Options**: Defined via `__audit_trail_options__/0` on the schema module.
3. **Global Config**: Defined in `config :audit_trail_ex`.

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :email, :string
    field :pin_code, :string
  end

  def __audit_trail_options__ do
    [
      excluded_fields: [:pin_code],
      redacted_fields: [:email]
    ]
  end
end
```

---

### 6. Querying History

AuditTrailEx provides composable Ecto query builders:

```elixir
# Fetch all events for a specific record
history = AuditTrailEx.history(Repo, User, user.id)

# Filter by action, date range, or limit
recent_updates =
  AuditTrailEx.history(Repo, User, user.id,
    action: :update,
    since: ~U[2026-09-01 00:00:00Z],
    limit: 10
  )

# Query events by actor
actor_events = AuditTrailEx.by_actor(Repo, "admin-1", actor_type: "superadmin")

# Query events by action
all_deletions = AuditTrailEx.by_action(Repo, :delete)
```

#### Composing Custom Queries

```elixir
import Ecto.Query

AuditTrailEx.Query.base()
|> AuditTrailEx.Query.by_action(:update)
|> AuditTrailEx.Query.recent(20)
|> Repo.all()
```

---

### 7. Human-Readable Descriptions

Convert raw diff maps or `%AuditTrailEx.Event{}` structs into structured descriptions or formatted text:

```elixir
# Structured change descriptions (ideal for LiveView or React UIs):
descriptions = AuditTrailEx.describe(event)
#=> [%AuditTrailEx.ChangeDescription{field: "name", from: "Alice", to: "Alicia", kind: :changed, summary: "Name changed from \"Alice\" to \"Alicia\""}]

# Plain-text formatting (ideal for logs, Slack alerts, or email receipts):
IO.puts(AuditTrailEx.describe_text(event))
# Output:
# Update MyApp.Accounts.User [42]
#
# Name changed
#   From: "Alice"
#   To:   "Alicia"
```

---

### 8. Telemetry

AuditTrailEx dispatches standard `:telemetry` events:
* `[:audit_trail_ex, :event, :created]` - Dispatched upon successful event creation.
  * **Measurements**: `%{duration: integer(), changed_fields_count: integer()}`
  * **Metadata**: `%{action: String.t(), schema: String.t(), table: String.t(), record_id: String.t(), actor_type: String.t(), fields: [String.t()]}`
* `[:audit_trail_ex, :diff, :calculated]` - Dispatched when diff calculation finishes.

> **Security Note**: Telemetry metadata **never** includes raw field values, previous values, or new values. Only field names and structural metadata are emitted.

### 9. Capturing Changes Made Outside AuditTrailEx (PostgreSQL)

By default only writes made through AuditTrailEx are audited. To also capture plain `Repo`
calls, `update_all`/`insert_all`/`delete_all`, raw SQL and manual database changes, add
audit triggers (PostgreSQL 13+):

```elixir
defmodule MyApp.Repo.Migrations.AddAuditTriggers do
  use Ecto.Migration

  def up do
    AuditTrailEx.Trigger.install()
    AuditTrailEx.Trigger.create(MyApp.Accounts.User)
  end

  def down do
    AuditTrailEx.Trigger.drop(MyApp.Accounts.User)
    AuditTrailEx.Trigger.uninstall()
  end
end
```

The trigger uses the schema's primary key and the same excluded and redacted fields as
AuditTrailEx. These are fixed when the migration runs, so after changing them, drop and
re-create the trigger in a new migration.

Turn on `trigger_capture` so writes made through AuditTrailEx are not recorded twice:

```elixir
config :audit_trail_ex, trigger_capture: true
```

Set the actor and metadata for triggered events with `with_context/3` (or `put_context/2`
inside an existing transaction):

```elixir
AuditTrailEx.with_context(Repo, [actor: current_user, metadata: %{reason: "cleanup"}], fn ->
  Repo.update_all(User, set: [role: "member"])
end)
```

Without a context, triggered events have `actor_type: "system"`. See `AuditTrailEx.Trigger`
for how triggered events differ (e.g. decimals are stored as JSON numbers).

---

## Limitations

* **Without triggers, only changes made through AuditTrailEx are audited.** `AuditTrailEx.insert/update/delete` and `AuditTrailEx.Multi` record events; plain `Repo` calls, `insert_all`/`update_all`/`delete_all`, raw SQL, and manual database changes are only recorded on tables with [audit triggers](#9-capturing-changes-made-outside-audittrailex-postgresql). `TRUNCATE` is never recorded.
* **Associations are not audited through their parent.** Changes made with `cast_assoc` are not recorded in the parent's event; audit associated records with their own operations. Embedded schemas are recorded.
* **Exclusion and redaction are name-based.** Persisted columns holding secrets (e.g. `hashed_password`, API tokens) must be listed in `excluded_fields` or `redacted_fields`.
* **Primarily tested on PostgreSQL.** GIN indexes are only created on PostgreSQL; other Ecto SQL adapters are untested.
* **One audit table per application.** The table name and primary key type are global, compile-time settings.

---

## Performance & Maintenance

* **Composite Indexes**: The default migration adds optimized composite indexes for `[:schema, :record_id]` and `[:actor_type, :actor_id]`, as well as `[:action]` and `[:inserted_at]`.
* **GIN Indexes on JSONB**: On PostgreSQL, GIN indexes are created on `changes` and `metadata` to support fast JSON queries. Skip them with `AuditTrailEx.Migration.up(gin_index: false)`.
* **Partitioning Strategy**: For high-volume production systems generating millions of audit records per month, consider partitioning the `audit_events` table by range on `inserted_at` (e.g. monthly PostgreSQL table partitions).

---

## Running Tests

Ensure PostgreSQL is running:

```bash
docker run --name audit_trail_postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_DB=audit_trail_ex_test \
  -p 5432:5432 -d postgres:16-alpine
```

Run the ExUnit test suite:

```bash
mix test
```

Run the executable demo:

```bash
MIX_ENV=test mix run examples/demo.exs
```

Run code quality tools:

```bash
mix format --check-formatted
mix credo --strict
mix docs
```

---

## Roadmap

- [x] Optional PostgreSQL trigger-based capture, so changes made outside AuditTrailEx (`update_all`, raw SQL) are also recorded
- [ ] PostgreSQL table partitioning migration recipe
- [ ] Configurable async audit writer adapter (Oban / GenStage) for high-throughput write decoupling
- [ ] Rollback replay helper: `AuditTrailEx.revert(record, audit_event)`
- [ ] LiveView component for displaying audit history timelines

---

## Contributing

Pull requests are welcome! Please check out [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code standards and verification processes.

---

## License

AuditTrailEx is open-source software licensed under the [MIT License](LICENSE).

