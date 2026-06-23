defmodule FeedPug.Groups.FollowExclusion do
  @moduledoc """
  A subgroup a follower has filtered out of a `FeedPug.Groups.GroupFollow`.
  Excluding a node hides its descendants too.
  """
  use FeedPug.Schema
  import Ecto.Changeset

  schema "follow_exclusions" do
    belongs_to :group_follow, FeedPug.Groups.GroupFollow
    belongs_to :excluded_group, FeedPug.Groups.Group

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(follow_exclusion, attrs) do
    follow_exclusion
    |> cast(attrs, [:group_follow_id, :excluded_group_id])
    |> validate_required([:group_follow_id, :excluded_group_id])
    |> unique_constraint([:group_follow_id, :excluded_group_id])
    |> foreign_key_constraint(:excluded_group_id)
  end
end
