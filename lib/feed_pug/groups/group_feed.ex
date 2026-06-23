defmodule FeedPug.Groups.GroupFeed do
  @moduledoc """
  Membership edge placing a canonical `FeedPug.Feeds.Feed` into a
  `FeedPug.Groups.Group`. Feeds may attach at any node, not just leaves.
  """
  use FeedPug.Schema
  import Ecto.Changeset

  schema "group_feeds" do
    field :custom_title, :string

    belongs_to :group, FeedPug.Groups.Group
    belongs_to :feed, FeedPug.Feeds.Feed

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(group_feed, attrs) do
    group_feed
    |> cast(attrs, [:group_id, :feed_id, :custom_title])
    |> validate_required([:group_id, :feed_id])
    |> unique_constraint([:group_id, :feed_id])
    |> foreign_key_constraint(:feed_id)
    |> foreign_key_constraint(:group_id)
  end
end
