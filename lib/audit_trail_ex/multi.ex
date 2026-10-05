defmodule AuditTrailEx.Multi do
  @moduledoc """
  First-class `Ecto.Multi` integration for atomic, transaction-safe audit logging.

  Ensures that the database mutation and the corresponding audit log entry either succeed
  together or fail together in the same database transaction.
  """

  alias AuditTrailEx.ActorHelper
  alias AuditTrailEx.Diff
  alias AuditTrailEx.Event
  alias AuditTrailEx.Telemetry
  alias AuditTrailEx.Trigger

  @doc """
  Adds an insert operation and its corresponding audit event to the `Ecto.Multi`.

  ## Options

    * `:actor` - the actor performing the change
    * `:actor_id` - explicit string actor ID
    * `:actor_type` - explicit string actor type
    * `:metadata` - map of arbitrary contextual metadata
    * `:audit_name` - custom multi step name (defaults to `:"\#{name}_audit"`)
    * `:excluded_fields` - list of fields to exclude from logging
    * `:redacted_fields` - list of fields to redact

  ## Example

      Ecto.Multi.new()
      |> AuditTrailEx.Multi.insert(:user, user_changeset, actor: current_user)
      |> Repo.transaction()
  """
  @spec insert(Ecto.Multi.t(), Ecto.Multi.name(), Ecto.Changeset.t() | struct(), keyword()) ::
          Ecto.Multi.t()
  def insert(multi, name, changeset_or_struct, opts \\ []) do
    audit_name = Keyword.get(opts, :audit_name, :"#{name}_audit")

    multi
    |> Trigger.skip_steps(name, &Ecto.Multi.insert(&1, name, changeset_or_struct))
    |> Ecto.Multi.run(audit_name, fn repo, results ->
      record = Map.fetch!(results, name)
      create_audit_event(repo, :insert, record, changeset_or_struct, opts)
    end)
  end

  @doc """
  Adds an update operation and its corresponding audit event to the `Ecto.Multi`.

  ## Options

    * `:actor` - the actor performing the change
    * `:actor_id` - explicit string actor ID
    * `:actor_type` - explicit string actor type
    * `:metadata` - map of arbitrary contextual metadata
    * `:audit_name` - custom multi step name (defaults to `:"\#{name}_audit"`)
    * `:excluded_fields` - list of fields to exclude from logging
    * `:redacted_fields` - list of fields to redact
    * `:ignore_empty` - when `true`, skips creating an audit event if no fields changed (default: `false`)

  ## Example

      Ecto.Multi.new()
      |> AuditTrailEx.Multi.update(:user, user_changeset, actor: current_user)
      |> Repo.transaction()
  """
  @spec update(Ecto.Multi.t(), Ecto.Multi.name(), Ecto.Changeset.t(), keyword()) ::
          Ecto.Multi.t()
  def update(multi, name, %Ecto.Changeset{} = changeset, opts \\ []) do
    audit_name = Keyword.get(opts, :audit_name, :"#{name}_audit")

    multi
    |> Trigger.skip_steps(name, &Ecto.Multi.update(&1, name, changeset))
    |> Ecto.Multi.run(audit_name, fn repo, results ->
      record = Map.fetch!(results, name)
      create_audit_event(repo, :update, record, changeset, opts)
    end)
  end

  @doc """
  Adds a delete operation and its corresponding audit event to the `Ecto.Multi`.

  ## Options

    * `:actor` - the actor performing the change
    * `:actor_id` - explicit string actor ID
    * `:actor_type` - explicit string actor type
    * `:metadata` - map of arbitrary contextual metadata
    * `:audit_name` - custom multi step name (defaults to `:"\#{name}_audit"`)
    * `:excluded_fields` - list of fields to exclude from logging
    * `:redacted_fields` - list of fields to redact

  ## Example

      Ecto.Multi.new()
      |> AuditTrailEx.Multi.delete(:user, user, actor: current_user)
      |> Repo.transaction()
  """
  @spec delete(Ecto.Multi.t(), Ecto.Multi.name(), Ecto.Changeset.t() | struct(), keyword()) ::
          Ecto.Multi.t()
  def delete(multi, name, struct_or_changeset, opts \\ []) do
    audit_name = Keyword.get(opts, :audit_name, :"#{name}_audit")

    multi
    |> Trigger.skip_steps(name, &Ecto.Multi.delete(&1, name, struct_or_changeset))
    |> Ecto.Multi.run(audit_name, fn repo, results ->
      record = Map.fetch!(results, name)
      create_audit_event(repo, :delete, record, struct_or_changeset, opts)
    end)
  end

  @doc """
  Appends an audit step to an existing operation in an `Ecto.Multi`.

  Useful when an operation was already registered in the multi. If the target table has an
  audit trigger (see `AuditTrailEx.Trigger`), the trigger records the operation too.
  """
  @spec audit(Ecto.Multi.t(), Ecto.Multi.name(), Ecto.Multi.name(), keyword()) ::
          Ecto.Multi.t()
  def audit(multi, audit_name, target_name, opts) do
    action = Keyword.fetch!(opts, :action)
    changeset_or_data = Keyword.get(opts, :changeset)

    Ecto.Multi.run(multi, audit_name, fn repo, results ->
      record = Map.fetch!(results, target_name)
      data_for_diff = changeset_or_data || record
      create_audit_event(repo, action, record, data_for_diff, opts)
    end)
  end

  defp create_audit_event(repo, action, record, data_for_diff, opts) do
    schema = get_schema(record)
    table = get_table(schema)
    record_id = extract_record_id(record, schema)

    start_time = System.monotonic_time()
    diff = Diff.calculate(action, data_for_diff, opts)
    diff_duration = System.monotonic_time() - start_time
    Telemetry.diff_calculated(action, schema, diff, diff_duration)

    ignore_empty = Keyword.get(opts, :ignore_empty, false)

    if action == :update and map_size(diff) == 0 and ignore_empty do
      {:ok, nil}
    else
      {actor_id, actor_type} = ActorHelper.resolve(opts)
      metadata = opts |> Keyword.get(:metadata, %{}) |> AuditTrailEx.Serializer.serialize()

      params = %{
        action: to_string(action),
        schema: inspect(schema),
        table: table,
        record_id: record_id,
        actor_id: actor_id,
        actor_type: actor_type,
        changes: diff,
        metadata: metadata,
        inserted_at: DateTime.utc_now()
      }

      changeset = Event.changeset(%Event{}, params)

      case repo.insert(changeset) do
        {:ok, event} ->
          total_duration = System.monotonic_time() - start_time
          Telemetry.event_created(event, total_duration)
          {:ok, event}

        {:error, cs} ->
          {:error, cs}
      end
    end
  end

  defp get_schema(%{__struct__: schema}), do: schema
  defp get_schema(%Ecto.Changeset{data: %{__struct__: schema}}), do: schema

  defp get_table(schema) do
    if function_exported?(schema, :__schema__, 1) do
      schema.__schema__(:source)
    else
      "unknown"
    end
  end

  defp extract_record_id(record, schema) do
    if function_exported?(schema, :__schema__, 1) do
      schema.__schema__(:primary_key)
      |> format_pks(record)
    else
      record |> Map.get(:id) |> to_string()
    end
  end

  defp format_pks([single_pk], record) do
    record |> Map.get(single_pk) |> to_string()
  end

  defp format_pks(pks, record) when is_list(pks) and length(pks) > 1 do
    Enum.map_join(pks, ":", fn pk -> to_string(Map.get(record, pk)) end)
  end

  defp format_pks(_pks, record) do
    record |> Map.get(:id) |> to_string()
  end
end
