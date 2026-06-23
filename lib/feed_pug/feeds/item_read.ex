defmodule FeedPug.Feeds.ItemRead do
  @moduledoc """
  Per-user read marker for an item. The presence of a row means the user has
  read that item.
  """
  use FeedPug.Schema

  schema "item_reads" do
    belongs_to :user, FeedPug.Accounts.User
    belongs_to :item, FeedPug.Feeds.Item

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
