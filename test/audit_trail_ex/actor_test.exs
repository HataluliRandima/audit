defmodule AuditTrailEx.ActorTest do
  use ExUnit.Case, async: true

  alias AuditTrailEx.Actor
  alias AuditTrailEx.ActorHelper
  alias AuditTrailEx.TestSchemas.ActorAdmin
  alias AuditTrailEx.TestSchemas.User

  describe "Actor.identify/1 protocol" do
    test "identifies nil as system actor" do
      assert Actor.identify(nil) == {nil, "system"}
    end

    test "identifies standard Ecto struct" do
      user = %User{id: 123, name: "Alice"}
      assert Actor.identify(user) == {"123", "User"}
    end

    test "identifies map with id and type" do
      actor = %{id: "bot-99", type: "bot"}
      assert Actor.identify(actor) == {"bot-99", "bot"}
    end

    test "identifies map with string keys" do
      actor = %{"id" => "srv-1", "type" => "service_account"}
      assert Actor.identify(actor) == {"srv-1", "service_account"}
    end

    test "defaults actor_type to 'user' for maps without type" do
      assert Actor.identify(%{id: 42}) == {"42", "user"}
    end

    test "identifies strings and integers" do
      assert Actor.identify("worker_job") == {"worker_job", "actor"}
      assert Actor.identify(999) == {"999", "actor"}
    end

    test "supports custom protocol implementations" do
      admin = %ActorAdmin{id: 7, username: "admin_bob", department: "security"}
      assert Actor.identify(admin) == {"7", "admin:security"}
    end
  end

  describe "ActorHelper.resolve/1" do
    test "resolves from keyword options" do
      user = %User{id: 1, name: "Alice"}
      assert ActorHelper.resolve(actor: user) == {"1", "User"}
    end

    test "allows explicit actor_id and actor_type overrides" do
      user = %User{id: 1, name: "Alice"}

      assert ActorHelper.resolve(actor: user, actor_type: "SuperAdmin") ==
               {"1", "SuperAdmin"}

      assert ActorHelper.resolve(actor_id: "override_id", actor_type: "override_type") ==
               {"override_id", "override_type"}
    end
  end
end
