defmodule AuditTrailEx.MigrationTest do
  use ExUnit.Case, async: true

  alias AuditTrailEx.Migration

  test "raises when :table_name differs from the configured table" do
    assert_raise ArgumentError, ~r/table_name: :other_table does not match/, fn ->
      Migration.up(table_name: :other_table)
    end
  end

  test "raises when :primary_key_type differs from the configured type" do
    other = if AuditTrailEx.Event.__schema__(:type, :id) == :id, do: :binary_id, else: :bigserial

    assert_raise ArgumentError, ~r/primary_key_type: #{inspect(other)} does not match/, fn ->
      Migration.up(primary_key_type: other)
    end
  end
end
