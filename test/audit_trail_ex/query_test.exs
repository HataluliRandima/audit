defmodule AuditTrailEx.QueryTest do
  use ExUnit.Case, async: true

  alias AuditTrailEx.Event
  alias AuditTrailEx.Query, as: AuditQuery
  alias AuditTrailEx.TestSchemas.User

  describe "query building" do
    test "base/1 orders by inserted_at desc" do
      query = AuditQuery.base()
      assert inspect(query) =~ "order_by: [desc: e0.inserted_at]"
    end

    test "for_record/3 filters by schema and string record_id" do
      query = AuditQuery.for_record(Event, User, 42)
      assert inspect(query) =~ "e0.schema == ^"
      assert inspect(query) =~ "e0.record_id == ^\"42\""
    end

    test "by_actor/3 filters by actor_id and optional actor_type" do
      query1 = AuditQuery.by_actor(Event, "actor-123")
      assert inspect(query1) =~ "e0.actor_id == ^\"actor-123\""

      query2 = AuditQuery.by_actor(Event, "actor-123", "admin")
      assert inspect(query2) =~ "e0.actor_id == ^\"actor-123\""
      assert inspect(query2) =~ "e0.actor_type == ^\"admin\""
    end

    test "by_action/2 filters by action" do
      query = AuditQuery.by_action(Event, :update)
      assert inspect(query) =~ "e0.action == ^\"update\""
    end

    test "in_date_range/3, since/2, until/2" do
      t1 = ~U[2026-01-01 00:00:00Z]
      t2 = ~U[2026-01-31 23:59:59Z]

      range_query = AuditQuery.in_date_range(Event, t1, t2)
      assert inspect(range_query) =~ "e0.inserted_at >= ^~U[2026-01-01 00:00:00Z]"
      assert inspect(range_query) =~ "e0.inserted_at <= ^~U[2026-01-31 23:59:59Z]"

      since_query = AuditQuery.since(Event, t1)
      assert inspect(since_query) =~ "e0.inserted_at >= ^~U[2026-01-01 00:00:00Z]"

      until_query = AuditQuery.until(Event, t2)
      assert inspect(until_query) =~ "e0.inserted_at <= ^~U[2026-01-31 23:59:59Z]"
    end

    test "filter/2 applies multiple filters composably" do
      query =
        AuditQuery.base()
        |> AuditQuery.filter(
          schema: User,
          record_id: 10,
          actor_id: "admin-1",
          action: :insert,
          limit: 25
        )

      inspect_str = inspect(query)
      assert inspect_str =~ "e0.record_id == ^\"10\""
      assert inspect_str =~ "e0.actor_id == ^\"admin-1\""
      assert inspect_str =~ "e0.action == ^\"insert\""
      assert inspect_str =~ "limit: ^25"
    end
  end
end
