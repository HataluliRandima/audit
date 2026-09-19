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

  ## Primary Keys
  The default schema uses a binary UUID primary key (`:binary_id`). The table can also be
  configured for integer or bigint primary keys if specified in custom migrations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
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

  schema "audit_events" do
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
