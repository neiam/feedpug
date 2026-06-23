defmodule FeedPug.GroupsTest do
  use FeedPug.DataCase, async: true

  import FeedPug.AccountsFixtures

  alias FeedPug.{Feeds, Groups}
  alias FeedPug.Groups.Group

  defp scope, do: user_scope_fixture()

  defp group_by_path(scope, path) do
    Enum.find(Groups.list_groups(scope), &(&1.path == path))
  end

  describe "default groups" do
    test "registration seeds the four default root groups" do
      s = scope()
      paths = s |> Groups.list_groups() |> Enum.map(& &1.path) |> Enum.sort()
      assert paths == ["blogs", "comics", "news", "podcasts"]
      assert Enum.all?(Groups.list_groups(s), & &1.is_default)
    end
  end

  describe "create_group/3" do
    test "creates a subgroup with a dotted materialized path" do
      s = scope()
      comics = group_by_path(s, "comics")
      assert {:ok, %Group{} = sad} = Groups.create_group(s, %{"name" => "Sad"}, comics)
      assert sad.path == "comics.sad"
      assert sad.slug == "sad"
      assert sad.parent_id == comics.id
    end

    test "slugifies names and disambiguates colliding sibling slugs" do
      s = scope()
      blogs = group_by_path(s, "blogs")
      {:ok, a} = Groups.create_group(s, %{"name" => "Tech News!"}, blogs)
      {:ok, b} = Groups.create_group(s, %{"name" => "Tech  News"}, blogs)
      assert a.slug == "tech-news"
      assert b.slug == "tech-news-2"
    end

    test "supports arbitrary depth" do
      s = scope()
      blogs = group_by_path(s, "blogs")
      {:ok, tech} = Groups.create_group(s, %{"name" => "tech"}, blogs)
      {:ok, erlang} = Groups.create_group(s, %{"name" => "erlang"}, tech)
      assert erlang.path == "blogs.tech.erlang"
    end
  end

  describe "rename_group/3" do
    test "rewrites the whole subtree's materialized path" do
      s = scope()
      comics = group_by_path(s, "comics")
      {:ok, _sad} = Groups.create_group(s, %{"name" => "sad"}, comics)
      {:ok, funny} = Groups.create_group(s, %{"name" => "funny"}, comics)
      {:ok, _deep} = Groups.create_group(s, %{"name" => "deep"}, funny)

      assert {:ok, renamed} = Groups.rename_group(s, comics, "Funnies")
      assert renamed.path == "funnies"

      paths = s |> Groups.list_groups() |> Enum.map(& &1.path) |> Enum.sort()
      assert "funnies" in paths
      assert "funnies.sad" in paths
      assert "funnies.funny" in paths
      assert "funnies.funny.deep" in paths
      refute Enum.any?(paths, &String.starts_with?(&1, "comics"))
    end
  end

  describe "delete_group/2" do
    test "refuses to delete a default group" do
      s = scope()
      assert {:error, :default_group} = Groups.delete_group(s, group_by_path(s, "blogs"))
    end

    test "deletes a subgroup and its descendants" do
      s = scope()
      comics = group_by_path(s, "comics")
      {:ok, sad} = Groups.create_group(s, %{"name" => "sad"}, comics)
      assert {:ok, _} = Groups.delete_group(s, sad)
      refute group_by_path(s, "comics.sad")
    end
  end

  describe "ownership enforcement" do
    test "cannot mutate another user's group" do
      owner = scope()
      other = scope()
      comics = group_by_path(owner, "comics")

      assert_raise FeedPug.Groups.NotOwnerError, fn ->
        Groups.create_group(other, %{"name" => "x"}, comics)
      end
    end
  end

  describe "following" do
    test "cannot follow your own group" do
      s = scope()

      assert {:error, :cannot_follow_own_group} =
               Groups.follow_group(s, group_by_path(s, "blogs"))
    end

    test "follow resolves the whole subtree into effective feeds" do
      bob = scope()
      alice = scope()
      comics = group_by_path(bob, "comics")
      {:ok, sad} = Groups.create_group(bob, %{"name" => "sad"}, comics)

      {:ok, gf_root} = Groups.add_feed_to_group(bob, comics, "https://ex.com/a.xml")
      {:ok, gf_sad} = Groups.add_feed_to_group(bob, sad, "https://ex.com/b.xml")

      {:ok, _follow} = Groups.follow_group(alice, comics)

      assert Enum.sort(Groups.effective_feed_ids(alice)) ==
               Enum.sort([gf_root.feed_id, gf_sad.feed_id])
    end

    test "exclusions remove an excluded subtree from the newsfeed" do
      bob = scope()
      alice = scope()
      comics = group_by_path(bob, "comics")
      {:ok, sad} = Groups.create_group(bob, %{"name" => "sad"}, comics)
      {:ok, gf_root} = Groups.add_feed_to_group(bob, comics, "https://ex.com/a.xml")
      {:ok, _gf_sad} = Groups.add_feed_to_group(bob, sad, "https://ex.com/b.xml")

      {:ok, follow} = Groups.follow_group(alice, comics)
      sad = Groups.get_group(sad.id)
      assert {:ok, _} = Groups.add_exclusion(alice, follow, sad)

      assert Groups.effective_feed_ids(alice) == [gf_root.feed_id]
    end

    test "cannot exclude a group outside the followed subtree" do
      bob = scope()
      alice = scope()
      comics = group_by_path(bob, "comics")
      news = group_by_path(bob, "news")
      {:ok, follow} = Groups.follow_group(alice, comics)

      assert {:error, :not_a_descendant} = Groups.add_exclusion(alice, follow, news)
    end
  end

  describe "import_opml/3" do
    test "creates nested subgroups and feeds under a target group" do
      s = scope()
      blogs = group_by_path(s, "blogs")

      {:ok, nodes} =
        FeedPug.Opml.parse("""
        <opml version="2.0"><body>
          <outline text="Comics">
            <outline text="Sad">
              <outline type="rss" text="Sad" xmlUrl="https://ex.com/sad.xml"/>
            </outline>
            <outline type="rss" text="Funny" xmlUrl="https://ex.com/funny.xml"/>
          </outline>
          <outline type="rss" text="Top" xmlUrl="https://ex.com/top.xml"/>
        </body></opml>
        """)

      assert {2, 3} = Groups.import_opml(s, nodes, blogs)

      paths = s |> Groups.list_groups() |> Enum.map(& &1.path)
      assert "blogs.comics" in paths
      assert "blogs.comics.sad" in paths

      # Top-level feed lands in the target group; nested feeds in their folders.
      assert ["https://ex.com/top.xml"] =
               blogs |> Groups.list_group_feeds() |> Enum.map(& &1.feed.url)
    end

    test "imports into :root, creating top-level groups and an Imported catch-all" do
      s = scope()

      {:ok, nodes} =
        FeedPug.Opml.parse("""
        <opml><body>
          <outline text="Tech">
            <outline type="rss" text="Erlang" xmlUrl="https://ex.com/erlang.xml"/>
          </outline>
          <outline type="rss" text="Loose" xmlUrl="https://ex.com/loose.xml"/>
        </body></opml>
        """)

      assert {2, 2} = Groups.import_opml(s, nodes, :root)

      paths = s |> Groups.list_groups() |> Enum.map(& &1.path)
      # New root group from the folder, plus the catch-all for the loose feed.
      assert "tech" in paths
      assert "tech.erlang" not in paths
      assert "imported" in paths

      tech = group_by_path(s, "tech")

      assert ["https://ex.com/erlang.xml"] =
               tech |> Groups.list_group_feeds() |> Enum.map(& &1.feed.url)
    end

    test "is idempotent across re-imports (reuses subgroups, skips dup feeds)" do
      s = scope()
      blogs = group_by_path(s, "blogs")

      {:ok, nodes} =
        FeedPug.Opml.parse("""
        <opml><body><outline text="Tech">
          <outline type="rss" text="A" xmlUrl="https://ex.com/a.xml"/>
        </outline></body></opml>
        """)

      assert {1, 1} = Groups.import_opml(s, nodes, blogs)
      # Second import: subgroup reused (0 created), feed already present (0 added).
      assert {0, 0} = Groups.import_opml(s, nodes, blogs)
    end
  end

  describe "list_newsfeed_sources/1" do
    test "lists own roots (subtree feeds) and follows (minus exclusions)" do
      bob = scope()
      alice = scope()
      comics = group_by_path(bob, "comics")
      {:ok, sad} = Groups.create_group(bob, %{"name" => "sad"}, comics)
      {:ok, root_gf} = Groups.add_feed_to_group(bob, comics, "https://ex.com/a.xml")
      {:ok, sad_gf} = Groups.add_feed_to_group(bob, sad, "https://ex.com/b.xml")

      comics_source = Enum.find(Groups.list_newsfeed_sources(bob), &(&1.label == "comics"))
      assert comics_source.kind == :own
      assert Enum.sort(comics_source.feed_ids) == Enum.sort([root_gf.feed_id, sad_gf.feed_id])

      {:ok, follow} = Groups.follow_group(alice, comics)
      followed = Enum.find(Groups.list_newsfeed_sources(alice), &(&1.kind == :follow))
      assert followed.label == "comics"
      assert Enum.sort(followed.feed_ids) == Enum.sort([root_gf.feed_id, sad_gf.feed_id])

      # Exclusions are reflected in the followed source's feeds.
      sad = Groups.get_group(sad.id)
      {:ok, _} = Groups.add_exclusion(alice, follow, sad)
      followed = Enum.find(Groups.list_newsfeed_sources(alice), &(&1.kind == :follow))
      assert followed.feed_ids == [root_gf.feed_id]
    end
  end

  describe "copy_feed_to_group/4" do
    test "pins an existing feed into the user's own group without duplicating it" do
      bob = scope()
      alice = scope()

      {:ok, gf} =
        Groups.add_feed_to_group(bob, group_by_path(bob, "comics"), "https://ex.com/c.xml")

      alice_blogs = group_by_path(alice, "blogs")
      assert {:ok, copied} = Groups.copy_feed_to_group(alice, alice_blogs, gf.feed_id)
      # Same canonical feed, new membership edge.
      assert copied.feed_id == gf.feed_id
      assert gf.feed_id in Groups.effective_feed_ids(alice)
      assert Feeds.get_feed!(gf.feed_id)
    end
  end
end
