defmodule AuditTrailEx.TelemetryTest do
  use ExUnit.Case, async: false

  alias AuditTrailEx.Event
  alias AuditTrailEx.Telemetry

  setup do
    test_pid = self()
    handler_id = "test-telemetry-handler-#{System.unique_integer()}"

    :telemetry.attach_many(
      handler_id,
      [
        [:audit_trail_ex, :event, :created],
        [:audit_trail_ex, :diff, :calculated]
      ],
      fn event_name, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event_name, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    :ok
  end

  test "emits [:audit_trail_ex, :event, :created] with sanitized metadata" do
    event = %Event{
      action: "update",
      schema: "MyApp.User",
      table: "users",
      record_id: "42",
      actor_type: "Admin",
      changes: %{
        "email" => %{"from" => "secret@old.com", "to" => "secret@new.com"},
        "name" => %{"from" => "Bob", "to" => "Bobby"}
      }
    }

    Telemetry.event_created(event, 500)

    assert_receive {:telemetry_event, [:audit_trail_ex, :event, :created], measurements, metadata}

    assert measurements.duration == 500
    assert measurements.changed_fields_count == 2

    assert metadata.action == "update"
    assert metadata.schema == "MyApp.User"
    assert metadata.table == "users"
    assert metadata.record_id == "42"
    assert metadata.actor_type == "Admin"
    assert Enum.sort(metadata.fields) == ["email", "name"]

    # Ensure no raw field values are leaked into metadata
    metadata_string = inspect(metadata)
    refute metadata_string =~ "secret@old.com"
    refute metadata_string =~ "secret@new.com"
    refute metadata_string =~ "Bobby"
  end

  test "emits [:audit_trail_ex, :diff, :calculated]" do
    changes = %{"name" => %{from: "A", to: "B"}}
    Telemetry.diff_calculated(:update, "User", changes, 120)

    assert_receive {:telemetry_event, [:audit_trail_ex, :diff, :calculated], measurements,
                    metadata}

    assert measurements.duration == 120
    assert measurements.fields_count == 1
    assert metadata.action == "update"
    assert metadata.schema == "User"
    assert metadata.fields == ["name"]
  end
end
