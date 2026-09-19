defmodule AuditTrailEx.FilterTest do
  use ExUnit.Case, async: true

  alias AuditTrailEx.Filter
  alias AuditTrailEx.TestSchemas.User

  describe "filter_changes/3" do
    test "excludes fields configured globally" do
      # :password and :password_hash are in config/config.exs
      changes = %{
        "name" => %{from: "Alice", to: "Bob"},
        "password" => %{from: nil, to: "secret123"},
        "password_hash" => %{from: "old_hash", to: "new_hash"}
      }

      filtered = Filter.filter_changes(changes, nil)

      assert Map.keys(filtered) == ["name"]
      assert filtered["name"] == %{from: "Alice", to: "Bob"}
    end

    test "respects schema-level excluded and redacted fields" do
      # User defines excluded: [:api_token], redacted: [:email]
      changes = %{
        "name" => %{from: "Alice", to: "Bob"},
        "email" => %{from: "old@example.com", to: "new@example.com"},
        "api_token" => %{from: "old_tok", to: "new_tok"}
      }

      filtered = Filter.filter_changes(changes, User)

      refute Map.has_key?(filtered, "api_token")
      assert filtered["name"] == %{from: "Alice", to: "Bob"}
      assert filtered["email"] == %{from: "[REDACTED]", to: "[REDACTED]"}
    end

    test "respects per-call options" do
      changes = %{
        "name" => %{from: "Alice", to: "Bob"},
        "role" => %{from: "member", to: "admin"},
        "notes" => %{from: "private", to: "confidential"}
      }

      filtered =
        Filter.filter_changes(changes, nil,
          excluded_fields: [:notes],
          redacted_fields: [:role],
          redaction_text: "[HIDDEN]"
        )

      refute Map.has_key?(filtered, "notes")
      assert filtered["name"] == %{from: "Alice", to: "Bob"}
      assert filtered["role"] == %{from: "[HIDDEN]", to: "[HIDDEN]"}
    end

    test "preserves nil in redacted values" do
      changes = %{
        "email" => %{from: nil, to: "first@example.com"}
      }

      filtered = Filter.filter_changes(changes, nil, redacted_fields: [:email])

      assert filtered["email"] == %{from: nil, to: "[REDACTED]"}
    end
  end

  describe "excluded?/3 and redacted?/3" do
    test "checks field membership across scopes" do
      assert Filter.excluded?(:password, nil)
      assert Filter.excluded?(:api_token, User)
      refute Filter.excluded?(:email, User)

      assert Filter.redacted?(:email, User)
      refute Filter.redacted?(:name, User)
    end
  end
end
