defmodule FeedPug.InvitesTest do
  use FeedPug.DataCase, async: false

  import FeedPug.AccountsFixtures

  alias FeedPug.Accounts
  alias FeedPug.Accounts.Invite

  defp user, do: user_fixture()

  test "create_invite makes an owned, active, single-use token" do
    owner = user()
    assert {:ok, invite} = Accounts.create_invite(owner)
    assert invite.created_by_id == owner.id
    assert is_binary(invite.token)
    assert Invite.active?(invite)
    assert [listed] = Accounts.list_invites(owner)
    assert listed.id == invite.id
  end

  test "get_active_invite returns active invites and rejects consumed/expired/unknown" do
    owner = user()
    {:ok, invite} = Accounts.create_invite(owner)
    assert %Invite{id: id} = Accounts.get_active_invite(invite.token)
    assert id == invite.id

    # consumed → inactive
    redeemer = user()
    {:ok, _} = Accounts.consume_invite(invite, redeemer)
    refute Accounts.get_active_invite(invite.token)

    refute Accounts.get_active_invite("nope")
    refute Accounts.get_active_invite(nil)

    # expired
    {:ok, past} =
      Accounts.create_invite(owner, %{expires_at: DateTime.utc_now() |> DateTime.add(-60)})

    refute Accounts.get_active_invite(past.token)
  end

  test "consume_invite is idempotent" do
    owner = user()
    redeemer = user()
    {:ok, invite} = Accounts.create_invite(owner)
    {:ok, consumed} = Accounts.consume_invite(invite, redeemer)
    assert consumed.consumed_by_id == redeemer.id
    {:ok, again} = Accounts.consume_invite(consumed, user())
    # still attributed to the first redeemer
    assert again.consumed_by_id == redeemer.id
  end

  test "revoke_invite only by owner; revoked invite is no longer active" do
    owner = user()
    other = user()
    {:ok, invite} = Accounts.create_invite(owner)

    assert {:error, :forbidden} = Accounts.revoke_invite(other, invite)
    assert {:ok, revoked} = Accounts.revoke_invite(owner, invite)
    refute Invite.active?(revoked)
    refute Accounts.get_active_invite(invite.token)
  end

  test "create_system_invite is unowned" do
    assert {:ok, invite} = Accounts.create_system_invite()
    assert is_nil(invite.created_by_id)
    assert Invite.active?(invite)
  end

  test "registration_open? reflects config" do
    Application.put_env(:feed_pug, :registration_open, false)
    on_exit(fn -> Application.put_env(:feed_pug, :registration_open, true) end)
    refute Accounts.registration_open?()

    Application.put_env(:feed_pug, :registration_open, true)
    assert Accounts.registration_open?()
  end
end
