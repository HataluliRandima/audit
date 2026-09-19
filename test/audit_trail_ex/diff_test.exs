defmodule AuditTrailEx.DiffTest do
  use ExUnit.Case, async: true

  alias AuditTrailEx.Diff
  alias AuditTrailEx.TestSchemas.Article
  alias AuditTrailEx.TestSchemas.User

  describe "calculate(:insert, ...)" do
    test "captures inserted attributes with from: nil" do
      changeset =
        User.changeset(%User{}, %{name: "John", email: "john@example.com", role: "admin"})

      diff = Diff.calculate(:insert, changeset)

      assert diff["name"] == %{"from" => nil, "to" => "John"}
      assert diff["role"] == %{"from" => nil, "to" => "admin"}
      # email is redacted in User schema
      assert diff["email"] == %{"from" => nil, "to" => "[REDACTED]"}
      refute Map.has_key?(diff, "id")
    end

    test "works with raw structs" do
      article = %Article{
        title: "Hello World",
        status: "published",
        price: Decimal.new("19.99"),
        tags: ["elixir", "audit"]
      }

      diff = Diff.calculate(:insert, article)

      assert diff["title"] == %{"from" => nil, "to" => "Hello World"}
      assert diff["status"] == %{"from" => nil, "to" => "published"}
      assert diff["price"] == %{"from" => nil, "to" => "19.99"}
      assert diff["tags"] == %{"from" => nil, "to" => ["elixir", "audit"]}
    end
  end

  describe "calculate(:update, ...)" do
    test "only captures fields that actually changed" do
      user = %User{id: 1, name: "John", email: "john@example.com", role: "member"}
      changeset = User.changeset(user, %{name: "Johnny"})

      diff = Diff.calculate(:update, changeset)

      assert Map.keys(diff) == ["name"]
      assert diff["name"] == %{"from" => "John", "to" => "Johnny"}
    end

    test "does not record fields where new value equals old value" do
      user = %User{id: 1, name: "John", email: "john@example.com"}
      changeset = Ecto.Changeset.change(user, %{name: "John"})

      diff = Diff.calculate(:update, changeset)

      assert diff == %{}
    end

    test "redacts modified sensitive fields" do
      user = %User{id: 1, name: "John", email: "old@example.com"}
      changeset = User.changeset(user, %{email: "new@example.com"})

      diff = Diff.calculate(:update, changeset)

      assert diff["email"] == %{"from" => "[REDACTED]", "to" => "[REDACTED]"}
    end

    test "completely excludes globally excluded fields" do
      user = %User{id: 1, name: "John", password_hash: "hash1"}
      changeset = User.changeset(user, %{password_hash: "hash2", name: "Jonathan"})

      diff = Diff.calculate(:update, changeset)

      refute Map.has_key?(diff, "password_hash")
      assert diff["name"] == %{"from" => "John", "to" => "Jonathan"}
    end

    test "handles complex types (Decimal, NaiveDateTime, lists, maps)" do
      article = %Article{
        id: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
        title: "Initial",
        price: Decimal.new("10.00"),
        tags: ["news"],
        meta: %{"reviewed" => false}
      }

      changeset =
        Article.changeset(article, %{
          title: "Updated",
          price: Decimal.new("15.50"),
          tags: ["news", "featured"],
          meta: %{"reviewed" => true}
        })

      diff = Diff.calculate(:update, changeset)

      assert diff["title"] == %{"from" => "Initial", "to" => "Updated"}
      assert diff["price"] == %{"from" => "10.00", "to" => "15.50"}
      assert diff["tags"] == %{"from" => ["news"], "to" => ["news", "featured"]}

      assert diff["meta"] == %{
               "from" => %{"reviewed" => false},
               "to" => %{"reviewed" => true}
             }
    end
  end

  describe "calculate(:delete, ...)" do
    test "captures previous record state with to: nil" do
      user = %User{id: 5, name: "Deleted User", email: "del@example.com", role: "member"}
      diff = Diff.calculate(:delete, user)

      assert diff["name"] == %{"from" => "Deleted User", "to" => nil}
      assert diff["role"] == %{"from" => "member", "to" => nil}
      assert diff["email"] == %{"from" => "[REDACTED]", "to" => nil}
      refute Map.has_key?(diff, "__meta__")
    end
  end
end
