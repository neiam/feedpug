defmodule FeedPugWeb.InvitesLiveTest do
  use FeedPugWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import FeedPug.AccountsFixtures

  alias FeedPug.Accounts

  describe "gated registration" do
    setup do
      # Close registration for these tests; the suite default is open.
      Application.put_env(:feed_pug, :registration_open, false)
      on_exit(fn -> Application.put_env(:feed_pug, :registration_open, true) end)
      :ok
    end

    test "register page is invite-only without a token", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")
      assert html =~ "invite-only"
      refute html =~ "registration_form"
    end

    test "a valid invite token shows the form and registering consumes it", %{conn: conn} do
      owner = user_fixture()
      {:ok, invite} = Accounts.create_invite(owner)

      {:ok, lv, html} = live(conn, ~p"/users/register?invite=#{invite.token}")
      assert html =~ "your invite is valid"

      email = unique_user_email()
      lv |> form("#registration_form", user: %{email: email}) |> render_submit()

      # invite is now consumed by the new user
      refute Accounts.get_active_invite(invite.token)
      assert Accounts.get_user_by_email(email)
    end

    test "an unknown invite token is still gated", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register?invite=bogus")
      assert html =~ "invite-only"
    end
  end

  describe "invites management" do
    setup :register_and_log_in_user

    test "create and revoke an invite", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/users/invites")

      lv |> element("#btn-create-invite") |> render_click()
      assert [invite] = Accounts.list_invites(scope.user)
      assert render(lv) =~ invite.token

      lv |> element("#invites-#{invite.id} button[phx-click='revoke_invite']") |> render_click()
      assert [revoked] = Accounts.list_invites(scope.user)
      assert revoked.consumed_at
      refute Accounts.get_active_invite(invite.token)
    end
  end
end
