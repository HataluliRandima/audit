defmodule AuditTrailEx.Query do
  @moduledoc """
  Composable Ecto query builders for retrieving and filtering audit history.

  All functions in this module accept an existing `Ecto.Query` or queryable and return
  a modified `Ecto.Query.t()`, allowing developer flexibility when constructing
  complex queries, paginations, and joins.
  """

  import Ecto.Query
  alias AuditTrailEx.Event

  @doc """
  Returns a base query for audit events, ordered by `inserted_at` descending by default.
  """
  @spec base(Ecto.Queryable.t()) :: Ecto.Query.t()
  def base(queryable \\ Event) do
    from(e in queryable, order_by: [desc: e.inserted_at])
  end

  @doc """
  Filters audit events for a specific record.

  Accepts schema module or string, and string or integer record ID.
  """
  @spec for_record(Ecto.Queryable.t(), module() | String.t(), term()) :: Ecto.Query.t()
  def for_record(query, schema, record_id) do
    schema_str = normalize_schema(schema)
    record_id_str = to_string(record_id)

    from(e in query,
      where: e.schema == ^schema_str and e.record_id == ^record_id_str
    )
  end

  @doc """
  Filters audit events by actor ID, and optionally actor type.
  """
  @spec by_actor(Ecto.Queryable.t(), term(), String.t() | atom() | nil) :: Ecto.Query.t()
  def by_actor(query, actor_id, actor_type \\ nil)

  def by_actor(query, actor_id, nil) do
    actor_id_str = to_string(actor_id)
    from(e in query, where: e.actor_id == ^actor_id_str)
  end

  def by_actor(query, actor_id, actor_type) do
    actor_id_str = to_string(actor_id)
    actor_type_str = to_string(actor_type)

    from(e in query,
      where: e.actor_id == ^actor_id_str and e.actor_type == ^actor_type_str
    )
  end

  @doc """
  Filters audit events by operation action (`:insert`, `:update`, `:delete` or strings).
  """
  @spec by_action(Ecto.Queryable.t(), atom() | String.t()) :: Ecto.Query.t()
  def by_action(query, action) do
    action_str = to_string(action)
    from(e in query, where: e.action == ^action_str)
  end

  @doc """
  Filters audit events occurring within a specific UTC date or datetime range.
  """
  @spec in_date_range(Ecto.Queryable.t(), DateTime.t(), DateTime.t()) :: Ecto.Query.t()
  def in_date_range(query, start_time, end_time) do
    from(e in query,
      where: e.inserted_at >= ^start_time and e.inserted_at <= ^end_time
    )
  end

  @doc """
  Filters audit events occurring at or after `start_time`.
  """
  @spec since(Ecto.Queryable.t(), DateTime.t()) :: Ecto.Query.t()
  def since(query, start_time) do
    from(e in query, where: e.inserted_at >= ^start_time)
  end

  @doc """
  Filters audit events occurring at or before `end_time`.
  """
  @spec until(Ecto.Queryable.t(), DateTime.t()) :: Ecto.Query.t()
  def until(query, end_time) do
    from(e in query, where: e.inserted_at <= ^end_time)
  end

  @doc """
  Limits the number of returned events.
  """
  @spec recent(Ecto.Queryable.t(), pos_integer()) :: Ecto.Query.t()
  def recent(query, limit \\ 50) do
    from(e in query, limit: ^limit)
  end

  @doc """
  Applies multiple filters at once from a keyword list or map.

  Supported filter keys:
    * `:schema` - schema module or string
    * `:record_id` - record identifier
    * `:actor_id` - actor identifier
    * `:actor_type` - actor type
    * `:action` - `:insert`, `:update`, or `:delete`
    * `:since` - DateTime
    * `:until` - DateTime
    * `:limit` - positive integer
  """
  @spec filter(Ecto.Queryable.t(), keyword() | map()) :: Ecto.Query.t()
  def filter(query, filters) do
    Enum.reduce(filters, query, fn
      {:schema, schema}, q -> from(e in q, where: e.schema == ^normalize_schema(schema))
      {:record_id, id}, q -> from(e in q, where: e.record_id == ^to_string(id))
      {:actor_id, id}, q -> from(e in q, where: e.actor_id == ^to_string(id))
      {:actor_type, type}, q -> from(e in q, where: e.actor_type == ^to_string(type))
      {:action, action}, q -> from(e in q, where: e.action == ^to_string(action))
      {:since, start_time}, q -> since(q, start_time)
      {:until, end_time}, q -> until(q, end_time)
      {:limit, limit}, q -> recent(q, limit)
      {_key, _val}, q -> q
    end)
  end

  defp normalize_schema(schema) when is_atom(schema), do: inspect(schema)
  defp normalize_schema(schema) when is_binary(schema), do: schema
end
