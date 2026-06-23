defmodule FeedPugWeb.Api.ApiControllerTest do
  use FeedPugWeb.ConnCase, async: true

  import FeedPug.AccountsFixtures

  alias FeedPug.{Accounts, Feeds, Groups}

  setup %{conn: conn} do
    scope = user_scope_fixture()
    {:ok, token} = Accounts.create_api_token(scope, label: "test")

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token.token}")

    %{conn: conn, scope: scope, user: scope.user}
  end

  defp comics(scope), do: Enum.find(Groups.list_groups(scope), &(&1.path == "comics"))

  defp seed_item(scope, title) do
    {:ok, gf} = Groups.add_feed_to_group(scope, comics(scope), "https://ex.com/#{title}.xml")
    feed = Feeds.get_feed!(gf.feed_id)

    {_n, [item]} =
      Feeds.store_items(feed, [
        %{
          guid: title,
          title: title,
          content: "<p>#{title} body</p>",
          published_at: ~U[2024-01-01 00:00:00Z]
        }
      ])

    {feed, item}
  end

  describe "authentication" do
    test "rejects requests without a token" do
      conn = build_conn() |> put_req_header("accept", "application/json")
      conn = get(conn, ~p"/api/profile")
      assert json_response(conn, 401)["error"] == "unauthorized"
    end

    test "rejects an unknown token" do
      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer fp_bogus")

      assert json_response(get(conn, ~p"/api/profile"), 401)
    end
  end

  test "GET /api/profile", %{conn: conn, user: user} do
    assert json_response(get(conn, ~p"/api/profile"), 200)["user"]["email"] == user.email
  end

  test "GET /api/timeline returns items from the user's groups", %{conn: conn, scope: scope} do
    {_feed, item} = seed_item(scope, "hello")
    body = json_response(get(conn, ~p"/api/timeline"), 200)
    assert Enum.any?(body["items"], &(&1["id"] == item.id and &1["title"] == "hello"))
  end

  test "GET /api/timeline?q= searches entry text", %{conn: conn, scope: scope} do
    seed_item(scope, "elixir")
    seed_item(scope, "kitten")

    titles =
      json_response(get(conn, ~p"/api/timeline?q=elixir"), 200)["items"]
      |> Enum.map(& &1["title"])

    assert "elixir" in titles
    refute "kitten" in titles
  end

  test "GET /api/items/:id returns full content", %{conn: conn, scope: scope} do
    {_feed, item} = seed_item(scope, "story")
    body = json_response(get(conn, ~p"/api/items/#{item.id}"), 200)
    assert body["item"]["content"] =~ "story body"
  end

  test "POST /api/items/:id/read marks read", %{conn: conn, scope: scope} do
    {feed, item} = seed_item(scope, "readme")
    assert json_response(post(conn, ~p"/api/items/#{item.id}/read"), 200)["ok"]
    assert Feeds.unread_count(scope.user.id, [feed.id]) == 0
  end

  test "POST /api/items/:id/unread clears the read marker", %{conn: conn, scope: scope} do
    {feed, item} = seed_item(scope, "unread")
    Feeds.mark_read(scope.user.id, item.id)
    assert Feeds.unread_count(scope.user.id, [feed.id]) == 0

    assert json_response(post(conn, ~p"/api/items/#{item.id}/unread"), 200)["ok"]
    assert Feeds.unread_count(scope.user.id, [feed.id]) == 1
  end

  test "POST /api/items/:id/reactions toggles a reaction", %{conn: conn, scope: scope} do
    {_feed, item} = seed_item(scope, "save")
    body = json_response(post(conn, ~p"/api/items/#{item.id}/reactions", %{emoji: "⭐"}), 200)
    assert body["state"] == "on"
    assert body["reactions"] == ["⭐"]
  end

  test "GET /api/slices returns saved views", %{conn: conn, scope: scope} do
    {:ok, _} =
      FeedPug.Timelines.create_slice(scope, %{
        name: "Unread comics",
        source_keys: ["group:#{comics(scope).id}"],
        unread_only: true,
        reaction_emoji: nil
      })

    slices = json_response(get(conn, ~p"/api/slices"), 200)["slices"]
    assert [%{"name" => "Unread comics", "unread_only" => true}] = slices
  end

  test "GET /api/sources and /api/reactions", %{conn: conn} do
    sources = json_response(get(conn, ~p"/api/sources"), 200)["sources"]
    assert Enum.any?(sources, &(&1["label"] == "comics" and &1["kind"] == "own"))

    reactions = json_response(get(conn, ~p"/api/reactions"), 200)["reactions"]
    assert Enum.map(reactions, & &1["emoji"]) == ["⭐", "❤️", "❗"]
  end

  test "create a group and add a feed via the API", %{conn: conn, scope: scope} do
    parent = comics(scope)

    created =
      json_response(post(conn, ~p"/api/groups", %{name: "Sad", parent_id: parent.id}), 201)

    assert created["group"]["display_path"] == "comics:sad"
    sub_id = created["group"]["id"]

    added =
      json_response(
        post(conn, ~p"/api/groups/#{sub_id}/feeds", %{url: "https://ex.com/x.xml"}),
        201
      )

    assert added["group_feed"]["feed"]["url"] == "https://ex.com/x.xml"
  end

  test "discover and follow another user's group", %{conn: conn, scope: scope} do
    bob = user_scope_fixture()
    bob_comics = Enum.find(Groups.list_groups(bob), &(&1.path == "comics"))

    discoverable = json_response(get(conn, ~p"/api/discover"), 200)["groups"]
    assert Enum.any?(discoverable, &(&1["id"] == bob_comics.id))

    follow =
      json_response(post(conn, ~p"/api/follows", %{group_id: bob_comics.id}), 201)["follow"]

    assert follow["group"]["id"] == bob_comics.id
    assert bob_comics.id in Enum.map(Groups.list_follows(scope), & &1.group_id)
  end
end
