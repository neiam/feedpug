defmodule FeedPug.ApiTokensTest do
  use FeedPug.DataCase, async: true

  import FeedPug.AccountsFixtures

  alias FeedPug.Accounts
  alias FeedPug.Accounts.ApiToken

  test "create, list, validate (bumps last_used), and delete" do
    scope = user_scope_fixture()

    assert {:ok, token} = Accounts.create_api_token(scope, label: "phone")
    assert String.starts_with?(token.token, "fp_")
    assert [listed] = Accounts.list_api_tokens(scope)
    assert listed.id == token.id

    user = Accounts.fetch_user_by_api_token(token.token)
    assert user.id == scope.user.id
    assert Accounts.list_api_tokens(scope) |> hd() |> Map.get(:last_used_at)

    assert {:ok, _} = Accounts.delete_api_token(scope, token.id)
    assert Accounts.list_api_tokens(scope) == []
    refute Accounts.fetch_user_by_api_token(token.token)
  end

  test "expired tokens are rejected" do
    scope = user_scope_fixture()
    {:ok, token} = Accounts.create_api_token(scope, expires_in_days: 1)

    past = DateTime.utc_now() |> DateTime.add(-10, :second) |> DateTime.truncate(:second)
    Repo.update_all(ApiToken, set: [expires_at: past])

    refute Accounts.fetch_user_by_api_token(token.token)
  end

  test "unknown tokens return nil" do
    refute Accounts.fetch_user_by_api_token("fp_nonexistent")
    refute Accounts.fetch_user_by_api_token(nil)
  end
end
