defmodule FeedPugWeb.Api.ItemController do
  use FeedPugWeb, :controller

  alias FeedPug.{Feeds, Reactions}
  alias FeedPugWeb.Api.Shape

  @doc "GET /api/items/:id — full item content with read state and reactions."
  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    item = Feeds.get_user_item!(scope.user.id, id)
    [item] = Reactions.put_reactions(scope, [item])
    json(conn, %{item: Shape.item_full(item)})
  end

  @doc "POST /api/items/:id/read — mark an item read."
  def read(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    Feeds.mark_read(scope.user.id, String.to_integer(id))
    json(conn, %{ok: true})
  end

  @doc "POST /api/items/:id/unread — mark an item unread."
  def unread(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    Feeds.mark_unread(scope.user.id, String.to_integer(id))
    json(conn, %{ok: true})
  end

  @doc "POST /api/items/:id/reactions — toggle an emoji reaction. Body: {emoji}."
  def react(conn, %{"id" => id, "emoji" => emoji}) do
    scope = conn.assigns.current_scope
    item_id = String.to_integer(id)
    state = Reactions.toggle_item_reaction(scope, item_id, emoji)
    reactions = Reactions.reactions_for_items(scope, [item_id]) |> Map.get(item_id, [])
    json(conn, %{state: state, reactions: reactions})
  end
end
