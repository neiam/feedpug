defmodule FeedPug.Timelines.Slice do
  @moduledoc """
  A saved newsfeed filterset: a named combination of selected source keys,
  the unread-only flag, and an optional reaction (saved) filter.
  """
  use FeedPug.Schema
  import Ecto.Changeset

  schema "timeline_slices" do
    field :name, :string
    field :source_keys, {:array, :string}, default: []
    field :unread_only, :boolean, default: false
    field :reaction_emoji, :string
    field :position, :integer, default: 0

    belongs_to :user, FeedPug.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(slice, attrs) do
    slice
    |> cast(attrs, [:name, :source_keys, :unread_only, :reaction_emoji, :position, :user_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :user_id])
    |> validate_length(:name, min: 1, max: 60)
    |> unique_constraint([:user_id, :name])
  end
end
