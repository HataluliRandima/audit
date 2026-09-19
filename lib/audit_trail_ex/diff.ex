defmodule AuditTrailEx.Diff do
  @moduledoc """
  Calculates field-level diffs for Ecto changesets and structs.

  Only modified fields are recorded for updates. Sensitive fields are filtered or
  redacted according to global, schema, or per-operation rules.
  """

  alias AuditTrailEx.Filter
  alias AuditTrailEx.Serializer

  @doc """
  Calculates field-level changes for the specified action.

  Supported actions:
    * `:insert` - records `{from: nil, to: new_value}`
    * `:update` - records `{from: old_value, to: new_value}` for modified fields only
    * `:delete` - records `{from: old_value, to: nil}`

  ## Examples

      # Update
      changeset = Ecto.Changeset.change(user, %{name: "Alice"})
      AuditTrailEx.Diff.calculate(:update, changeset)
      #=> %{"name" => %{from: "Bob", to: "Alice"}}
  """
  @spec calculate(atom() | String.t(), Ecto.Changeset.t() | struct(), keyword()) :: map()
  def calculate(action, data, opts \\ [])

  def calculate(:insert, %Ecto.Changeset{} = changeset, opts) do
    schema = changeset.data.__struct__

    raw_diff =
      changeset.changes
      |> Enum.map(fn {field, value} ->
        {to_string(field), %{"from" => nil, "to" => Serializer.serialize(value)}}
      end)
      |> Map.new()

    Filter.filter_changes(raw_diff, schema, opts)
  end

  def calculate(:insert, %{__struct__: schema} = struct, opts) do
    raw_diff =
      struct
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Enum.reject(fn {_field, value} -> is_nil(value) end)
      |> Enum.map(fn {field, value} ->
        {to_string(field), %{"from" => nil, "to" => Serializer.serialize(value)}}
      end)
      |> Map.new()

    Filter.filter_changes(raw_diff, schema, opts)
  end

  def calculate(:update, %Ecto.Changeset{} = changeset, opts) do
    schema = changeset.data.__struct__
    data = changeset.data

    raw_diff =
      changeset.changes
      |> Enum.reduce(%{}, fn {field, new_value}, acc ->
        old_value = Map.get(data, field)

        if values_differ?(old_value, new_value) do
          diff = %{
            "from" => Serializer.serialize(old_value),
            "to" => Serializer.serialize(new_val_or_changeset(new_value))
          }

          Map.put(acc, to_string(field), diff)
        else
          acc
        end
      end)

    Filter.filter_changes(raw_diff, schema, opts)
  end

  def calculate(:delete, %Ecto.Changeset{} = changeset, opts) do
    calculate(:delete, changeset.data, opts)
  end

  def calculate(:delete, %{__struct__: schema} = struct, opts) do
    raw_diff =
      struct
      |> Map.from_struct()
      |> Map.drop([:__meta__])
      |> Enum.reject(fn {_field, value} -> is_nil(value) end)
      |> Enum.map(fn {field, value} ->
        {to_string(field), %{"from" => Serializer.serialize(value), "to" => nil}}
      end)
      |> Map.new()

    Filter.filter_changes(raw_diff, schema, opts)
  end

  def calculate(action, data, opts) when is_binary(action) do
    calculate(String.to_existing_atom(action), data, opts)
  end

  defp values_differ?(old_val, new_val) do
    Serializer.serialize(old_val) != Serializer.serialize(new_val)
  end

  defp new_val_or_changeset(%Ecto.Changeset{} = cs), do: Ecto.Changeset.apply_changes(cs)
  defp new_val_or_changeset(val), do: val
end
