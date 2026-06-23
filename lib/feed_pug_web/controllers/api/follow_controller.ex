defmodule FeedPugWeb.Api.FollowController do
  use FeedPugWeb, :controller

  alias FeedPug.Groups
  alias FeedPugWeb.Api.Shape

  @doc "GET /api/follows — groups the user follows."
  def index(conn, _params) do
    scope = conn.assigns.current_scope
    json(conn, %{follows: Enum.map(Groups.list_follows(scope), &Shape.follow/1)})
  end

  @doc "GET /api/discover — other users' shareable groups."
  def discover(conn, _params) do
    scope = conn.assigns.current_scope

    groups =
      Enum.map(Groups.list_followable_groups(scope), fn group ->
        group |> Shape.group() |> Map.put(:owner_email, group.user.email)
      end)

    json(conn, %{groups: groups})
  end

  @doc "POST /api/follows — follow a group. Body: {group_id}."
  def create(conn, %{"group_id" => group_id}) do
    scope = conn.assigns.current_scope

    case Groups.follow_group(scope, Groups.get_group(group_id)) do
      {:ok, follow} ->
        follow = FeedPug.Repo.preload(follow, [:exclusions, group: :user])
        conn |> put_status(:created) |> json(%{follow: Shape.follow(follow)})

      {:error, reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: to_string(reason)})
    end
  end

  @doc "DELETE /api/follows/:id"
  def delete(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    case Enum.find(Groups.list_follows(scope), &(to_string(&1.id) == id)) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not found"})

      follow ->
        {:ok, _} = Groups.unfollow_group(scope, follow)
        json(conn, %{ok: true})
    end
  end
end
