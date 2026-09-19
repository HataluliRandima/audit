defmodule AuditTrailEx.SerializerTest do
  use ExUnit.Case, async: true

  alias AuditTrailEx.Serializer
  alias AuditTrailEx.TestSchemas.User

  describe "serialize/1" do
    test "serializes primitives as-is" do
      assert Serializer.serialize("hello") == "hello"
      assert Serializer.serialize(42) == 42
      assert Serializer.serialize(3.14) == 3.14
      assert Serializer.serialize(true) == true
      assert Serializer.serialize(false) == false
      assert Serializer.serialize(nil) == nil
    end

    test "serializes atoms to strings" do
      assert Serializer.serialize(:active) == "active"
      assert Serializer.serialize(:pending_review) == "pending_review"
    end

    test "serializes Decimal to string" do
      assert Serializer.serialize(Decimal.new("123.45")) == "123.45"
      assert Serializer.serialize(Decimal.new(0)) == "0"
    end

    test "serializes Date, Time, DateTime, and NaiveDateTime to ISO 8601 strings" do
      date = ~D[2026-09-19]
      time = ~T[12:30:00]
      ndt = ~N[2026-09-19 12:30:00]
      {:ok, dt, 0} = DateTime.from_iso8601("2026-09-19T12:30:00Z")

      assert Serializer.serialize(date) == "2026-09-19"
      assert Serializer.serialize(time) == "12:30:00"
      assert Serializer.serialize(ndt) == "2026-09-19T12:30:00"
      assert Serializer.serialize(dt) == "2026-09-19T12:30:00Z"
    end

    test "serializes structs and drops __meta__" do
      user = %User{id: 1, name: "Alice", email: "alice@example.com"}
      serialized = Serializer.serialize(user)

      assert is_map(serialized)
      refute Map.has_key?(serialized, "__meta__")
      refute Map.has_key?(serialized, :__meta__)
      assert serialized["name"] == "Alice"
      assert serialized["email"] == "alice@example.com"
      assert serialized["id"] == 1
    end

    test "recursively serializes maps, lists, and tuples" do
      input = %{
        user: %{
          name: "Bob",
          joined: ~D[2026-01-01],
          scores: [Decimal.new("98.5"), Decimal.new("100.0")]
        },
        coordinate: {10, 20}
      }

      assert Serializer.serialize(input) == %{
               "user" => %{
                 "name" => "Bob",
                 "joined" => "2026-01-01",
                 "scores" => ["98.5", "100.0"]
               },
               "coordinate" => [10, 20]
             }
    end
  end
end
