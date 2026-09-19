defmodule AuditTrailEx.TestSchemas.User do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name, :string
    field :email, :string
    field :role, :string, default: "member"
    field :password_hash, :string
    field :api_token, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :role, :password_hash, :api_token])
    |> validate_required([:name])
  end

  def __audit_trail_options__ do
    [
      redacted_fields: [:email],
      excluded_fields: [:api_token]
    ]
  end
end

defmodule AuditTrailEx.TestSchemas.Article do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "articles" do
    field :title, :string
    field :body, :string
    field :status, :string, default: "draft"
    field :view_count, :integer, default: 0
    field :price, :decimal
    field :published_at, :naive_datetime
    field :tags, {:array, :string}, default: []
    field :meta, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  def changeset(article, attrs) do
    article
    |> cast(attrs, [:title, :body, :status, :view_count, :price, :published_at, :tags, :meta])
    |> validate_required([:title])
  end
end

defmodule AuditTrailEx.TestSchemas.ProjectMember do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "project_members" do
    field :project_id, :integer, primary_key: true
    field :user_id, :integer, primary_key: true
    field :role, :string, default: "developer"

    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:project_id, :user_id, :role])
    |> validate_required([:project_id, :user_id])
  end
end

defmodule AuditTrailEx.TestSchemas.ActorAdmin do
  @moduledoc false
  defstruct [:id, :username, :department]
end

defimpl AuditTrailEx.Actor, for: AuditTrailEx.TestSchemas.ActorAdmin do
  def identify(%{id: id, department: dept}) do
    {to_string(id), "admin:#{dept}"}
  end
end
