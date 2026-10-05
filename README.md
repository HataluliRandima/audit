# AuditTrailEx

[![CI](https://github.com/hata/audit_trail_ex/actions/workflows/ci.yml/badge.svg)](https://github.com/hata/audit_trail_ex/actions/workflows/ci.yml)
[![Hex.pm](https://img.shields.io/hexpm/v/audit_trail_ex.svg)](https://hex.pm/packages/audit_trail_ex)
[![Hexdocs.pm](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/audit_trail_ex)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**AuditTrailEx** is a production-ready, transaction-safe audit logging and change-history library for Elixir applications using Ecto.

It provides automated field-level diff calculation, granular sensitive-field exclusion and redaction, flexible actor identification, structured change formatting, and seamless `Ecto.Multi` pipeline integration.

---

## Why AuditTrailEx?

Many existing audit solutions in the Elixir ecosystem either:
1. Force heavy framework dependencies like Phoenix or specific session plugs.
2. Store entire snapshot duplicates of rows on every update rather than granular field diffs.
3. Lack built-in protection against leaking sensitive credentials or passwords into audit tables.
4. Execute audit writes outside or after database transactions, risking inconsistency if operations fail.

**AuditTrailEx** was engineered from the ground up to solve these challenges:
* **Zero Cruft & Framework Agnostic**: Depends solely on `Ecto` and `Jason`. Phoenix and Plug remain 100% optional.
* **Strict Transaction Safety**: Database mutations and audit events commit atomically in the same database transaction.
* **Field-Level Diffing**: Only changed fields are stored for updates (`from` and `to`), drastically saving storage.
* **Proactive Sensitive Data Protection**: Hierarchical exclusion and redaction guarantees secrets never touch logs.
* **Flexible Actor Architecture**: Track authenticated users, admins, API keys, workers, or automated system tasks.
* **Human-Readable Presentation**: Out-of-the-box structured change descriptions and plain-text summaries.
* **Telemetry Built-in**: Safe metric emission with zero data-leak risk.

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

If your application prefers integer autoincrement primary keys or a different table name:

```elixir
# Using bigserial primary keys:
AuditTrailEx.Migration.up(primary_key_type: :bigserial)

# Custom table name:
AuditTrailEx.Migration.up(table_name: :system_audit_logs)
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

---

## Performance & Maintenance

* **Composite Indexes**: The default migration adds optimized composite indexes for `[:schema, :record_id]` and `[:actor_type, :actor_id]`, as well as `[:action]` and `[:inserted_at]`.
* **GIN Indexes on JSONB**: For PostgreSQL installations, GIN indexes are automatically created on `changes` and `metadata` to support fast JSON path queries.
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

