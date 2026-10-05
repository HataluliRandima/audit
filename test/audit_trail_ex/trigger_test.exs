defmodule AuditTrailEx.TriggerTest do
  use ExUnit.Case, async: false

  import Ecto.Query

  alias AuditTrailEx.Event
  alias AuditTrailEx.Multi, as: AuditMulti
  alias AuditTrailEx.TestRepo, as: Repo
  alias AuditTrailEx.TestSchemas.Note
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    on_exit(fn -> Application.delete_env(:audit_trail_ex, :trigger_capture) end)
    :ok
  end

  defp note_events,
    do: Repo.all(from e in Event, where: e.table == "notes", order_by: e.inserted_at)

  describe "changes made outside AuditTrailEx" do
    test "Repo.insert is recorded with excluded, redacted and renamed columns" do
      note = Repo.insert!(%Note{title: "Hello", access_token: "tok", pin: "1234", rating: 5})

      assert [event] = note_events()
      assert event.action == "insert"
      assert event.schema == "AuditTrailEx.TestSchemas.Note"
      assert event.record_id == to_string(note.id)
      assert event.actor_id == nil
      assert event.actor_type == "system"
      assert event.metadata == %{}

      assert event.changes["title"] == %{"from" => nil, "to" => "Hello"}
      assert event.changes["pin"] == %{"from" => nil, "to" => "[REDACTED]"}
      assert event.changes["score"] == %{"from" => nil, "to" => 5}
      refute Map.has_key?(event.changes, "access_token")
      refute Map.has_key?(event.changes, "body")
    end

    test "Repo.update_all records only changed columns for each row" do
      a = Repo.insert!(%Note{title: "A", body: "same"})
      b = Repo.insert!(%Note{title: "B", body: "same"})

      Repo.update_all(Note, set: [title: "Z", body: "same"])

      updates = Enum.filter(note_events(), &(&1.action == "update"))
      assert Enum.map(updates, & &1.record_id) |> Enum.sort() == Enum.sort(["#{a.id}", "#{b.id}"])

      for event <- updates do
        assert Map.keys(event.changes) == ["title"]
        assert event.changes["title"]["to"] == "Z"
      end
    end

    test "updates that change nothing are not recorded" do
      Repo.insert!(%Note{title: "A"})
      Repo.update_all(Note, set: [title: "A"])

      assert Enum.map(note_events(), & &1.action) == ["insert"]
    end

    test "Repo.delete records the previous values" do
      note = Repo.insert!(%Note{title: "Bye", pin: "1"})
      Repo.delete!(note)

      assert [_, event] = note_events()
      assert event.action == "delete"
      assert event.changes["title"] == %{"from" => "Bye", "to" => nil}
      assert event.changes["pin"] == %{"from" => "[REDACTED]", "to" => nil}
    end

    test "events are found by AuditTrailEx.history/4" do
      note = Repo.insert!(%Note{title: "A"})
      assert [%Event{action: "insert"}] = AuditTrailEx.history(Repo, Note, note.id)
    end

    test "rolled back changes leave no events" do
      Repo.transaction(fn ->
        Repo.insert!(%Note{title: "A"})
        Repo.rollback(:abort)
      end)

      assert note_events() == []
    end
  end

  describe "with_context/3" do
    test "records the actor and metadata" do
      assert {:ok, %Note{}} =
               AuditTrailEx.with_context(
                 Repo,
                 [actor: %{id: 42, type: "admin"}, metadata: %{reason: "import"}],
                 fn -> Repo.insert!(%Note{title: "A"}) end
               )

      assert [event] = note_events()
      assert event.actor_id == "42"
      assert event.actor_type == "admin"
      assert event.metadata == %{"reason" => "import"}
    end

    test "put_context/2 raises outside a transaction" do
      assert_raise ArgumentError, ~r/inside a transaction/, fn ->
        AuditTrailEx.put_context(Repo, actor: "x")
      end
    end
  end

  describe "trigger_capture config" do
    test "without it, writes through AuditTrailEx are recorded twice" do
      {:ok, _} = AuditTrailEx.insert(Repo, %Note{title: "A"}, actor: "me")

      assert [%{actor_id: _}, %{actor_id: _}] = note_events()
    end

    test "with it, writes through AuditTrailEx are recorded once" do
      Application.put_env(:audit_trail_ex, :trigger_capture, true)

      {:ok, note} = AuditTrailEx.insert(Repo, %Note{title: "A"}, actor: "me")

      {:ok, note} =
        AuditTrailEx.update(Repo, Ecto.Changeset.change(note, title: "B"), actor: "me")

      {:ok, _} = AuditTrailEx.delete(Repo, note, actor: "me")

      events = note_events()
      assert Enum.map(events, & &1.action) == ["insert", "update", "delete"]
      assert Enum.all?(events, &(&1.actor_id == "me"))
    end

    test "with it, other statements in the same transaction are still recorded" do
      Application.put_env(:audit_trail_ex, :trigger_capture, true)

      {:ok, _} =
        Ecto.Multi.new()
        |> AuditMulti.insert(:note, %Note{title: "A"}, actor: "me")
        |> Ecto.Multi.update_all(:bulk, Note, set: [title: "B"])
        |> Repo.transaction()

      assert %{"insert" => insert, "update" => update} = Map.new(note_events(), &{&1.action, &1})
      assert insert.actor_id == "me"
      assert update.actor_type == "system"
    end
  end
end
