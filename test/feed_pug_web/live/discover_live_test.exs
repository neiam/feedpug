defmodule FeedPugWeb.DiscoverLiveTest do
  use FeedPugWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import FeedPug.AccountsFixtures

  alias FeedPug.{Feeds, Groups}

  setup :register_and_log_in_user

  defp group(scope, path), do: Enum.find(Groups.list_groups(scope), &(&1.path == path))

  test "follow another user's group, then see its feeds aggregate into the newsfeed",
       %{conn: conn, scope: alice} do
    bob = user_scope_fixture()
    {:ok, _gf} = Groups.add_feed_to_group(bob, group(bob, "comics"), "https://ex.com/bob.xml")
    bob_comics = group(bob, "comics")

    {:ok, lv, _html} = live(conn, ~p"/discover")
    assert has_element?(lv, "#followable-#{bob_comics.id}")

    lv |> element("#followable-#{bob_comics.id} button", "Follow") |> render_click()

    # Alice now follows Bob's comics; the follow shows in the Following section.
    assert has_element?(lv, "[id^='follow-']")
    assert bob_comics.id in Enum.map(Groups.list_follows(alice), & &1.group_id)
  end

  test "copy a feed from a followed group into your own group", %{conn: conn, scope: alice} do
    bob = user_scope_fixture()
    {:ok, gf} = Groups.add_feed_to_group(bob, group(bob, "comics"), "https://ex.com/bob.xml")
    {:ok, _follow} = Groups.follow_group(alice, group(bob, "comics"))

    {:ok, lv, _html} = live(conn, ~p"/discover")

    lv
    |> element("button[phx-value-feed-id='#{gf.feed_id}']", "copy to mine")
    |> render_click()

    # The feed is now pinned in one of Alice's own groups (same canonical feed).
    own_feed_ids =
      alice
      |> Groups.list_groups()
      |> Enum.flat_map(&Groups.list_group_feeds/1)
      |> Enum.map(& &1.feed_id)

    assert gf.feed_id in own_feed_ids
    assert Feeds.get_feed!(gf.feed_id)
  end

  test "toggling a subgroup excludes it from the follower's newsfeed", %{conn: conn, scope: alice} do
    bob = user_scope_fixture()
    bob_comics = group(bob, "comics")
    {:ok, sad} = Groups.create_group(bob, %{"name" => "sad"}, bob_comics)
    {:ok, root_gf} = Groups.add_feed_to_group(bob, bob_comics, "https://ex.com/a.xml")
    {:ok, _sad_gf} = Groups.add_feed_to_group(bob, sad, "https://ex.com/b.xml")
    {:ok, _follow} = Groups.follow_group(alice, bob_comics)

    {:ok, lv, _html} = live(conn, ~p"/discover")

    # Hide the "sad" subgroup.
    lv |> element("button[phx-value-group-id='#{sad.id}']") |> render_click()

    assert Groups.effective_feed_ids(alice) == [root_gf.feed_id]

    # Toggle it back on.
    lv |> element("button[phx-value-group-id='#{sad.id}']") |> render_click()
    assert sad.id not in Enum.map(Groups.effective_feed_ids(alice), & &1)
    assert length(Groups.effective_feed_ids(alice)) == 2
  end
end
