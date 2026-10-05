defmodule AuditTrailEx.Event do
  @moduledoc """
  Ecto schema representing an audit event entry in the database.

  An audit event records an operation (`:insert`, `:update`, `:delete`) performed on
  a database record, capturing:
    * `action` - the operation performed (`:insert`, `:update`, or `:delete`)
    * `schema` - the Elixir schema module name (e.g. `"MyApp.Accounts.User"`)
    * `table` - the underlying database table name (e.g. `"users"`)
    * `record_id` - the stringified primary key of the modified record
    * `actor_id` - the stringified identifier of the user or entity responsible
    * `actor_type` - the type of actor (e.g. `"User"`, `"Admin"`, `"system"`)
    * `changes` - a map of field changes: `%{"field" => %{"from" => val, "to" => val}}`
    * `metadata` - arbitrary contextual metadata (e.g. request ID, IP address, reason)
    * `inserted_at` - UTC timestamp with microsecond precision

  ## Table Name and Primary Key Type

  By default events are stored in `audit_events` with a UUID (`:binary_id`) primary key.
  Both can be changed in your application config:

      config :audit_trail_ex,
        table_name: "system_audit_logs",
        primary_key_type: :bigserial

  These are read at compile time, so recompile the dependency after changing them
  (`mix deps.compile audit_trail_ex --force`). `AuditTrailEx.Migration` reads the same
  settings, so the table it creates always matches this schema.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @table_name Application.compile_env(:audit_trail_ex, :table_name, "audit_events")

  @primary_key (case Application.compile_env(:audit_trail_ex, :primary_key_type, :binary_id) do
                  :binary_id ->
                    {:id, :binary_id, autogenerate: true}

                  :bigserial ->
                    {:id, :id, autogenerate: true}

                  other ->
                    raise ArgumentError,
                          "invalid :primary_key_type for :audit_trail_ex: #{inspect(other)}, " <>
                            "expected :binary_id or :bigserial"
                end)

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | integer() | nil,
          action: String.t(),
          schema: String.t(),
          table: String.t(),
          record_id: String.t(),
          actor_id: String.t() | nil,
          actor_type: String.t() | nil,
          changes: map(),
          metadata: map(),
          inserted_at: DateTime.t() | nil
        }

  @valid_actions ~w(insert update delete)

  schema @table_name do
    field :action, :string
    field :schema, :string
    field :table, :string
    field :record_id, :string
    field :actor_id, :string
    field :actor_type, :string
    field :changes, :map, default: %{}
    field :metadata, :map, default: %{}

    field :inserted_at, :utc_datetime_usec
  end

  @doc """
  Builds a changeset for an audit event.

  Requires `:action`, `:schema`, `:table`, and `:record_id`.
  Automatically sets `inserted_at` to the current UTC time if not present.
  """
  @spec changeset(t() | Ecto.Changeset.t(), map()) :: Ecto.Changeset.t()
  def changeset(audit_event, attrs) do
    audit_event
    |> cast(attrs, [
      :action,
      :schema,
      :table,
      :record_id,
      :actor_id,
      :actor_type,
      :changes,
      :metadata,
      :inserted_at
    ])
    |> validate_required([:action, :schema, :table, :record_id])
    |> validate_inclusion(:action, @valid_actions)
    |> ensure_inserted_at()
  end

  defp ensure_inserted_at(changeset) do
    case get_field(changeset, :inserted_at) do
      nil -> put_change(changeset, :inserted_at, DateTime.utc_now())
      _ -> changeset
    end
  end
end
