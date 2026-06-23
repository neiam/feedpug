defmodule FeedPugWeb.OpmlControllerTest do
  use FeedPugWeb.ConnCase, async: true

  alias FeedPug.Groups

  setup :register_and_log_in_user

  test "GET /opml/export downloads the user's subscriptions", %{conn: conn, scope: scope} do
    comics = Enum.find(Groups.list_groups(scope), &(&1.path == "comics"))
    {:ok, sub} = Groups.create_group(scope, %{"name" => "Sad"}, comics)
    {:ok, _} = Groups.add_feed_to_group(scope, comics, "https://ex.com/a.xml")
    {:ok, _} = Groups.add_feed_to_group(scope, sub, "https://ex.com/b.xml")

    conn = get(conn, ~p"/opml/export")
    body = response(conn, 200)

    assert get_resp_header(conn, "content-type") |> hd() =~ "x-opml"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "feedpug-subscriptions.opml"
    assert body =~ "<opml"
    assert body =~ ~s(text="comics")
    assert body =~ ~s(xmlUrl="https://ex.com/a.xml")
    assert body =~ ~s(xmlUrl="https://ex.com/b.xml")
  end

  test "requires authentication", %{} do
    conn = build_conn() |> get(~p"/opml/export")
    assert redirected_to(conn) =~ "/users/log-in"
  end
end
