defmodule FeedPug.TimelinesTest do
  use FeedPug.DataCase, async: true

  import FeedPug.AccountsFixtures

  alias FeedPug.Timelines

  test "creates, lists and deletes slices" do
    scope = user_scope_fixture()

    assert {:ok, slice} =
             Timelines.create_slice(scope, %{
               name: "Tech",
               source_keys: ["group:1", "follow:2"],
               unread_only: true,
               reaction_emoji: "⭐"
             })

    assert slice.source_keys == ["group:1", "follow:2"]
    assert slice.unread_only
    assert slice.reaction_emoji == "⭐"
    assert [listed] = Timelines.list_slices(scope)
    assert listed.id == slice.id

    assert {:ok, _} = Timelines.delete_slice(scope, slice.id)
    assert Timelines.list_slices(scope) == []
  end

  test "slice names are unique per user" do
    scope = user_scope_fixture()
    {:ok, _} = Timelines.create_slice(scope, %{name: "X", source_keys: []})
    assert {:error, _} = Timelines.create_slice(scope, %{name: "X", source_keys: []})
  end

  test "slices are scoped per user" do
    a = user_scope_fixture()
    b = user_scope_fixture()
    {:ok, _} = Timelines.create_slice(a, %{name: "Mine", source_keys: []})
    assert Timelines.list_slices(b) == []
  end
end
