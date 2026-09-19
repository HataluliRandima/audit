defmodule AuditTrailEx.FormatterTest do
  use ExUnit.Case, async: true

  alias AuditTrailEx.ChangeDescription
  alias AuditTrailEx.Event
  alias AuditTrailEx.Formatter

  describe "describe/1" do
    test "formats changed, added, and removed fields" do
      changes = %{
        "name" => %{"from" => "Bob", "to" => "Bobby"},
        "bio" => %{"from" => nil, "to" => "Software Engineer"},
        "legacy_token" => %{"from" => "abc-123", "to" => nil}
      }

      descriptions = Formatter.describe(changes)
      assert length(descriptions) == 3

      by_field = Map.new(descriptions, fn d -> {d.field, d} end)

      assert %ChangeDescription{kind: :changed, from: "Bob", to: "Bobby"} = by_field["name"]
      assert by_field["name"].summary =~ "Name changed from \"Bob\" to \"Bobby\""

      assert %ChangeDescription{kind: :added, from: nil, to: "Software Engineer"} =
               by_field["bio"]

      assert by_field["bio"].summary =~ "Bio set to \"Software Engineer\""

      assert %ChangeDescription{kind: :removed, from: "abc-123", to: nil} =
               by_field["legacy_token"]

      assert by_field["legacy_token"].summary =~ "Legacy token removed"
    end

    test "works with Event struct" do
      event = %Event{
        action: "update",
        schema: "User",
        record_id: "1",
        changes: %{"role" => %{from: "member", to: "admin"}}
      }

      [desc] = Formatter.describe(event)
      assert desc.field == "role"
      assert desc.kind == :changed
      assert desc.from == "member"
      assert desc.to == "admin"
    end
  end

  describe "to_text/1" do
    test "renders formatted text representation" do
      event = %Event{
        action: "update",
        schema: "MyApp.Accounts.User",
        record_id: "42",
        changes: %{
          "email" => %{from: "old@example.com", to: "new@example.com"}
        }
      }

      text = Formatter.to_text(event)
      assert text =~ "Update MyApp.Accounts.User [42]"
      assert text =~ "Email changed"
      assert text =~ "From: \"old@example.com\""
      assert text =~ "To:   \"new@example.com\""
    end
  end
end
