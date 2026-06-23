defmodule FeedPugWeb.Api.TimelineController do
  use FeedPugWeb, :controller

  alias FeedPug.{Feeds, Groups, Reactions}
  alias FeedPugWeb.Api.Shape

  @max_limit 100

  @doc """
  GET /api/timeline — the aggregated newsfeed.

  Query params: `sources` (csv of source keys; omit for all), `unread` ("true"),
  `reaction` (emoji; overrides group filtering, spans all feeds), `before`
  (cursor `"<sort_at ISO8601>,<id>"`), `limit`.
  """
  def index(conn, params) do
    scope = conn.assigns.current_scope
    limit = parse_limit(params["limit"])
    before = parse_cursor(params["before"])

    query = params["q"]

    items =
      case present(params["reaction"]) do
        nil ->
          feed_ids = resolve_feed_ids(scope, params["sources"])

          Feeds.list_newsfeed_items(feed_ids,
            limit: limit,
            user_id: scope.user.id,
            unread_only: params["unread"] == "true",
            query: query,
            before: before
          )
          |> then(&Reactions.put_reactions(scope, &1))

        emoji ->
          Reactions.list_reacted_items(scope, emoji, limit: limit, query: query, before: before)
      end

    json(conn, %{items: Enum.map(items, &Shape.item/1), next_before: next_cursor(items, limit)})
  end

  @doc "POST /api/timeline/read_all — mark all items in the (optionally filtered) feed set read."
  def read_all(conn, params) do
    scope = conn.assigns.current_scope
    Feeds.mark_all_read(scope.user.id, resolve_feed_ids(scope, params["sources"]))
    json(conn, %{ok: true})
  end

  ## Helpers

  defp resolve_feed_ids(scope, sources_param) do
    sources = Groups.list_newsfeed_sources(scope)

    selected =
      case present(sources_param) do
        nil ->
          sources

        csv ->
          keys = csv |> String.split(",", trim: true) |> MapSet.new()
          Enum.filter(sources, &MapSet.member?(keys, &1.key))
      end

    selected |> Enum.flat_map(& &1.feed_ids) |> Enum.uniq()
  end

  defp parse_limit(nil), do: 40

  defp parse_limit(str) do
    case Integer.parse(to_string(str)) do
      {n, _} when n > 0 -> min(n, @max_limit)
      _ -> 40
    end
  end

  defp parse_cursor(nil), do: nil

  defp parse_cursor(str) do
    with [iso, id] <- String.split(str, ",", parts: 2),
         {:ok, dt, _} <- DateTime.from_iso8601(iso),
         {id_int, ""} <- Integer.parse(id) do
      {DateTime.truncate(dt, :second), id_int}
    else
      _ -> nil
    end
  end

  defp next_cursor(items, limit) when length(items) == limit do
    last = List.last(items)
    "#{DateTime.to_iso8601(last.sort_at)},#{last.id}"
  end

  defp next_cursor(_items, _limit), do: nil

  defp present(nil), do: nil
  defp present(""), do: nil
  defp present(str), do: str
end
