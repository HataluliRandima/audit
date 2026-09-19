defmodule AuditTrailEx.Serializer do
  @moduledoc """
  Converts arbitrary Elixir and Ecto data types into JSON-serializable primitives.

  Handles:
    * `Decimal` -> ISO string representation via `Decimal.to_string/1`
    * `Date`, `Time`, `DateTime`, `NaiveDateTime` -> ISO 8601 strings
    * Structs -> maps without `:__meta__` and internal keys
    * Maps -> maps with string keys and serialized values
    * Lists & Tuples -> lists with serialized elements
    * Atoms -> strings (except `nil`, `true`, `false`)
    * Primitive values (`integer`, `float`, `binary`, `boolean`, `nil`) -> unchanged
  """

  @doc """
  Recursively serializes any value into JSON-safe data structures.

  ## Examples

      iex> AuditTrailEx.Serializer.serialize(~D[2026-09-19])
      "2026-09-19"

      iex> AuditTrailEx.Serializer.serialize(Decimal.new("19.99"))
      "19.99"

      iex> AuditTrailEx.Serializer.serialize(%{role: :admin, active: true})
      %{"role" => "admin", "active" => true}
  """
  @spec serialize(term()) :: term()
  def serialize(nil), do: nil
  def serialize(true), do: true
  def serialize(false), do: false

  def serialize(%Decimal{} = decimal), do: Decimal.to_string(decimal)
  def serialize(%Date{} = date), do: Date.to_iso8601(date)
  def serialize(%Time{} = time), do: Time.to_iso8601(time)
  def serialize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  def serialize(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)

  def serialize(%{__struct__: _} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> serialize()
  end

  def serialize(map) when is_map(map) do
    Map.new(map, fn {key, val} ->
      {to_string(key), serialize(val)}
    end)
  end

  def serialize(list) when is_list(list) do
    Enum.map(list, &serialize/1)
  end

  def serialize(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> serialize()
  end

  def serialize(atom) when is_atom(atom), do: Atom.to_string(atom)

  def serialize(value)
      when is_binary(value) or is_integer(value) or is_float(value) do
    value
  end

  def serialize(other), do: inspect(other)
end
