defmodule AuditTrailExTest do
  use ExUnit.Case, async: false

  alias AuditTrailEx.Event
  alias AuditTrailEx.TestRepo, as: Repo
  alias AuditTrailEx.TestSchemas.Article
  alias AuditTrailEx.TestSchemas.ProjectMember
  alias AuditTrailEx.TestSchemas.User
  alias AuditTrailEx.Web
  alias Ecto.Adapters.SQL.Sandbox

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})
    :ok
  end

  describe "insert/3" do
    test "inserts record and creates audit event for integer primary key" do
      params = %{
        name: "Samantha",
        email: "samantha@example.com",
        role: "admin",
        password_hash: "secret_hash",
        api_token: "tok_123"
      }

      changeset = User.changeset(%User{}, params)

      assert {:ok, user} =
               AuditTrailEx.insert(Repo, changeset,
                 actor: %{id: "admin-99", type: "superadmin"},
                 metadata: %{ip: "127.0.0.1", source: "backoffice"}
               )

      assert is_integer(user.id)
      assert user.name == "Samantha"

      [event] = Repo.all(AuditTrailEx.Query.base())
      assert event.action == "insert"
      assert event.schema == "AuditTrailEx.TestSchemas.User"
      assert event.table == "users"
      assert event.record_id == to_string(user.id)
      assert event.actor_id == "admin-99"
      assert event.actor_type == "superadmin"
      assert event.metadata == %{"ip" => "127.0.0.1", "source" => "backoffice"}

      # Name captured
      assert event.changes["name"] == %{"from" => nil, "to" => "Samantha"}
      assert event.changes["role"] == %{"from" => nil, "to" => "admin"}

      # Redacted field
      assert event.changes["email"] == %{"from" => nil, "to" => "[REDACTED]"}

      # Excluded fields (password_hash from global config, api_token from schema config)
      refute Map.has_key?(event.changes, "password_hash")
      refute Map.has_key?(event.changes, "api_token")
    end

    test "inserts record with UUID primary key (Article)" do
      params = %{
        title: "Mastering Elixir",
        body: "A comprehensive guide.",
        price: Decimal.new("49.99"),
        status: "published",
        tags: ["elixir", "ecto"]
      }

      changeset = Article.changeset(%Article{}, params)

      assert {:ok, article, event} =
               AuditTrailEx.insert(Repo, changeset,
                 actor_id: "author-1",
                 actor_type: "author",
                 return_audit: true
               )

      assert is_binary(article.id)
      assert event.record_id == article.id
      assert event.action == "insert"
      assert event.changes["price"] == %{"from" => nil, "to" => "49.99"}
      assert event.changes["tags"] == %{"from" => nil, "to" => ["elixir", "ecto"]}
    end

    test "inserts composite primary key record (ProjectMember)" do
      changeset =
        ProjectMember.changeset(%ProjectMember{}, %{
          project_id: 10,
          user_id: 20,
          role: "maintainer"
        })

      assert {:ok, member, event} =
               AuditTrailEx.insert(Repo, changeset,
                 actor: "system_cron",
                 return_audit: true
               )

      assert member.project_id == 10
      assert member.user_id == 20
      assert event.record_id == "10:20"
      assert event.action == "insert"
      assert event.changes["role"] == %{"from" => nil, "to" => "maintainer"}
    end

    test "returns {:error, changeset} on validation failure without saving audit event" do
      invalid_changeset = User.changeset(%User{}, %{name: nil})

      assert {:error, changeset} = AuditTrailEx.insert(Repo, invalid_changeset)
      refute changeset.valid?
      assert Repo.aggregate(Event, :count) == 0
    end
  end

  describe "update/3" do
    test "records only changed fields and applies redactions" do
      {:ok, user} =
        Repo.insert(%User{
          name: "Original Name",
          email: "orig@example.com",
          role: "member",
          password_hash: "p_hash"
        })

      changeset =
        User.changeset(user, %{
          name: "Updated Name",
          email: "updated@example.com",
          password_hash: "new_hash"
        })

      assert {:ok, updated_user, event} =
               AuditTrailEx.update(Repo, changeset,
                 actor: user,
                 return_audit: true
               )

      assert updated_user.name == "Updated Name"

      # Verify audit event
      assert event.action == "update"
      assert event.record_id == to_string(user.id)
      assert event.actor_id == to_string(user.id)
      assert event.actor_type == "User"

      # Name changed
      assert event.changes["name"] == %{"from" => "Original Name", "to" => "Updated Name"}

      # Email was changed and is redacted
      assert event.changes["email"] == %{"from" => "[REDACTED]", "to" => "[REDACTED]"}

      # Unchanged field 'role' is NOT recorded
      refute Map.has_key?(event.changes, "role")

      # Globally excluded 'password_hash' is NOT recorded
      refute Map.has_key?(event.changes, "password_hash")
    end

    test "returns {:error, changeset} on invalid update" do
      {:ok, user} = Repo.insert(%User{name: "Valid User"})
      changeset = User.changeset(user, %{name: nil})

      assert {:error, cs} = AuditTrailEx.update(Repo, changeset)
      refute cs.valid?
      assert Repo.aggregate(Event, :count) == 0
    end
  end

  describe "delete/3" do
    test "records snapshot of deleted fields" do
      {:ok, user} = Repo.insert(%User{name: "To Delete", email: "del@example.com", role: "admin"})

      assert {:ok, _deleted, event} =
               AuditTrailEx.delete(Repo, user,
                 actor_id: "sec_ops",
                 actor_type: "security",
                 return_audit: true
               )

      assert event.action == "delete"
      assert event.record_id == to_string(user.id)
      assert event.changes["name"] == %{"from" => "To Delete", "to" => nil}
      assert event.changes["role"] == %{"from" => "admin", "to" => nil}
      assert event.changes["email"] == %{"from" => "[REDACTED]", "to" => nil}

      assert Repo.get(User, user.id) == nil
    end
  end

  describe "audit/3 general helper" do
    test "routes changeset with action :insert, :update, :delete" do
      # Insert
      cs_insert = User.changeset(%User{}, %{name: "Audit Dispatcher"})
      assert {:ok, user} = AuditTrailEx.audit(Repo, cs_insert)
      assert user.id != nil

      # Update
      cs_update = User.changeset(user, %{name: "Audit Dispatcher Updated"})
      assert {:ok, updated_user} = AuditTrailEx.audit(Repo, cs_update)
      assert updated_user.name == "Audit Dispatcher Updated"

      # Delete
      assert {:ok, _} = AuditTrailEx.audit(Repo, updated_user, action: :delete)
      assert Repo.get(User, user.id) == nil
    end
  end

  describe "history/4, by_actor/3, by_action/3 query API" do
    test "retrieves and filters audit history" do
      {:ok, user, _} =
        AuditTrailEx.insert(Repo, User.changeset(%User{}, %{name: "History Test"}),
          actor_id: "user-1",
          actor_type: "user",
          return_audit: true
        )

      {:ok, _user2, _} =
        AuditTrailEx.insert(Repo, User.changeset(%User{}, %{name: "User Two"}),
          actor_id: "admin-1",
          actor_type: "admin",
          return_audit: true
        )

      {:ok, _, _} =
        AuditTrailEx.update(Repo, User.changeset(user, %{name: "History Test 2"}),
          actor_id: "admin-1",
          actor_type: "admin",
          return_audit: true
        )

      # history for user
      history = AuditTrailEx.history(Repo, User, user.id)
      assert length(history) == 2
      assert Enum.map(history, & &1.action) == ["update", "insert"]

      # history with action filter
      updates = AuditTrailEx.history(Repo, User, user.id, action: :update)
      assert length(updates) == 1
      assert List.first(updates).action == "update"

      # by_actor
      admin_events = AuditTrailEx.by_actor(Repo, "admin-1")
      assert length(admin_events) == 2

      admin_events_scoped = AuditTrailEx.by_actor(Repo, "admin-1", actor_type: "admin")
      assert length(admin_events_scoped) == 2

      # by_action
      inserts = AuditTrailEx.by_action(Repo, :insert)
      assert length(inserts) == 2
    end
  end

  describe "describe/1 and describe_text/1" do
    test "formats human readable changes" do
      event = %Event{
        action: "update",
        schema: "AuditTrailEx.TestSchemas.User",
        record_id: "1",
        changes: %{
          "name" => %{"from" => "Alice", "to" => "Alicia"}
        }
      }

      descriptions = AuditTrailEx.describe(event)
      assert length(descriptions) == 1
      [desc] = descriptions
      assert desc.field == "name"
      assert desc.kind == :changed
      assert desc.summary =~ "Name changed from \"Alice\" to \"Alicia\""

      text = AuditTrailEx.describe_text(event)
      assert text =~ "Update AuditTrailEx.TestSchemas.User [1]"
      assert text =~ "Name changed"
    end
  end

  describe "Web.extract_metadata/1" do
    test "extracts metadata from map or conn" do
      raw_meta = %{request_id: "req-123", ip: "192.168.1.1"}
      extracted = Web.extract_metadata(raw_meta)
      assert extracted == %{"request_id" => "req-123", "ip" => "192.168.1.1"}
    end
  end
end
