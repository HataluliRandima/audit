# AuditTrailEx End-to-End Demo
#
# To execute this script, run:
#   mix run examples/demo.exs

defmodule AuditTrailEx.Demo do
  @moduledoc false

  alias AuditTrailEx.TestMigrations
  alias AuditTrailEx.TestRepo, as: Repo
  alias AuditTrailEx.TestSchemas.User
  alias Ecto.Adapters.Postgres
  alias Ecto.Migrator

  def run do
    IO.puts("""
    =======================================================
                      AuditTrailEx Demo
    =======================================================
    """)

    # 1. Start Repo and ensure database & migrations are ready
    {:ok, _} = Repo.start_link()
    _ = Postgres.storage_up(Repo.config())
    Migrator.up(Repo, 1, TestMigrations, log: false)

    # Clean previous demo runs
    Repo.delete_all(AuditTrailEx.Event)
    Repo.delete_all(User)

    # 2. Insert record
    IO.puts("[1] Inserting a new User record with AuditTrailEx...")

    {:ok, user, insert_event} =
      AuditTrailEx.insert(
        Repo,
        User.changeset(%User{}, %{
          name: "Ada Lovelace",
          email: "ada@example.com",
          role: "analyst",
          password_hash: "secret_argon2_hash",
          api_token: "tok_secret_999"
        }),
        actor: %{id: "admin-1", type: "superadmin"},
        metadata: %{"client_ip" => "192.168.1.1", "source" => "web_admin"},
        return_audit: true
      )

    IO.puts("    ✓ User created: #{user.name} (ID: #{user.id})")
    IO.puts("    ✓ Audit event action: #{insert_event.action}")
    IO.puts("    ✓ Actor: #{insert_event.actor_id} (#{insert_event.actor_type})")

    IO.puts(
      "    ✓ Password hash was excluded: #{not Map.has_key?(insert_event.changes, "password_hash")}"
    )

    IO.puts(
      "    ✓ API token was excluded: #{not Map.has_key?(insert_event.changes, "api_token")}"
    )

    IO.puts("    ✓ Email was redacted: #{insert_event.changes["email"]["to"] == "[REDACTED]"}\n")

    # 3. Update record
    IO.puts("[2] Updating the User record...")

    {:ok, updated_user, update_event} =
      AuditTrailEx.update(
        Repo,
        User.changeset(user, %{name: "Ada King", role: "lead_architect"}),
        actor: user,
        metadata: %{"reason" => "Title promotion & marriage name change"},
        return_audit: true
      )

    IO.puts("    ✓ User updated: #{updated_user.name} (#{updated_user.role})")
    IO.puts("    ✓ Field-level changes recorded:")

    for desc <- AuditTrailEx.describe(update_event) do
      IO.puts("      - #{desc.summary}")
    end

    IO.puts("\n[3] Formatted Plain Text representation:")
    IO.puts("-------------------------------------------------------")
    IO.puts(AuditTrailEx.describe_text(update_event))
    IO.puts("-------------------------------------------------------\n")

    # 4. Atomic transactions with Ecto.Multi
    IO.puts("[4] Executing atomic transaction with Ecto.Multi...")

    multi =
      Ecto.Multi.new()
      |> AuditTrailEx.Multi.update(
        :promote,
        User.changeset(updated_user, %{role: "fellow"}),
        actor_id: "governance_board",
        actor_type: "system"
      )

    {:ok, %{promote: promoted_user, promote_audit: multi_audit}} =
      Repo.transaction(multi)

    IO.puts("    ✓ User atomically promoted to: #{promoted_user.role}")
    IO.puts("    ✓ Audit event atomically committed: #{multi_audit.id}\n")

    # 5. Query Audit History
    IO.puts("[5] Querying Audit History for User #{user.id}...")

    history = AuditTrailEx.history(Repo, User, user.id)
    IO.puts("    ✓ Found #{length(history)} audit events in history:")

    for event <- history do
      IO.puts(
        "      * [#{event.inserted_at}] #{String.upcase(event.action)} by #{event.actor_type}:#{event.actor_id || "none"}"
      )
    end

    IO.puts("""

    =======================================================
                 Demo Completed Successfully!
    =======================================================
    """)
  end
end

AuditTrailEx.Demo.run()
