defmodule FeedPug.Feeds.Feed do
  @moduledoc """
  A canonical, globally-shared RSS/Atom feed keyed by URL.

  A feed is fetched once regardless of how many users/groups reference it; the
  membership lives in `FeedPug.Groups.GroupFeed`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(active paused failed archived)

  schema "feeds" do
    field :url, :string
    field :site_url, :string
    field :title, :string
    field :description, :string
    field :etag, :string
    field :last_modified, :string
    field :last_fetched_at, :utc_datetime
    field :next_fetch_at, :utc_datetime
    field :fetch_interval_seconds, :integer, default: 3600
    field :failure_count, :integer, default: 0
    field :status, :string, default: "active"

    has_many :items, FeedPug.Feeds.Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(feed, attrs) do
    feed
    |> cast(attrs, [
      :url,
      :site_url,
      :title,
      :description,
      :etag,
      :last_modified,
      :last_fetched_at,
      :next_fetch_at,
      :fetch_interval_seconds,
      :failure_count,
      :status
    ])
    |> validate_required([:url])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:url)
  end

  def statuses, do: @statuses
end
