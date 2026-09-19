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

  You can customize the table name or primary key type via options:

  ```elixir
  # Using bigint autoincrement primary key:
  AuditTrailEx.Migration.up(primary_key_type: :bigserial)

  # Custom table name:
  AuditTrailEx.Migration.up(table_name: :system_audit_logs)
  ```
  """

  use Ecto.Migration

  @doc """
  Runs the migration to create the audit events table and indexes.
  """
  @spec up(keyword()) :: :ok
  def up(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, :audit_events)
    primary_key_type = Keyword.get(opts, :primary_key_type, :binary_id)
    with_gin_index = Keyword.get(opts, :gin_index, true)

    table_opts =
      case primary_key_type do
        :binary_id -> [primary_key: false]
        :bigserial -> [primary_key: false]
        _ -> [primary_key: false]
      end

    create_if_not_exists table(table_name, table_opts) do
      case primary_key_type do
        :binary_id ->
          add :id, :binary_id, primary_key: true

        :bigserial ->
          add :id, :bigserial, primary_key: true

        custom_type ->
          add :id, custom_type, primary_key: true
      end

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

    if with_gin_index do
      # GIN indexes for PostgreSQL JSONB
      execute """
      DO $$
      BEGIN
        IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'btree_gin' OR true) THEN
          BEGIN
            CREATE INDEX IF NOT EXISTS #{table_name}_changes_gin_idx ON #{table_name} USING gin (changes);
            CREATE INDEX IF NOT EXISTS #{table_name}_metadata_gin_idx ON #{table_name} USING gin (metadata);
          EXCEPTION WHEN OTHERS THEN
            NULL;
          END;
        END IF;
      END $$;
      """
    end

    :ok
  end

  @doc """
  Rolls back the audit events table.
  """
  @spec down(keyword()) :: :ok
  def down(opts \\ []) do
    table_name = Keyword.get(opts, :table_name, :audit_events)
    drop_if_exists table(table_name)
    :ok
  end
end
