defmodule AuditTrailEx.MultiTest do
  use ExUnit.Case, async: false

  alias AuditTrailEx.Event
  alias AuditTrailEx.Multi, as: AuditMulti
  alias AuditTrailEx.TestRepo, as: Repo
  alias AuditTrailEx.TestSchemas.User
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  describe "Multi.insert/4" do
    test "atomically commits record and audit log in one transaction" do
      changeset = User.changeset(%User{}, %{name: "Alice", email: "alice@example.com"})

      multi =
        Ecto.Multi.new()
        |> AuditMulti.insert(:new_user, changeset,
          actor: %{id: "admin-1", type: "admin"},
          metadata: %{source: "api"}
        )

      assert {:ok, %{new_user: user, new_user_audit: audit}} = Repo.transaction(multi)

      assert user.id != nil
      assert user.name == "Alice"

      assert audit.action == "insert"
      assert audit.schema == "AuditTrailEx.TestSchemas.User"
      assert audit.table == "users"
      assert audit.record_id == to_string(user.id)
      assert audit.actor_id == "admin-1"
      assert audit.actor_type == "admin"
      assert audit.metadata == %{"source" => "api"}
      assert audit.changes["name"] == %{"from" => nil, "to" => "Alice"}
      # email is redacted per schema
      assert audit.changes["email"] == %{"from" => nil, "to" => "[REDACTED]"}
    end

    test "rolls back everything if an operation fails" do
      invalid_changeset = User.changeset(%User{}, %{name: nil})

      multi =
        Ecto.Multi.new()
        |> AuditMulti.insert(:failed_user, invalid_changeset)

      assert {:error, :failed_user, changeset, _steps} = Repo.transaction(multi)
      refute changeset.valid?

      # Verify no audit event was created
      assert Repo.aggregate(Event, :count) == 0
      assert Repo.aggregate(User, :count) == 0
    end
  end

  describe "Multi.update/4" do
    test "atomically updates and records audit diff" do
      {:ok, user} = Repo.insert(%User{name: "Bob", email: "bob@example.com", role: "member"})
      changeset = User.changeset(user, %{name: "Robert", role: "admin"})

      multi =
        Ecto.Multi.new()
        |> AuditMulti.update(:updated_user, changeset, actor: user)

      assert {:ok, %{updated_user: updated_user, updated_user_audit: audit}} =
               Repo.transaction(multi)

      assert updated_user.name == "Robert"
      assert updated_user.role == "admin"

      assert audit.action == "update"
      assert audit.record_id == to_string(user.id)
      assert audit.changes["name"] == %{"from" => "Bob", "to" => "Robert"}
      assert audit.changes["role"] == %{"from" => "member", "to" => "admin"}
      refute Map.has_key?(audit.changes, "email")
    end

    test "respects ignore_empty: true" do
      {:ok, user} = Repo.insert(%User{name: "Charlie"})
      changeset = Ecto.Changeset.change(user, %{name: "Charlie"})

      multi =
        Ecto.Multi.new()
        |> AuditMulti.update(:charlie, changeset, ignore_empty: true)

      assert {:ok, %{charlie: _, charlie_audit: nil}} = Repo.transaction(multi)
      assert Repo.aggregate(Event, :count) == 0
    end
  end

  describe "Multi.delete/4" do
    test "atomically deletes record and records audit log" do
      {:ok, user} = Repo.insert(%User{name: "Dave", role: "member"})

      multi =
        Ecto.Multi.new()
        |> AuditMulti.delete(:deleted_user, user, actor_id: "sys", actor_type: "cron")

      assert {:ok, %{deleted_user: _, deleted_user_audit: audit}} = Repo.transaction(multi)

      assert audit.action == "delete"
      assert audit.record_id == to_string(user.id)
      assert audit.changes["name"] == %{"from" => "Dave", "to" => nil}
      assert audit.changes["role"] == %{"from" => "member", "to" => nil}

      assert Repo.get(User, user.id) == nil
    end
  end
end
