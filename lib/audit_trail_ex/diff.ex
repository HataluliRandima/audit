defmodule AuditTrailEx.Diff do
  @moduledoc """
  Calculates field-level diffs for Ecto changesets and structs.

  Only modified fields are recorded for updates. Sensitive fields are filtered or
  redacted according to global, schema, or per-operation rules.

  Only persisted schema fields are audited. Virtual fields (which often carry plaintext
  secrets such as `:password`) and associations (`has_many`, `belongs_to`, etc.) are never
  recorded; audit associated records with their own operations. Embedded schemas are
  recorded as their applied values.
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
    applied = Ecto.Changeset.apply_changes(changeset)

    raw_diff =
      changeset.changes
      |> Map.keys()
      |> auditable(schema)
      |> Map.new(fn field ->
        {to_string(field),
         %{"from" => nil, "to" => Serializer.serialize(Map.get(applied, field))}}
      end)

    Filter.filter_changes(raw_diff, schema, opts)
  end

  def calculate(:insert, %{__struct__: schema} = struct, opts) do
    raw_diff =
      struct
      |> persisted_values()
      |> Map.new(fn {field, value} ->
        {to_string(field), %{"from" => nil, "to" => Serializer.serialize(value)}}
      end)

    Filter.filter_changes(raw_diff, schema, opts)
  end

  def calculate(:update, %Ecto.Changeset{} = changeset, opts) do
    schema = changeset.data.__struct__
    data = changeset.data
    applied = Ecto.Changeset.apply_changes(changeset)

    raw_diff =
      changeset.changes
      |> Map.keys()
      |> auditable(schema)
      |> Enum.reduce(%{}, fn field, acc ->
        old_value = Serializer.serialize(Map.get(data, field))
        new_value = Serializer.serialize(Map.get(applied, field))

        if old_value != new_value do
          Map.put(acc, to_string(field), %{"from" => old_value, "to" => new_value})
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
      |> persisted_values()
      |> Map.new(fn {field, value} ->
        {to_string(field), %{"from" => Serializer.serialize(value), "to" => nil}}
      end)

    Filter.filter_changes(raw_diff, schema, opts)
  end

  def calculate(action, data, opts) when is_binary(action) do
    calculate(String.to_existing_atom(action), data, opts)
  end

  # Virtual fields and associations are never audited: virtual fields commonly hold
  # plaintext secrets (e.g. `:password`), and associations are separate records.
  defp auditable(fields, schema) do
    case Serializer.schema_fields(schema) do
      nil -> fields
      persisted -> Enum.filter(fields, &(&1 in persisted))
    end
  end

  defp persisted_values(%{__struct__: schema} = struct) do
    map = Map.from_struct(struct)
    fields = Serializer.schema_fields(schema) || Map.keys(map) -- [:__meta__]

    map
    |> Map.take(fields)
    |> Enum.reject(fn {_field, value} -> is_nil(value) end)
  end
end
