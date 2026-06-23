defmodule FeedPug.Timelines do
  @moduledoc """
  The Timelines context: a user's saved newsfeed slices (named filtersets).
  All operations are scoped through `%FeedPug.Accounts.Scope{}`.
  """
  import Ecto.Query, warn: false

  alias FeedPug.Repo
  alias FeedPug.Accounts.Scope
  alias FeedPug.Timelines.Slice

  def list_slices(%Scope{user: user}) do
    from(s in Slice, where: s.user_id == ^user.id, order_by: [asc: s.position, asc: s.id])
    |> Repo.all()
  end

  def get_slice!(%Scope{user: user}, id), do: Repo.get_by!(Slice, id: id, user_id: user.id)

  @doc """
  Saves a slice from a filterset. `attrs` keys: `name`, `source_keys` (list),
  `unread_only` (bool), `reaction_emoji` (string or nil).
  """
  def create_slice(%Scope{user: user}, attrs) do
    next_position =
      from(s in Slice, where: s.user_id == ^user.id, select: coalesce(max(s.position), -1) + 1)
      |> Repo.one()

    %Slice{}
    |> Slice.changeset(
      attrs
      |> normalize_keys()
      |> Map.merge(%{"user_id" => user.id, "position" => next_position})
    )
    |> Repo.insert()
  end

  def delete_slice(%Scope{user: user}, id) do
    case Repo.get_by(Slice, id: id, user_id: user.id) do
      nil -> {:error, :not_found}
      slice -> Repo.delete(slice)
    end
  end

  # Accept string- or atom-keyed attrs.
  defp normalize_keys(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end
end
