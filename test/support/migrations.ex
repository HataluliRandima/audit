defmodule AuditTrailEx.TestMigrations do
  @moduledoc false
  use Ecto.Migration

  def up do
    AuditTrailEx.Migration.up()

    create_if_not_exists table(:users) do
      add :name, :string, null: false
      add :email, :string
      add :role, :string, default: "member"
      add :password_hash, :string
      add :api_token, :string

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists table(:articles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :body, :text
      add :status, :string, default: "draft"
      add :view_count, :integer, default: 0
      add :price, :decimal
      add :published_at, :naive_datetime
      add :tags, {:array, :string}, default: []
      add :meta, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create_if_not_exists table(:project_members, primary_key: false) do
      add :project_id, :integer, primary_key: true
      add :user_id, :integer, primary_key: true
      add :role, :string, default: "developer"

      timestamps(type: :utc_datetime)
    end
  end

  def down do
    drop_if_exists table(:project_members)
    drop_if_exists table(:articles)
    drop_if_exists table(:users)
    AuditTrailEx.Migration.down()
  end
end
