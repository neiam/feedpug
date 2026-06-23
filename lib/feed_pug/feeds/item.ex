defmodule FeedPug.Feeds.Item do
  @moduledoc """
  A single entry/article within a `FeedPug.Feeds.Feed`, deduped per feed by
  its `guid`.
  """
  use FeedPug.Schema
  import Ecto.Changeset

  schema "items" do
    field :guid, :string
    field :title, :string
    field :url, :string
    field :summary, :string
    field :content, :string
    field :author, :string
    field :published_at, :utc_datetime
    field :revised_at, :utc_datetime
    field :sort_at, :utc_datetime
    field :read, :boolean, virtual: true, default: false
    field :reactions, {:array, :string}, virtual: true, default: []

    belongs_to :feed, FeedPug.Feeds.Feed

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(item, attrs) do
    item
    |> cast(attrs, [:feed_id, :guid, :title, :url, :summary, :content, :author, :published_at])
    |> validate_required([:feed_id, :guid])
    |> unique_constraint([:feed_id, :guid])
  end
end
