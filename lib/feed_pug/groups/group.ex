defmodule FeedPug.Groups.Group do
  @moduledoc """
  A user-owned, arbitrary-depth group of feeds.

  Hierarchy is stored as both an adjacency list (`parent_id`, authoritative) and
  a dot-separated materialized `path` of slugs (e.g. `"blogs.tech.erlang"`) used
  for cheap descendant queries. `path`/`slug` are maintained exclusively by
  `FeedPug.Groups` — never set them directly from callers.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "groups" do
    field :name, :string
    field :slug, :string
    field :path, :string
    field :is_default, :boolean, default: false

    belongs_to :user, FeedPug.Accounts.User
    belongs_to :parent, FeedPug.Groups.Group

    has_many :children, FeedPug.Groups.Group, foreign_key: :parent_id
    has_many :group_feeds, FeedPug.Groups.GroupFeed

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for user-supplied attributes (just the display name). Slug, path,
  parent and ownership are assigned by the context, not cast from user input.
  """
  def changeset(group, attrs) do
    group
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 100)
  end

  @doc false
  def placement_changeset(group, attrs) do
    group
    |> cast(attrs, [:name, :slug, :path, :parent_id, :user_id, :is_default])
    |> validate_required([:name, :slug, :path, :user_id])
    |> unique_constraint([:user_id, :path], name: :groups_user_id_path_index)
    |> unique_constraint([:user_id, :name],
      name: :groups_root_name_index,
      message: "already exists"
    )
    |> unique_constraint([:user_id, :parent_id, :name],
      name: :groups_child_name_index,
      message: "already exists"
    )
  end
end
