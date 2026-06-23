defmodule FeedPug.Reactions.Reaction do
  @moduledoc "An entry in a user's reaction-emoji palette."
  use FeedPug.Schema
  import Ecto.Changeset

  schema "reactions" do
    field :emoji, :string
    field :label, :string
    field :position, :integer, default: 0

    belongs_to :user, FeedPug.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(reaction, attrs) do
    reaction
    |> cast(attrs, [:emoji, :label, :position, :user_id])
    |> update_change(:emoji, &String.trim/1)
    |> validate_required([:emoji, :user_id])
    |> validate_length(:emoji, max: 16)
    |> unique_constraint([:user_id, :emoji])
  end
end
