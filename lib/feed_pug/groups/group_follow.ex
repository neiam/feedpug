defmodule FeedPug.Groups.GroupFollow do
  @moduledoc """
  A user following another user's group. The follow implicitly includes all of
  the followed group's descendants (resolved at query time), minus any
  `FeedPug.Groups.FollowExclusion`s.
  """
  use FeedPug.Schema
  import Ecto.Changeset

  schema "group_follows" do
    belongs_to :follower_user, FeedPug.Accounts.User
    belongs_to :group, FeedPug.Groups.Group

    has_many :exclusions, FeedPug.Groups.FollowExclusion

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group_follow, attrs) do
    group_follow
    |> cast(attrs, [:follower_user_id, :group_id])
    |> validate_required([:follower_user_id, :group_id])
    |> unique_constraint([:follower_user_id, :group_id])
    |> foreign_key_constraint(:group_id)
  end
end
