defprotocol AuditTrailEx.Actor do
  @moduledoc """
  Protocol for extracting identity and type information from an actor.

  Can be implemented for custom schemas (e.g. `%User{}`, `%Admin{}`) or used with
  standard maps and primitives via default fallback implementations.
  """

  @fallback_to_any true

  @doc """
  Returns a tuple of `{actor_id, actor_type}` as strings, or `{nil, nil}`.
  """
  @spec identify(term()) :: {String.t() | nil, String.t() | nil}
  def identify(actor)
end

defimpl AuditTrailEx.Actor, for: Any do
  def identify(nil), do: {nil, "system"}

  def identify(%{__struct__: struct} = data) do
    id = Map.get(data, :id) || Map.get(data, "id")
    type = struct |> Module.split() |> List.last()
    {to_string_or_nil(id), type}
  end

  def identify(map) when is_map(map) do
    id = Map.get(map, :id) || Map.get(map, "id")
    type = Map.get(map, :type) || Map.get(map, "type") || "user"
    {to_string_or_nil(id), to_string_or_nil(type)}
  end

  def identify(id) when is_binary(id) or is_integer(id) do
    {to_string(id), "actor"}
  end

  def identify(other) do
    {inspect(other), "unknown"}
  end

  defp to_string_or_nil(nil), do: nil
  defp to_string_or_nil(val), do: to_string(val)
end

defmodule AuditTrailEx.ActorHelper do
  @moduledoc false

  @doc """
  Resolves `{actor_id, actor_type}` from keyword options or an actor term.
  """
  @spec resolve(keyword() | term()) :: {String.t() | nil, String.t() | nil}
  def resolve(opts) when is_list(opts) do
    actor = Keyword.get(opts, :actor)
    {id_from_actor, type_from_actor} = AuditTrailEx.Actor.identify(actor)

    explicit_id = Keyword.get(opts, :actor_id)
    explicit_type = Keyword.get(opts, :actor_type)

    final_id = (explicit_id && to_string(explicit_id)) || id_from_actor
    final_type = (explicit_type && to_string(explicit_type)) || type_from_actor

    {final_id, final_type}
  end

  def resolve(actor), do: AuditTrailEx.Actor.identify(actor)
end
