defmodule FeedPug.Reactions do
  @moduledoc """
  The Reactions context: a per-user palette of reaction emojis, and the
  application of those emojis to items ("saving"/tagging). All operations are
  scoped through `%FeedPug.Accounts.Scope{}`.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias FeedPug.Repo
  alias FeedPug.Accounts.Scope
  alias FeedPug.Feeds.{Item, ItemRead}
  alias FeedPug.Reactions.{Reaction, ItemReaction}

  # Seeded for every new user; they can add/remove their own afterwards.
  @defaults [
    %{emoji: "⭐", label: "star"},
    %{emoji: "❤️", label: "heart"},
    %{emoji: "❗", label: "exclamation"}
  ]

  def default_reactions, do: @defaults

  ## Palette --------------------------------------------------------------------

  def list_reactions(%Scope{user: user}) do
    from(r in Reaction, where: r.user_id == ^user.id, order_by: [asc: r.position, asc: r.id])
    |> Repo.all()
  end

  def add_reaction(%Scope{user: user}, emoji, label \\ nil) do
    next_position =
      from(r in Reaction, where: r.user_id == ^user.id, select: coalesce(max(r.position), -1) + 1)
      |> Repo.one()

    %Reaction{}
    |> Reaction.changeset(%{
      emoji: emoji,
      label: label,
      position: next_position,
      user_id: user.id
    })
    |> Repo.insert()
  end

  def delete_reaction(%Scope{user: user}, reaction_id) do
    case Repo.get_by(Reaction, id: reaction_id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      %Reaction{} = reaction ->
        # Also drop the user's applications of that emoji.
        from(ir in ItemReaction, where: ir.user_id == ^user.id and ir.emoji == ^reaction.emoji)
        |> Repo.delete_all()

        Repo.delete(reaction)
    end
  end

  @doc """
  Seeds the default palette only when the user has *no* reactions at all
  (backfills users who predate the feature or whose seeding failed). A user who
  has any reactions — including ones they curated by removing a default — is left
  untouched. Idempotent. Returns the palette.
  """
  def ensure_default_reactions(%Scope{user: user} = scope) do
    unless Repo.exists?(from(r in Reaction, where: r.user_id == ^user.id)) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      rows =
        @defaults
        |> Enum.with_index()
        |> Enum.map(fn {attrs, position} ->
          %{
            user_id: user.id,
            emoji: attrs.emoji,
            label: attrs.label,
            position: position,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(Reaction, rows, on_conflict: :nothing, conflict_target: [:user_id, :emoji])
    end

    list_reactions(scope)
  end

  @doc "Seeds the default palette inside the registration transaction."
  def seed_default_reactions_multi(multi) do
    @defaults
    |> Enum.with_index()
    |> Enum.reduce(multi, fn {attrs, position}, multi ->
      Multi.insert(multi, {:reaction, attrs.emoji}, fn %{user: user} ->
        Reaction.changeset(%Reaction{}, Map.merge(attrs, %{position: position, user_id: user.id}))
      end)
    end)
  end

  ## Applying reactions to items ------------------------------------------------

  @doc "Toggles an emoji reaction on an item for the user. Returns `:on` or `:off`."
  def toggle_item_reaction(%Scope{user: user}, item_id, emoji) do
    case Repo.get_by(ItemReaction, user_id: user.id, item_id: item_id, emoji: emoji) do
      nil ->
        %ItemReaction{}
        |> ItemReaction.changeset(%{user_id: user.id, item_id: item_id, emoji: emoji})
        |> Repo.insert()

        :on

      %ItemReaction{} = existing ->
        Repo.delete(existing)
        :off
    end
  end

  @doc "Map of `item_id => [emoji]` for the user across the given item ids."
  def reactions_for_items(%Scope{user: user}, item_ids) do
    from(ir in ItemReaction,
      where: ir.user_id == ^user.id and ir.item_id in ^item_ids,
      order_by: [asc: ir.id],
      select: {ir.item_id, ir.emoji}
    )
    |> Repo.all()
    |> Enum.group_by(fn {item_id, _} -> item_id end, fn {_, emoji} -> emoji end)
  end

  @doc "Sets the virtual `:reactions` field on a list of items for the user."
  def put_reactions(_scope, []), do: []

  def put_reactions(%Scope{} = scope, items) do
    by_item = reactions_for_items(scope, Enum.map(items, & &1.id))
    Enum.map(items, fn item -> %{item | reactions: Map.get(by_item, item.id, [])} end)
  end

  ## Saved view -----------------------------------------------------------------

  @doc """
  Items the user has reacted with `emoji` (across all feeds), newest first,
  enriched with read state and reactions. Supports keyset pagination via
  `:before` = `{sort_at, id}`.
  """
  def list_reacted_items(%Scope{user: user} = scope, emoji, opts \\ []) do
    limit = Keyword.get(opts, :limit, 40)

    query =
      from(i in Item,
        join: ir in ItemReaction,
        on: ir.item_id == i.id and ir.user_id == ^user.id and ir.emoji == ^emoji,
        left_join: rd in ItemRead,
        on: rd.item_id == i.id and rd.user_id == ^user.id,
        order_by: [desc: i.sort_at, desc: i.id],
        limit: ^limit,
        preload: [:feed],
        select_merge: %{read: not is_nil(rd.id)}
      )

    query =
      case Keyword.get(opts, :before) do
        {sort_at, id} ->
          from(i in query, where: i.sort_at < ^sort_at or (i.sort_at == ^sort_at and i.id < ^id))

        nil ->
          query
      end

    query
    |> FeedPug.Feeds.search(Keyword.get(opts, :query))
    |> Repo.all()
    |> then(&put_reactions(scope, &1))
  end
end
