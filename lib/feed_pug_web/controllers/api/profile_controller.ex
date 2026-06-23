defmodule FeedPugWeb.Api.ProfileController do
  use FeedPugWeb, :controller

  def show(conn, _params) do
    user = conn.assigns.current_scope.user
    json(conn, %{user: %{id: user.id, email: user.email}})
  end
end
