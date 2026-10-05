defmodule AuditTrailEx.Migration do
  @moduledoc """
  Migration helper for creating and managing the `audit_events` table.

  ## Usage in your application

  Create a migration with `mix ecto.gen.migration create_audit_events`, then invoke:

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

  ## Custom Table Name or Primary Key Type

  The table name and primary key type come from your application config, so the table
  always matches `AuditTrailEx.Event`:

  ```elixir
  config :audit_trail_ex,
    table_name: "system_audit_logs",
    primary_key_type: :bigserial
  ```

  The `:table_name` and `:primary_key_type` options are still accepted, but raise if they
  differ from the configured values.

  ## Options

    * `:gin_index` - create GIN indexes on `changes` and `metadata` (default: `true`).
      Only applies to PostgreSQL; ignored on other adapters.
  """

  use Ecto.Migration

  alias AuditTrailEx.Event

  @doc """
  Runs the migration to create the audit events table and indexes.
  """
  @spec up(keyword()) :: :ok
  def up(opts \\ []) do
    table_name = table_name(opts)
    primary_key_type = primary_key_type(opts)
    with_gin_index = Keyword.get(opts, :gin_index, true)

    create_if_not_exists table(table_name, primary_key: false) do
      add :id, primary_key_type, primary_key: true

      add :action, :string, null: false
      add :schema, :string, null: false
      add :table, :string, null: false
      add :record_id, :string, null: false
      add :actor_id, :string
      add :actor_type, :string
      add :changes, :map, null: false, default: %{}
      add :metadata, :map, null: false, default: %{}
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create_if_not_exists index(table_name, [:schema, :record_id])
    create_if_not_exists index(table_name, [:actor_type, :actor_id])
    create_if_not_exists index(table_name, [:action])
    create_if_not_exists index(table_name, [:inserted_at])

    # GIN indexes speed up JSONB queries on `changes` and `metadata` (PostgreSQL only).
    if with_gin_index and postgres?() do
      create_if_not_exists index(table_name, [:changes],
                             using: "GIN",
                             name: :"#{table_name}_changes_gin_idx"
                           )

      create_if_not_exists index(table_name, [:metadata],
                             using: "GIN",
                             name: :"#{table_name}_metadata_gin_idx"
                           )
    end

    :ok
  end

  @doc """
  Rolls back the audit events table.
  """
  @spec down(keyword()) :: :ok
  def down(opts \\ []) do
    drop_if_exists table(table_name(opts))
    :ok
  end

  defp postgres?, do: repo().__adapter__() == Ecto.Adapters.Postgres

  defp table_name(opts) do
    configured = Event.__schema__(:source)
    check_option!(opts, :table_name, configured, &to_string/1)
    String.to_atom(configured)
  end

  defp primary_key_type(opts) do
    configured =
      case Event.__schema__(:type, :id) do
        :binary_id -> :binary_id
        :id -> :bigserial
      end

    check_option!(opts, :primary_key_type, configured, & &1)
    configured
  end

  defp check_option!(opts, key, configured, normalize) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when value != nil ->
        if normalize.(value) != configured do
          raise ArgumentError,
                "AuditTrailEx.Migration option #{key}: #{inspect(value)} does not match " <>
                  "AuditTrailEx.Event (#{inspect(configured)}). Set `config :audit_trail_ex, " <>
                  "#{key}: #{inspect(value)}` and recompile with " <>
                  "`mix deps.compile audit_trail_ex --force` instead."
        end

      _ ->
        :ok
    end
  end
end
