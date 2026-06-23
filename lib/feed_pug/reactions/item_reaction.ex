defmodule FeedPug.Reactions.ItemReaction do
  @moduledoc "A reaction emoji a user has applied to an item."
  use Ecto.Schema
  import Ecto.Changeset

  schema "item_reactions" do
    field :emoji, :string

    belongs_to :user, FeedPug.Accounts.User
    belongs_to :item, FeedPug.Feeds.Item

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(item_reaction, attrs) do
    item_reaction
    |> cast(attrs, [:emoji, :user_id, :item_id])
    |> validate_required([:emoji, :user_id, :item_id])
    |> unique_constraint([:user_id, :item_id, :emoji])
  end
end
