defmodule AuditTrailEx.Telemetry do
  @moduledoc """
  Telemetry integration for AuditTrailEx.

  AuditTrailEx emits the following Telemetry events:
    * `[:audit_trail_ex, :event, :created]` - emitted when an audit event has been successfully created
    * `[:audit_trail_ex, :diff, :calculated]` - emitted when a field-level diff calculation completes

  To prevent accidental data leakage, Telemetry metadata never contains raw field values,
  previous values, or new values. Only structural metadata such as the schema, action,
  record ID, actor type, and names of modified fields are included.
  """

  @doc """
  Dispatches an `[:audit_trail_ex, :event, :created]` event.
  """
  @spec event_created(AuditTrailEx.Event.t(), non_neg_integer()) :: :ok
  def event_created(event, duration_native \\ 0) do
    measurements = %{
      duration: duration_native,
      changed_fields_count: map_size(event.changes || %{})
    }

    metadata = %{
      action: event.action,
      schema: event.schema,
      table: event.table,
      record_id: event.record_id,
      actor_type: event.actor_type,
      fields: Map.keys(event.changes || %{})
    }

    :telemetry.execute([:audit_trail_ex, :event, :created], measurements, metadata)
  end

  @doc """
  Dispatches an `[:audit_trail_ex, :diff, :calculated]` event.
  """
  @spec diff_calculated(String.t() | atom(), module() | String.t(), map(), non_neg_integer()) ::
          :ok
  def diff_calculated(action, schema, changes, duration_native \\ 0) do
    measurements = %{
      duration: duration_native,
      fields_count: map_size(changes)
    }

    metadata = %{
      action: to_string(action),
      schema: to_string(schema),
      fields: Map.keys(changes)
    }

    :telemetry.execute([:audit_trail_ex, :diff, :calculated], measurements, metadata)
  end
end
