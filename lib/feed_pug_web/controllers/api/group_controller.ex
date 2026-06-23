defmodule FeedPugWeb.Api.GroupController do
  use FeedPugWeb, :controller

  alias FeedPug.Groups
  alias FeedPug.Groups.GroupFeed
  alias FeedPugWeb.Api.Shape

  @doc "GET /api/groups — the user's group tree, each with its direct feeds."
  def index(conn, _params) do
    scope = conn.assigns.current_scope

    groups =
      Enum.map(Groups.list_groups(scope), fn group ->
        group
        |> Shape.group()
        |> Map.put(:feeds, Enum.map(Groups.list_group_feeds(group), &Shape.group_feed/1))
      end)

    json(conn, %{groups: groups})
  end

  @doc "POST /api/groups — create a (sub)group. Body: {name, parent_id?}."
  def create(conn, params) do
    scope = conn.assigns.current_scope
    parent = params["parent_id"] && Groups.get_group!(scope, params["parent_id"])

    case Groups.create_group(scope, %{"name" => params["name"]}, parent) do
      {:ok, group} -> conn |> put_status(:created) |> json(%{group: Shape.group(group)})
      {:error, changeset} -> unprocessable(conn, changeset)
    end
  end

  @doc "DELETE /api/groups/:id"
  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    case Groups.delete_group(scope, Groups.get_group!(scope, id)) do
      {:ok, _} -> json(conn, %{ok: true})
      {:error, :default_group} -> unprocessable(conn, "cannot delete a default group")
    end
  end

  @doc "POST /api/groups/:id/feeds — add a feed by URL. Body: {url, custom_title?}."
  def add_feed(conn, %{"id" => id} = params) do
    scope = conn.assigns.current_scope
    group = Groups.get_group!(scope, id)

    case Groups.add_feed_to_group(scope, group, params["url"], params["custom_title"]) do
      {:ok, group_feed} ->
        group_feed = FeedPug.Repo.preload(group_feed, :feed)
        conn |> put_status(:created) |> json(%{group_feed: Shape.group_feed(group_feed)})

      {:error, changeset} ->
        unprocessable(conn, changeset)
    end
  end

  @doc "DELETE /api/group_feeds/:id — remove a feed membership."
  def remove_feed(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope
    group_feed = FeedPug.Repo.get!(GroupFeed, id)
    {:ok, _} = Groups.remove_feed_from_group(scope, group_feed)
    json(conn, %{ok: true})
  end

  defp unprocessable(conn, %Ecto.Changeset{} = changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)

    conn |> put_status(:unprocessable_entity) |> json(%{errors: errors})
  end

  defp unprocessable(conn, message) when is_binary(message) do
    conn |> put_status(:unprocessable_entity) |> json(%{error: message})
  end
end
