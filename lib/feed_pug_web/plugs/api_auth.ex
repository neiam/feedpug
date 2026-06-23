defmodule FeedPugWeb.Plugs.ApiAuth do
  @moduledoc """
  Authenticates JSON API requests via `Authorization: Bearer <api_token>` and
  assigns `current_scope`. Halts with `401` JSON when the token is missing,
  unknown, or expired. Mirrors the device-pairing flow used by the mobile app.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias FeedPug.Accounts
  alias FeedPug.Accounts.Scope

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         %Accounts.User{} = user <- Accounts.fetch_user_by_api_token(token) do
      assign(conn, :current_scope, Scope.for_user(user))
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "unauthorized"})
        |> halt()
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> present(token)
      ["bearer " <> token | _] -> present(token)
      _ -> :error
    end
  end

  defp present(token) do
    case String.trim(token) do
      "" -> :error
      trimmed -> {:ok, trimmed}
    end
  end
end
