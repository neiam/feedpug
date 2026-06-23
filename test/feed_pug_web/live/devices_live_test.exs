defmodule FeedPugWeb.DevicesLiveTest do
  use FeedPugWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FeedPug.Accounts

  setup :register_and_log_in_user

  test "generates a token and renders the pairing QR + URI", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/devices")

    lv |> form("#token-form", token: %{label: "My phone", days: ""}) |> render_submit()

    assert [token] = Accounts.list_api_tokens(scope)
    html = render(lv)
    assert html =~ "feedpug://pair?base="
    assert html =~ token.token
    assert html =~ "<svg"
  end

  test "a used token can no longer be paired", %{conn: conn, scope: scope} do
    {:ok, token} = Accounts.create_api_token(scope, label: "phone")
    # Simulate a device pairing: validating the token bumps last_used_at.
    Accounts.fetch_user_by_api_token(token.token)

    {:ok, lv, _html} = live(conn, ~p"/devices")
    refute has_element?(lv, "#token-#{token.id} button", "Pair")
    assert has_element?(lv, "#token-#{token.id}", "paired")
  end

  test "revokes a token", %{conn: conn, scope: scope} do
    {:ok, token} = Accounts.create_api_token(scope, label: "old")
    {:ok, lv, _html} = live(conn, ~p"/devices")

    lv |> element("#token-#{token.id} button", "Revoke") |> render_click()
    assert Accounts.list_api_tokens(scope) == []
  end
end
