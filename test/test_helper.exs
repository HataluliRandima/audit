ExUnit.start()

alias AuditTrailEx.Event
alias AuditTrailEx.TestMigrations
alias AuditTrailEx.TestRepo
alias AuditTrailEx.TestSchemas.Article
alias AuditTrailEx.TestSchemas.Note
alias AuditTrailEx.TestSchemas.ProjectMember
alias AuditTrailEx.TestSchemas.User
alias AuditTrailEx.TestTriggerMigrations
alias Ecto.Adapters.Postgres
alias Ecto.Adapters.SQL.Sandbox
alias Ecto.Migrator

{:ok, _} = TestRepo.start_link()
_ = Postgres.storage_up(TestRepo.config())

# Run migrations for tests
Migrator.up(TestRepo, 1, TestMigrations, log: false)
Migrator.up(TestRepo, 2, TestTriggerMigrations, log: false)

# Ensure clean slate for test database
TestRepo.delete_all(Note)
TestRepo.delete_all(Event)
TestRepo.delete_all(ProjectMember)
TestRepo.delete_all(Article)
TestRepo.delete_all(User)

Sandbox.mode(TestRepo, :manual)
