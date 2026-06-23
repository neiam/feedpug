defmodule FeedPug.FeedsTest do
  use FeedPug.DataCase, async: true

  import FeedPug.AccountsFixtures

  alias FeedPug.Feeds

  describe "upsert_feed_by_url/2" do
    test "creates a feed due immediately, then is idempotent" do
      assert {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")
      assert feed.status == "active"
      assert feed.next_fetch_at

      assert {:ok, same} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")
      assert same.id == feed.id
    end

    test "trims surrounding whitespace in the URL" do
      {:ok, feed} = Feeds.upsert_feed_by_url("  https://ex.com/x.xml  ")
      assert feed.url == "https://ex.com/x.xml"
    end
  end

  describe "store_items/2" do
    test "inserts items, dedupes by guid, and is idempotent across calls" do
      {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")

      entries = [
        %{guid: "g1", title: "One", published_at: ~U[2024-01-01 00:00:00Z]},
        %{guid: "g1", title: "dup-in-batch"},
        %{guid: "g2", title: "Two", published_at: ~U[2024-01-02 00:00:00Z]},
        %{guid: nil, title: "no guid dropped"}
      ]

      {total, inserted} = Feeds.store_items(feed, entries)
      assert total == 2
      assert length(inserted) == 2

      # Second run inserts nothing new.
      {_total, inserted2} = Feeds.store_items(feed, entries)
      assert inserted2 == []
    end
  end

  describe "list_newsfeed_items/2" do
    test "returns [] for an empty feed set without querying" do
      assert Feeds.list_newsfeed_items([]) == []
    end

    test "orders newest first and paginates via keyset cursor" do
      {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")

      Feeds.store_items(feed, [
        %{guid: "a", title: "A", published_at: ~U[2024-01-01 00:00:00Z]},
        %{guid: "b", title: "B", published_at: ~U[2024-01-02 00:00:00Z]},
        %{guid: "c", title: "C", published_at: ~U[2024-01-03 00:00:00Z]}
      ])

      [first, second] = Feeds.list_newsfeed_items([feed.id], limit: 2)
      assert [first.title, second.title] == ["C", "B"]

      cursor = {second.sort_at, second.id}
      assert [third] = Feeds.list_newsfeed_items([feed.id], limit: 2, before: cursor)
      assert third.title == "A"
    end

    test "orders by the latest available date, so a revised entry sorts above a newer-published one" do
      {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")

      Feeds.store_items(feed, [
        # Older published, but revised most recently -> should sort first.
        %{
          guid: "x",
          title: "Revised",
          published_at: ~U[2024-01-01 00:00:00Z],
          revised_at: ~U[2024-03-01 00:00:00Z]
        },
        %{guid: "y", title: "Newer", published_at: ~U[2024-02-01 00:00:00Z]}
      ])

      titles = [feed.id] |> Feeds.list_newsfeed_items() |> Enum.map(& &1.title)
      assert titles == ["Revised", "Newer"]
    end
  end

  describe "full-text search" do
    test "filters timeline items by a query over title/summary/content" do
      {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")

      Feeds.store_items(feed, [
        %{guid: "a", title: "Elixir release notes", published_at: ~U[2024-01-01 00:00:00Z]},
        %{
          guid: "b",
          title: "Cat photos",
          summary: "fluffy kittens",
          published_at: ~U[2024-01-02 00:00:00Z]
        },
        %{
          guid: "c",
          title: "Recipe",
          content: "<p>roast elixir of life</p>",
          published_at: ~U[2024-01-03 00:00:00Z]
        }
      ])

      titles = fn q ->
        Feeds.list_newsfeed_items([feed.id], query: q) |> Enum.map(& &1.title) |> Enum.sort()
      end

      assert titles.("elixir") == ["Elixir release notes", "Recipe"]
      assert titles.("kittens") == ["Cat photos"]
      assert titles.("nonexistentword") == []
      # Blank query is a no-op (returns everything).
      assert length(Feeds.list_newsfeed_items([feed.id], query: "  ")) == 3
    end

    test "matches word prefixes (fuzzy), e.g. \"holo\" finds \"holographic\"" do
      {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")

      Feeds.store_items(feed, [
        %{guid: "h", title: "Holographic displays", published_at: ~U[2024-01-01 00:00:00Z]},
        %{guid: "p", title: "Plain old news", published_at: ~U[2024-01-02 00:00:00Z]}
      ])

      titles = fn q -> Feeds.list_newsfeed_items([feed.id], query: q) |> Enum.map(& &1.title) end

      assert titles.("holo") == ["Holographic displays"]
      assert titles.("holographic") == ["Holographic displays"]
      # Multiple partial words AND together.
      assert titles.("holo disp") == ["Holographic displays"]
      assert titles.("holo news") == []
    end
  end

  describe "read / unread state" do
    setup do
      user = user_fixture()
      {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")

      Feeds.store_items(feed, [
        %{guid: "a", title: "A", published_at: ~U[2024-01-01 00:00:00Z]},
        %{guid: "b", title: "B", published_at: ~U[2024-01-02 00:00:00Z]}
      ])

      %{user: user, feed: feed}
    end

    test "items start unread and counts reflect it", %{user: user, feed: feed} do
      assert Feeds.unread_count(user.id, [feed.id]) == 2
      assert Feeds.unread_counts_by_feed(user.id, [feed.id]) == %{feed.id => 2}

      items = Feeds.list_newsfeed_items([feed.id], user_id: user.id)
      assert Enum.all?(items, &(&1.read == false))
    end

    test "mark_read flips a single item and is idempotent", %{user: user, feed: feed} do
      [newest | _] = Feeds.list_newsfeed_items([feed.id], user_id: user.id)
      Feeds.mark_read(user.id, newest.id)
      Feeds.mark_read(user.id, newest.id)

      assert Feeds.unread_count(user.id, [feed.id]) == 1

      read_item =
        Enum.find(Feeds.list_newsfeed_items([feed.id], user_id: user.id), &(&1.id == newest.id))

      assert read_item.read
    end

    test "mark_all_read clears the whole feed set", %{user: user, feed: feed} do
      Feeds.mark_all_read(user.id, [feed.id])
      assert Feeds.unread_count(user.id, [feed.id]) == 0
      assert Feeds.unread_counts_by_feed(user.id, [feed.id]) == %{}
    end

    test "read state is per-user", %{user: user, feed: feed} do
      other = user_fixture()
      Feeds.mark_all_read(user.id, [feed.id])
      assert Feeds.unread_count(other.id, [feed.id]) == 2
    end
  end

  describe "due_feeds/2" do
    test "returns active feeds whose next fetch is due" do
      {:ok, due} = Feeds.upsert_feed_by_url("https://ex.com/due.xml")

      {:ok, not_due} = Feeds.upsert_feed_by_url("https://ex.com/later.xml")

      {:ok, _} =
        Feeds.update_feed(not_due, %{next_fetch_at: DateTime.add(DateTime.utc_now(), 3600)})

      {:ok, paused} = Feeds.upsert_feed_by_url("https://ex.com/paused.xml")
      {:ok, _} = Feeds.update_feed(paused, %{status: "paused"})

      ids = Feeds.due_feeds() |> Enum.map(& &1.id)
      assert due.id in ids
      refute not_due.id in ids
      refute paused.id in ids
    end
  end
end
