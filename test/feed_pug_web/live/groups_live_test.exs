defmodule FeedPugWeb.GroupsLiveTest do
  use FeedPugWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias FeedPug.Groups

  setup :register_and_log_in_user

  defp comics(scope), do: Enum.find(Groups.list_groups(scope), &(&1.path == "comics"))

  test "shows the default groups", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/groups")
    assert has_element?(lv, "#group-#{comics(scope).id}")
    assert render(lv) =~ "Your Groups"
  end

  test "creates a subgroup", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/groups")

    lv
    |> form("#subgroup-form", subgroup: %{parent_id: comics(scope).id, name: "Sad"})
    |> render_submit()

    sad = Enum.find(Groups.list_groups(scope), &(&1.path == "comics.sad"))
    assert sad
    assert has_element?(lv, "#group-#{sad.id}")
  end

  test "adds a feed to a group", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/groups")

    lv
    |> form("#feed-form", feed: %{group_id: comics(scope).id, url: "https://ex.com/x.xml"})
    |> render_submit()

    [gf] = Groups.list_group_feeds(comics(scope))
    assert gf.feed.url == "https://ex.com/x.xml"
    assert has_element?(lv, "#group-feed-#{gf.id}")
  end

  test "imports an OPML file into a target group", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/groups")
    blogs = Enum.find(Groups.list_groups(scope), &(&1.path == "blogs"))

    opml = """
    <opml version="2.0"><body>
      <outline text="Tech">
        <outline type="rss" text="Erlang" xmlUrl="https://ex.com/erlang.xml"/>
      </outline>
    </body></opml>
    """

    upload =
      file_input(lv, "#opml-form", :opml, [
        %{name: "subs.opml", content: opml, type: "text/x-opml"}
      ])

    render_upload(upload, "subs.opml")

    lv |> form("#opml-form", opml: %{target_id: blogs.id}) |> render_submit()

    paths = Enum.map(Groups.list_groups(scope), & &1.path)
    assert "blogs.tech" in paths

    tech = Enum.find(Groups.list_groups(scope), &(&1.path == "blogs.tech"))

    assert ["https://ex.com/erlang.xml"] =
             tech |> Groups.list_group_feeds() |> Enum.map(& &1.feed.url)
  end
end
