defmodule AuditTrailEx.Trigger do
  @moduledoc """
  Optional PostgreSQL trigger-based capture.

  `AuditTrailEx.insert/3`, `update/3`, `delete/3` and `AuditTrailEx.Multi` only audit the
  changes made through them. Database triggers also capture changes made any other way:
  plain `Repo` calls, `Repo.insert_all/3`, `Repo.update_all/3`, `Repo.delete_all/2`, raw SQL,
  or a `psql` session. Requires PostgreSQL 13 or later.

  ## Setup

  Install the trigger function once, then attach it to each table you want to audit:

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

  When given an Ecto schema module, `create/2` resolves the primary key, the schema name
  stored on each event, and the excluded and redacted fields (global config, the schema's
  `__audit_trail_options__/0`, and the `:excluded_fields` / `:redacted_fields` options).
  These are fixed into the trigger when the migration runs: after changing them, drop and
  re-create the trigger in a new migration.

  ## Avoiding duplicate events

  When a table has a trigger, a write through `AuditTrailEx.update/3` would be recorded twice:
  once by AuditTrailEx and once by the trigger. Enable trigger capture in your config:

      config :audit_trail_ex, trigger_capture: true

  AuditTrailEx then tells the trigger to skip the statements it audits itself. Other
  statements in the same transaction are still captured. `AuditTrailEx.Multi.audit/4`
  attaches to a step it did not run, so on a table with a trigger it records a second event.

  ## Actor and metadata

  Triggered events record the actor and metadata set with `AuditTrailEx.with_context/3` or
  `AuditTrailEx.put_context/2`, and `actor_type: "system"` otherwise:

      AuditTrailEx.with_context(Repo, [actor: current_user, metadata: %{reason: "bulk"}], fn ->
        Repo.update_all(User, set: [role: "member"])
      end)

  ## Differences from AuditTrailEx-recorded events

    * Values use PostgreSQL's JSON representation (e.g. decimals are JSON numbers).
    * `changes` keys are column names, which differ from field names only for fields with
      a `:source` option.
    * Updates that change no columns are not recorded. `TRUNCATE` is not captured.
    * No telemetry events are emitted.
  """

  import Ecto.Migration, only: [execute: 1, execute: 2, repo: 0]

  alias AuditTrailEx.ActorHelper
  alias AuditTrailEx.Event
  alias AuditTrailEx.Filter
  alias AuditTrailEx.Serializer

  @function "audit_trail_ex_capture"
  @trigger "audit_trail_ex_capture"

  @doc """
  Creates the trigger function. Call once, in a migration, before `create/2`.
  """
  @spec install() :: :ok
  def install do
    ensure_postgres!()
    execute(function_sql(), "DROP FUNCTION IF EXISTS #{@function}()")
    :ok
  end

  @doc """
  Drops the trigger function. Drop all triggers created with `create/2` first.
  """
  @spec uninstall() :: :ok
  def uninstall do
    execute("DROP FUNCTION IF EXISTS #{@function}()")
    :ok
  end

  @doc """
  Attaches the audit trigger to a table.

  Accepts an Ecto schema module, or a table name with the `:schema` option.

  ## Options

    * `:schema` - (table name only, required) schema name stored on events, as a module
      or string. Use the schema module so `AuditTrailEx.history/4` finds the events.
    * `:primary_key` - (table name only) primary key columns (default: `[:id]`)
    * `:prefix` - database schema (PostgreSQL schema) of the table
    * `:excluded_fields` - additional fields to exclude
    * `:redacted_fields` - additional fields to redact
  """
  @spec create(module() | atom() | String.t(), keyword()) :: :ok
  def create(schema_or_table, opts \\ []) do
    ensure_postgres!()
    target = resolve(schema_or_table, opts)
    execute(create_sql(target), drop_sql(target))
    :ok
  end

  @doc """
  Removes the audit trigger from a table. Accepts the same arguments as `create/2`.
  """
  @spec drop(module() | atom() | String.t(), keyword()) :: :ok
  def drop(schema_or_table, opts \\ []) do
    execute(drop_sql(location(schema_or_table, opts)))
    :ok
  end

  @doc """
  Sets the actor and metadata recorded by triggers for the rest of the current transaction.

  Must be called inside a transaction. Accepts the same `:actor`, `:actor_id`, `:actor_type`
  and `:metadata` options as `AuditTrailEx.update/3`. The context lasts until the outermost
  transaction ends, including when called inside a nested `Repo.transaction/2`.
  """
  @spec put_context(module(), keyword()) :: :ok
  def put_context(repo, opts) do
    unless repo.in_transaction?() do
      raise ArgumentError, "AuditTrailEx.put_context/2 must be called inside a transaction"
    end

    {actor_id, actor_type} = ActorHelper.resolve(opts)
    metadata = opts |> Keyword.get(:metadata, %{}) |> Serializer.serialize() |> Jason.encode!()

    repo.query!(
      "SELECT set_config('audit_trail_ex.actor_id', $1, true), " <>
        "set_config('audit_trail_ex.actor_type', $2, true), " <>
        "set_config('audit_trail_ex.metadata', $3, true)",
      [actor_id || "", actor_type || "", metadata]
    )

    :ok
  end

  @doc false
  # Toggles trigger capture for the following statements of the current transaction.
  # Used by `AuditTrailEx.Multi` around the statements it audits itself.
  @spec skip_steps(Ecto.Multi.t(), Ecto.Multi.name(), (Ecto.Multi.t() -> Ecto.Multi.t())) ::
          Ecto.Multi.t()
  def skip_steps(multi, name, fun) do
    if Application.get_env(:audit_trail_ex, :trigger_capture, false) do
      multi
      |> Ecto.Multi.run({:audit_trail_ex_skip, name, :on}, &set_skip(&1, &2, "on"))
      |> fun.()
      |> Ecto.Multi.run({:audit_trail_ex_skip, name, :off}, &set_skip(&1, &2, "off"))
    else
      fun.(multi)
    end
  end

  defp set_skip(repo, _changes, value) do
    repo.query!("SELECT set_config('audit_trail_ex.skip', $1, true)", [value])
    {:ok, value}
  end

  defp ensure_postgres! do
    unless repo().__adapter__() == Ecto.Adapters.Postgres do
      raise ArgumentError, "AuditTrailEx.Trigger requires PostgreSQL"
    end
  end

  defp location(schema_or_table, opts) do
    if Serializer.schema_fields(schema_or_table) do
      %{
        table: schema_or_table.__schema__(:source),
        prefix: Keyword.get(opts, :prefix, schema_or_table.__schema__(:prefix))
      }
    else
      %{table: to_string(schema_or_table), prefix: Keyword.get(opts, :prefix)}
    end
  end

  defp resolve(schema_or_table, opts) do
    case Serializer.schema_fields(schema_or_table) do
      nil -> resolve_table(schema_or_table, opts)
      fields -> resolve_schema(schema_or_table, fields, opts)
    end
  end

  defp resolve_schema(schema, fields, opts) do
    source = &to_string(schema.__schema__(:field_source, &1))

    primary_key =
      case schema.__schema__(:primary_key) do
        [] -> raise ArgumentError, "#{inspect(schema)} has no primary key"
        pks -> pks
      end

    schema
    |> location(opts)
    |> Map.merge(%{
      schema: inspect(schema),
      primary_key: Enum.map(primary_key, source),
      excluded: fields |> Enum.filter(&Filter.excluded?(&1, schema, opts)) |> Enum.map(source),
      redacted: fields |> Enum.filter(&Filter.redacted?(&1, schema, opts)) |> Enum.map(source)
    })
  end

  defp resolve_table(table, opts) do
    schema =
      case Keyword.fetch(opts, :schema) do
        {:ok, schema} when is_atom(schema) -> inspect(schema)
        {:ok, schema} when is_binary(schema) -> schema
        :error -> raise ArgumentError, "AuditTrailEx.Trigger needs the :schema option for tables"
      end

    table
    |> location(opts)
    |> Map.merge(%{
      schema: schema,
      primary_key: opts |> Keyword.get(:primary_key, [:id]) |> Enum.map(&to_string/1),
      excluded: configured(:excluded_fields, opts),
      redacted: configured(:redacted_fields, opts)
    })
  end

  defp configured(key, opts) do
    (Application.get_env(:audit_trail_ex, key, []) ++ Keyword.get(opts, key, []))
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
  end

  defp create_sql(target) do
    args = [
      target.schema,
      Enum.join(target.primary_key, ","),
      Enum.join(target.excluded, ","),
      Enum.join(target.redacted, ",")
    ]

    "CREATE TRIGGER #{@trigger} AFTER INSERT OR UPDATE OR DELETE ON #{table_ref(target)} " <>
      "FOR EACH ROW EXECUTE FUNCTION #{@function}(#{Enum.map_join(args, ", ", &literal/1)})"
  end

  defp drop_sql(target), do: "DROP TRIGGER IF EXISTS #{@trigger} ON #{table_ref(target)}"

  defp table_ref(%{prefix: nil, table: table}), do: ident(table)
  defp table_ref(%{prefix: prefix, table: table}), do: "#{ident(prefix)}.#{ident(table)}"

  defp ident(name), do: ~s("#{String.replace(to_string(name), ~s("), ~s(""))}")
  defp literal(value), do: "'#{String.replace(value, "'", "''")}'"

  defp function_sql do
    {id_column, id_value} =
      case Event.__schema__(:type, :id) do
        :binary_id -> {"id, ", "gen_random_uuid(), "}
        :id -> {"", ""}
      end

    """
    CREATE OR REPLACE FUNCTION #{@function}() RETURNS trigger
    LANGUAGE plpgsql AS $$
    DECLARE
      v_old jsonb := CASE WHEN TG_OP IN ('UPDATE', 'DELETE') THEN to_jsonb(OLD) END;
      v_new jsonb := CASE WHEN TG_OP IN ('INSERT', 'UPDATE') THEN to_jsonb(NEW) END;
      v_row jsonb := coalesce(v_new, v_old);
      v_primary_key text[] := string_to_array(TG_ARGV[1], ',');
      v_excluded text[] := coalesce(string_to_array(nullif(TG_ARGV[2], ''), ','), '{}');
      v_redacted text[] := coalesce(string_to_array(nullif(TG_ARGV[3], ''), ','), '{}');
      v_changes jsonb := '{}';
      v_column text;
      v_from jsonb;
      v_to jsonb;
    BEGIN
      IF coalesce(current_setting('audit_trail_ex.skip', true), '') = 'on' THEN
        RETURN NULL;
      END IF;

      FOR v_column IN SELECT jsonb_object_keys(v_row) LOOP
        CONTINUE WHEN v_column = ANY(v_excluded);

        v_from := coalesce(v_old -> v_column, 'null');
        v_to := coalesce(v_new -> v_column, 'null');
        CONTINUE WHEN v_from = v_to;

        IF v_column = ANY(v_redacted) THEN
          IF v_from <> 'null' THEN v_from := '"[REDACTED]"'; END IF;
          IF v_to <> 'null' THEN v_to := '"[REDACTED]"'; END IF;
        END IF;

        v_changes := v_changes || jsonb_build_object(v_column, jsonb_build_object('from', v_from, 'to', v_to));
      END LOOP;

      IF TG_OP = 'UPDATE' AND v_changes = '{}' THEN
        RETURN NULL;
      END IF;

      INSERT INTO #{ident(Event.__schema__(:source))}
        (#{id_column}"action", "schema", "table", "record_id", "actor_id", "actor_type", "changes", "metadata", "inserted_at")
      VALUES (
        #{id_value}lower(TG_OP),
        TG_ARGV[0],
        TG_TABLE_NAME,
        (SELECT string_agg(v_row ->> pk, ':' ORDER BY ord) FROM unnest(v_primary_key) WITH ORDINALITY AS t(pk, ord)),
        nullif(current_setting('audit_trail_ex.actor_id', true), ''),
        coalesce(nullif(current_setting('audit_trail_ex.actor_type', true), ''), 'system'),
        v_changes,
        coalesce(nullif(current_setting('audit_trail_ex.metadata', true), '')::jsonb, '{}'),
        clock_timestamp() AT TIME ZONE 'UTC'
      );

      RETURN NULL;
    END;
    $$
    """
  end
end
