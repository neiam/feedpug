defmodule FeedPugWeb.Api.SourceController do
  use FeedPugWeb, :controller

  alias FeedPug.{Groups, Reactions, Timelines}
  alias FeedPugWeb.Api.Shape

  @doc "GET /api/sources — newsfeed sources (own groups + follows) for filtering."
  def index(conn, _params) do
    scope = conn.assigns.current_scope
    json(conn, %{sources: Enum.map(Groups.list_newsfeed_sources(scope), &Shape.source/1)})
  end

  @doc "GET /api/slices — the user's saved timeline views (filtersets)."
  def slices(conn, _params) do
    scope = conn.assigns.current_scope
    json(conn, %{slices: Enum.map(Timelines.list_slices(scope), &Shape.slice/1)})
  end

  @doc "GET /api/reactions — the user's reaction palette."
  def reactions(conn, _params) do
    scope = conn.assigns.current_scope
    palette = Reactions.ensure_default_reactions(scope)
    json(conn, %{reactions: Enum.map(palette, &Shape.reaction/1)})
  end
end
