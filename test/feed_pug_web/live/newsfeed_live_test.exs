defmodule FeedPugWeb.NewsfeedLiveTest do
  use FeedPugWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FeedPug.{Feeds, Groups, Reactions, Timelines}

  setup :register_and_log_in_user

  defp comics(scope), do: Enum.find(Groups.list_groups(scope), &(&1.path == "comics"))

  test "empty newsfeed shows an empty-state prompt", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/")
    assert html =~ "Your newsfeed is empty"
  end

  test "shows items from feeds in the user's own groups", %{conn: conn, scope: scope} do
    {:ok, gf} = Groups.add_feed_to_group(scope, comics(scope), "https://ex.com/a.xml")
    feed = Feeds.get_feed!(gf.feed_id)

    Feeds.store_items(feed, [
      %{guid: "g1", title: "Hello World", published_at: ~U[2024-01-01 00:00:00Z]}
    ])

    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#items")
    assert render(lv) =~ "Hello World"
  end

  test "new polled items arrive live via PubSub", %{conn: conn, scope: scope} do
    {:ok, gf} = Groups.add_feed_to_group(scope, comics(scope), "https://ex.com/a.xml")
    feed = Feeds.get_feed!(gf.feed_id)

    {:ok, lv, _html} = live(conn, ~p"/")

    # Simulate the fetcher broadcasting a freshly inserted item.
    {_n, [item]} =
      Feeds.store_items(feed, [
        %{guid: "live1", title: "Breaking", published_at: ~U[2024-02-02 00:00:00Z]}
      ])

    Phoenix.PubSub.broadcast(
      FeedPug.PubSub,
      Feeds.feed_topic(feed.id),
      {:new_items, feed.id, [item]}
    )

    assert render(lv) =~ "Breaking"
  end

  test "selecting an entry shows its content in the detail pane and marks it read",
       %{conn: conn, scope: scope} do
    {:ok, gf} = Groups.add_feed_to_group(scope, comics(scope), "https://ex.com/a.xml")
    feed = Feeds.get_feed!(gf.feed_id)

    {_n, [item]} =
      Feeds.store_items(feed, [
        %{
          guid: "g1",
          title: "Read Me",
          content: "<p>FULL BODY TEXT</p>",
          published_at: ~U[2024-01-01 00:00:00Z]
        }
      ])

    {:ok, lv, _html} = live(conn, ~p"/")
    refute render(lv) =~ "FULL BODY TEXT"

    lv |> element("#items-#{item.id}") |> render_click()

    html = render(lv)
    assert html =~ "FULL BODY TEXT"
    assert html =~ "Open original"
    assert Feeds.unread_count(scope.user.id, [feed.id]) == 0
  end

  test "the unread-only toggle hides read entries", %{conn: conn, scope: scope} do
    {:ok, gf} = Groups.add_feed_to_group(scope, comics(scope), "https://ex.com/a.xml")
    feed = Feeds.get_feed!(gf.feed_id)

    {_n, inserted} =
      Feeds.store_items(feed, [
        %{guid: "a", title: "Already Read", published_at: ~U[2024-01-01 00:00:00Z]},
        %{guid: "b", title: "Still Unread", published_at: ~U[2024-01-02 00:00:00Z]}
      ])

    read = Enum.find(inserted, &(&1.guid == "a"))
    unread = Enum.find(inserted, &(&1.guid == "b"))
    Feeds.mark_read(scope.user.id, read.id)

    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#items-#{read.id}")
    assert has_element?(lv, "#items-#{unread.id}")

    lv |> element("input[phx-click='toggle_unread_only']") |> render_click()

    refute has_element?(lv, "#items-#{read.id}")
    assert has_element?(lv, "#items-#{unread.id}")
  end

  test "saving an entry with a reaction, then filtering the list by it",
       %{conn: conn, scope: scope} do
    {:ok, gf} = Groups.add_feed_to_group(scope, comics(scope), "https://ex.com/a.xml")
    feed = Feeds.get_feed!(gf.feed_id)

    {_n, [saved]} =
      Feeds.store_items(feed, [
        %{guid: "s", title: "Save me", published_at: ~U[2024-01-02 00:00:00Z]}
      ])

    {_n, [other]} =
      Feeds.store_items(feed, [
        %{guid: "o", title: "Ignore me", published_at: ~U[2024-01-01 00:00:00Z]}
      ])

    {:ok, lv, _html} = live(conn, ~p"/")

    lv |> element("#items-#{saved.id}") |> render_click()
    lv |> element("button[phx-click='toggle_reaction'][phx-value-emoji='⭐']") |> render_click()

    assert Reactions.reactions_for_items(scope, [saved.id]) == %{saved.id => ["⭐"]}

    # Filtering by the star shows only the saved entry.
    lv |> element("button[phx-click='filter_reaction'][phx-value-emoji='⭐']") |> render_click()
    assert has_element?(lv, "#items-#{saved.id}")
    refute has_element?(lv, "#items-#{other.id}")
  end

  test "the group filter restricts the timeline to selected groups", %{conn: conn, scope: scope} do
    comics = comics(scope)
    news = Enum.find(Groups.list_groups(scope), &(&1.path == "news"))

    {:ok, cgf} = Groups.add_feed_to_group(scope, comics, "https://ex.com/c.xml")
    {:ok, ngf} = Groups.add_feed_to_group(scope, news, "https://ex.com/n.xml")

    {_n, [citem]} =
      Feeds.store_items(Feeds.get_feed!(cgf.feed_id), [
        %{guid: "c", title: "Comic Item", published_at: ~U[2024-01-01 00:00:00Z]}
      ])

    {_n, [nitem]} =
      Feeds.store_items(Feeds.get_feed!(ngf.feed_id), [
        %{guid: "n", title: "News Item", published_at: ~U[2024-01-02 00:00:00Z]}
      ])

    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#items-#{citem.id}")
    assert has_element?(lv, "#items-#{nitem.id}")

    # Deselect the news group.
    lv
    |> element("input[phx-click='toggle_source'][phx-value-key='group:#{news.id}']")
    |> render_click()

    assert has_element?(lv, "#items-#{citem.id}")
    refute has_element?(lv, "#items-#{nitem.id}")
  end

  test "clicking a feed's favicon/title drills into only that feed", %{conn: conn, scope: scope} do
    comics = comics(scope)
    # Both feeds live in the SAME group, so this is a per-feed filter, not a group one.
    {:ok, agf} = Groups.add_feed_to_group(scope, comics, "https://ex.com/a.xml")
    {:ok, bgf} = Groups.add_feed_to_group(scope, comics, "https://ex.com/b.xml")

    {_n, [aitem]} =
      Feeds.store_items(Feeds.get_feed!(agf.feed_id), [
        %{guid: "a", title: "Alpha Post", published_at: ~U[2024-01-01 00:00:00Z]}
      ])

    {_n, [bitem]} =
      Feeds.store_items(Feeds.get_feed!(bgf.feed_id), [
        %{guid: "b", title: "Beta Post", published_at: ~U[2024-01-02 00:00:00Z]}
      ])

    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#items-#{aitem.id}")
    assert has_element?(lv, "#items-#{bitem.id}")

    # Click feed A's title in its row (nested button must filter, not select-row).
    lv
    |> element("#items-#{aitem.id} button[phx-value-feed-id='#{agf.feed_id}']")
    |> render_click()

    assert render(lv) =~ "Showing only"
    assert has_element?(lv, "#items-#{aitem.id}")
    refute has_element?(lv, "#items-#{bitem.id}")

    # Clearing restores the full set.
    lv |> element("button[phx-click='clear_feed_filter']") |> render_click()
    assert has_element?(lv, "#items-#{aitem.id}")
    assert has_element?(lv, "#items-#{bitem.id}")
  end

  test "search filters the timeline by entry text", %{conn: conn, scope: scope} do
    {:ok, gf} = Groups.add_feed_to_group(scope, comics(scope), "https://ex.com/a.xml")
    feed = Feeds.get_feed!(gf.feed_id)

    {_n, [elixir]} =
      Feeds.store_items(feed, [
        %{guid: "e", title: "Elixir 1.20", published_at: ~U[2024-01-02 00:00:00Z]}
      ])

    {_n, [cats]} =
      Feeds.store_items(feed, [
        %{guid: "c", title: "Cat photos", published_at: ~U[2024-01-01 00:00:00Z]}
      ])

    {:ok, lv, _html} = live(conn, ~p"/")
    assert has_element?(lv, "#items-#{elixir.id}")
    assert has_element?(lv, "#items-#{cats.id}")

    lv |> form("form[phx-change='search']", %{q: "elixir"}) |> render_change()

    assert has_element?(lv, "#items-#{elixir.id}")
    refute has_element?(lv, "#items-#{cats.id}")
  end

  test "'only' isolates a single group, and a saved view re-applies the filterset",
       %{conn: conn, scope: scope} do
    comics = comics(scope)
    news = Enum.find(Groups.list_groups(scope), &(&1.path == "news"))
    {:ok, cgf} = Groups.add_feed_to_group(scope, comics, "https://ex.com/c.xml")
    {:ok, ngf} = Groups.add_feed_to_group(scope, news, "https://ex.com/n.xml")

    {_n, [citem]} =
      Feeds.store_items(Feeds.get_feed!(cgf.feed_id), [
        %{guid: "c", title: "Comic Item", published_at: ~U[2024-01-01 00:00:00Z]}
      ])

    {_n, [nitem]} =
      Feeds.store_items(Feeds.get_feed!(ngf.feed_id), [
        %{guid: "n", title: "News Item", published_at: ~U[2024-01-02 00:00:00Z]}
      ])

    {:ok, lv, _html} = live(conn, ~p"/")

    # "only" comics.
    lv
    |> element("button[phx-click='only_source'][phx-value-key='group:#{comics.id}']")
    |> render_click()

    assert has_element?(lv, "#items-#{citem.id}")
    refute has_element?(lv, "#items-#{nitem.id}")

    # Save it as a view.
    lv |> form("form[phx-submit='save_slice']", slice: %{name: "Just comics"}) |> render_submit()
    assert [slice] = Timelines.list_slices(scope)

    # Widen back to all groups...
    lv |> element("button[phx-click='select_all_sources']") |> render_click()
    assert has_element?(lv, "#items-#{nitem.id}")

    # ...then re-apply the saved view to get back to comics-only.
    lv |> element("button[phx-click='apply_slice'][phx-value-id='#{slice.id}']") |> render_click()
    assert has_element?(lv, "#items-#{citem.id}")
    refute has_element?(lv, "#items-#{nitem.id}")
  end
end
