defmodule AuditTrailEx do
  @moduledoc """
  A production-quality audit logging and change-history library for Elixir and Ecto.

  AuditTrailEx provides:
    * **Atomic Transaction Safety**: Mutations and audit events are executed in the same database transaction.
    * **Field-level Diffing**: Automatically tracks changed fields with `:from` and `:to` values.
    * **Sensitive Data Protection**: Global, schema-level, and per-call field exclusions and redactions.
    * **Flexible Actor Identification**: Protocol-based actor resolution supporting users, admins, API keys, or automated system jobs.
    * **Composable History Queries**: Query builders for filtering by record, actor, action, and date range.
    * **Human-Readable Output**: Helpers for displaying audit diffs in web UIs, notifications, and logs.
    * **First-Class Ecto.Multi Support**: Native pipeline integration.
    * **Telemetry Support**: Rich metrics and lifecycle events without sensitive data leaks.

  ## Quickstart

  ### Basic Mutation

      # Insert
      {:ok, user} = AuditTrailEx.insert(Repo, User.changeset(%User{}, params), actor: current_user)

      # Update
      {:ok, updated_user} = AuditTrailEx.update(Repo, User.changeset(user, new_params), actor: current_user)

      # Delete
      {:ok, deleted_user} = AuditTrailEx.delete(Repo, user, actor: current_user)

  ### Ecto.Multi Pipeline

      Ecto.Multi.new()
      |> AuditTrailEx.Multi.update(:user, user_changeset, actor: current_user)
      |> Repo.transaction()

  ### Querying Audit History

      # Get all audit events for a record
      events = AuditTrailEx.history(Repo, User, user.id)

      # Describe changes in human-readable terms
      AuditTrailEx.describe(List.first(events))
  """

  alias AuditTrailEx.Event
  alias AuditTrailEx.Formatter
  alias AuditTrailEx.Multi, as: AuditMulti
  alias AuditTrailEx.Query, as: AuditQuery

  @doc """
  Inserts a struct or changeset and logs an audit event within a transaction.

  When called with `Ecto.Multi`, delegates to `AuditTrailEx.Multi.insert/4`.

  ## Options

    * `:actor` - user struct, map, or identifier performing the operation
    * `:actor_id` - explicit string actor ID
    * `:actor_type` - explicit string actor type
    * `:metadata` - map of arbitrary contextual metadata
    * `:excluded_fields` - fields to exclude from logging
    * `:redacted_fields` - fields to mask with `[REDACTED]`
    * `:return_audit` - boolean, when `true` returns `{:ok, record, audit_event}` (default: `false`)

  ## Examples

      {:ok, user} = AuditTrailEx.insert(Repo, User.changeset(%User{}, attrs), actor: current_user)
  """
  @spec insert(
          module() | Ecto.Multi.t(),
          Ecto.Changeset.t() | struct() | Ecto.Multi.name(),
          keyword() | Ecto.Changeset.t() | struct()
        ) ::
          {:ok, struct()} | {:ok, struct(), Event.t() | nil} | {:error, term()} | Ecto.Multi.t()
  def insert(repo, changeset_or_struct) do
    insert(repo, changeset_or_struct, [])
  end

  def insert(%Ecto.Multi{} = multi, name, changeset_or_struct) do
    AuditMulti.insert(multi, name, changeset_or_struct, [])
  end

  def insert(repo, changeset_or_struct, opts) when is_list(opts) do
    multi =
      Ecto.Multi.new()
      |> AuditMulti.insert(:record, changeset_or_struct, opts)

    case repo.transaction(multi) do
      {:ok, %{record: record, record_audit: audit}} ->
        if Keyword.get(opts, :return_audit, false) do
          {:ok, record, audit}
        else
          {:ok, record}
        end

      {:error, :record, error_val, _} ->
        {:error, error_val}

      {:error, :record_audit, error_val, _} ->
        {:error, error_val}

      {:error, other} ->
        {:error, other}
    end
  end

  @doc """
  Inserts a struct or changeset with an `Ecto.Multi`.
  """
  @spec insert(Ecto.Multi.t(), Ecto.Multi.name(), Ecto.Changeset.t() | struct(), keyword()) ::
          Ecto.Multi.t()
  def insert(%Ecto.Multi{} = multi, name, changeset_or_struct, opts) do
    AuditMulti.insert(multi, name, changeset_or_struct, opts)
  end

  @doc """
  Updates a changeset and logs an audit event within a transaction.

  When called with `Ecto.Multi`, delegates to `AuditTrailEx.Multi.update/4`.

  ## Options

    * `:actor` - user struct, map, or identifier performing the operation
    * `:actor_id` - explicit string actor ID
    * `:actor_type` - explicit string actor type
    * `:metadata` - map of arbitrary contextual metadata
    * `:excluded_fields` - fields to exclude from logging
    * `:redacted_fields` - fields to mask with `[REDACTED]`
    * `:ignore_empty` - when `true`, skips creating audit log if no fields changed
    * `:return_audit` - boolean, when `true` returns `{:ok, record, audit_event}` (default: `false`)

  ## Examples

      {:ok, user} = AuditTrailEx.update(Repo, User.changeset(user, attrs), actor: current_user)
  """
  @spec update(
          module() | Ecto.Multi.t(),
          Ecto.Changeset.t() | Ecto.Multi.name(),
          keyword() | Ecto.Changeset.t()
        ) ::
          {:ok, struct()} | {:ok, struct(), Event.t() | nil} | {:error, term()} | Ecto.Multi.t()
  def update(repo, %Ecto.Changeset{} = changeset) do
    update(repo, changeset, [])
  end

  def update(%Ecto.Multi{} = multi, name, %Ecto.Changeset{} = changeset) do
    AuditMulti.update(multi, name, changeset, [])
  end

  def update(repo, %Ecto.Changeset{} = changeset, opts) when is_list(opts) do
    multi =
      Ecto.Multi.new()
      |> AuditMulti.update(:record, changeset, opts)

    case repo.transaction(multi) do
      {:ok, %{record: record, record_audit: audit}} ->
        if Keyword.get(opts, :return_audit, false) do
          {:ok, record, audit}
        else
          {:ok, record}
        end

      {:error, :record, error_val, _} ->
        {:error, error_val}

      {:error, :record_audit, error_val, _} ->
        {:error, error_val}

      {:error, other} ->
        {:error, other}
    end
  end

  @doc """
  Updates a changeset with an `Ecto.Multi`.
  """
  @spec update(Ecto.Multi.t(), Ecto.Multi.name(), Ecto.Changeset.t(), keyword()) ::
          Ecto.Multi.t()
  def update(%Ecto.Multi{} = multi, name, %Ecto.Changeset{} = changeset, opts) do
    AuditMulti.update(multi, name, changeset, opts)
  end

  @doc """
  Deletes a struct or changeset and logs an audit event within a transaction.

  When called with `Ecto.Multi`, delegates to `AuditTrailEx.Multi.delete/4`.

  ## Options

    * `:actor` - user struct, map, or identifier performing the operation
    * `:actor_id` - explicit string actor ID
    * `:actor_type` - explicit string actor type
    * `:metadata` - map of arbitrary contextual metadata
    * `:excluded_fields` - fields to exclude from logging
    * `:redacted_fields` - fields to mask with `[REDACTED]`
    * `:return_audit` - boolean, when `true` returns `{:ok, record, audit_event}` (default: `false`)

  ## Examples

      {:ok, user} = AuditTrailEx.delete(Repo, user, actor: current_user)
  """
  @spec delete(
          module() | Ecto.Multi.t(),
          Ecto.Changeset.t() | struct() | Ecto.Multi.name(),
          keyword() | Ecto.Changeset.t() | struct()
        ) ::
          {:ok, struct()} | {:ok, struct(), Event.t() | nil} | {:error, term()} | Ecto.Multi.t()
  def delete(repo, struct_or_changeset) do
    delete(repo, struct_or_changeset, [])
  end

  def delete(%Ecto.Multi{} = multi, name, struct_or_changeset) do
    AuditMulti.delete(multi, name, struct_or_changeset, [])
  end

  def delete(repo, struct_or_changeset, opts) when is_list(opts) do
    multi =
      Ecto.Multi.new()
      |> AuditMulti.delete(:record, struct_or_changeset, opts)

    case repo.transaction(multi) do
      {:ok, %{record: record, record_audit: audit}} ->
        if Keyword.get(opts, :return_audit, false) do
          {:ok, record, audit}
        else
          {:ok, record}
        end

      {:error, :record, error_val, _} ->
        {:error, error_val}

      {:error, :record_audit, error_val, _} ->
        {:error, error_val}

      {:error, other} ->
        {:error, other}
    end
  end

  @doc """
  Deletes a struct or changeset with an `Ecto.Multi`.
  """
  @spec delete(Ecto.Multi.t(), Ecto.Multi.name(), Ecto.Changeset.t() | struct(), keyword()) ::
          Ecto.Multi.t()
  def delete(%Ecto.Multi{} = multi, name, struct_or_changeset, opts) do
    AuditMulti.delete(multi, name, struct_or_changeset, opts)
  end

  @doc """
  General auditing helper that infers the action or delegates to `insert`, `update`, or `delete`.

  Can accept an `Ecto.Changeset` or struct.
  """
  @spec audit(module(), Ecto.Changeset.t() | struct(), keyword()) ::
          {:ok, struct()} | {:ok, struct(), Event.t() | nil} | {:error, term()}
  def audit(repo, changeset_or_struct, opts \\ [])

  def audit(repo, %Ecto.Changeset{action: :delete} = cs, opts), do: delete(repo, cs, opts)
  def audit(repo, %Ecto.Changeset{action: :update} = cs, opts), do: update(repo, cs, opts)
  def audit(repo, %Ecto.Changeset{action: :insert} = cs, opts), do: insert(repo, cs, opts)

  def audit(repo, %Ecto.Changeset{} = cs, opts) do
    case Keyword.get(opts, :action) do
      :delete ->
        delete(repo, cs, opts)

      :update ->
        update(repo, cs, opts)

      :insert ->
        insert(repo, cs, opts)

      _ ->
        if cs.data && primary_key_present?(cs.data) do
          update(repo, cs, opts)
        else
          insert(repo, cs, opts)
        end
    end
  end

  def audit(repo, struct, opts) when is_struct(struct) do
    case Keyword.get(opts, :action, :insert) do
      :delete ->
        delete(repo, struct, opts)

      :insert ->
        insert(repo, struct, opts)

      :update ->
        raise ArgumentError, "AuditTrailEx.audit/3 requires an Ecto.Changeset for updates"
    end
  end

  @doc """
  Retrieves audit history for a given schema and record ID.

  ## Examples

      events = AuditTrailEx.history(Repo, User, user.id)
      events = AuditTrailEx.history(Repo, User, user.id, action: :update, limit: 10)
  """
  @spec history(module(), module() | String.t(), term(), keyword()) :: [Event.t()]
  def history(repo, schema, record_id, opts \\ []) do
    AuditQuery.base()
    |> AuditQuery.for_record(schema, record_id)
    |> AuditQuery.filter(opts)
    |> repo.all()
  end

  @doc """
  Retrieves audit events associated with a specific actor ID.
  """
  @spec by_actor(module(), term(), keyword()) :: [Event.t()]
  def by_actor(repo, actor_id, opts \\ []) do
    actor_type = Keyword.get(opts, :actor_type)

    AuditQuery.base()
    |> AuditQuery.by_actor(actor_id, actor_type)
    |> AuditQuery.filter(opts)
    |> repo.all()
  end

  @doc """
  Retrieves audit events by action (`:insert`, `:update`, or `:delete`).
  """
  @spec by_action(module(), atom() | String.t(), keyword()) :: [Event.t()]
  def by_action(repo, action, opts \\ []) do
    AuditQuery.base()
    |> AuditQuery.by_action(action)
    |> AuditQuery.filter(opts)
    |> repo.all()
  end

  @doc """
  Describes field changes in a structured format (`AuditTrailEx.ChangeDescription`).
  """
  @spec describe(Event.t() | map()) :: [AuditTrailEx.ChangeDescription.t()]
  def describe(event_or_changes), do: Formatter.describe(event_or_changes)

  @doc """
  Formats field changes into human-readable text.
  """
  @spec describe_text(Event.t() | map() | [AuditTrailEx.ChangeDescription.t()]) :: String.t()
  def describe_text(event_or_changes), do: Formatter.to_text(event_or_changes)

  defp primary_key_present?(%{__struct__: schema} = data) do
    if function_exported?(schema, :__schema__, 1) do
      pks = schema.__schema__(:primary_key)
      Enum.all?(pks, fn pk -> not is_nil(Map.get(data, pk)) end)
    else
      not is_nil(Map.get(data, :id))
    end
  end

  defp primary_key_present?(_), do: false
end
