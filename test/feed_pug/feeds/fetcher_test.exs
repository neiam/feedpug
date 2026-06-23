defmodule FeedPug.Feeds.FetcherTest do
  use FeedPug.DataCase, async: true

  alias FeedPug.Feeds
  alias FeedPug.Feeds.Fetcher

  @rss """
  <?xml version="1.0"?>
  <rss version="2.0"><channel>
  <title>Comics Daily</title><link>https://ex.com</link><description>d</description>
  <item><title>First</title><link>https://ex.com/1</link><guid>https://ex.com/1</guid>
  <pubDate>Wed, 02 Oct 2002 13:00:00 GMT</pubDate></item>
  </channel></rss>
  """

  defp stub, do: [plug: {Req.Test, __MODULE__}]

  test "fetches, parses, stores items, and updates feed metadata" do
    {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")

    Req.Test.stub(__MODULE__, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("etag", "abc123")
      |> Req.Test.text(@rss)
    end)

    assert {:ok, inserted} = Fetcher.refresh(feed, stub())
    assert length(inserted) == 1

    feed = Feeds.get_feed!(feed.id)
    assert feed.title == "Comics Daily"
    assert feed.etag == "abc123"
    assert feed.failure_count == 0
    assert feed.next_fetch_at
  end

  test "a 304 Not Modified bumps the schedule without new items" do
    {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 304, "") end)

    assert {:ok, :not_modified} = Fetcher.refresh(feed, stub())
    assert Feeds.get_feed!(feed.id).failure_count == 0
  end

  test "a transport error records a failure and backs off" do
    {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

    assert {:error, _reason} = Fetcher.refresh(feed, stub())
    assert Feeds.get_feed!(feed.id).failure_count == 1
  end

  test "parse_datetime handles ISO-8601 and RFC-822" do
    assert %DateTime{} = Fetcher.parse_datetime("2024-01-02T03:04:05Z")

    assert %DateTime{year: 2002, month: 10, day: 2} =
             Fetcher.parse_datetime("Wed, 02 Oct 2002 13:00:00 GMT")

    assert Fetcher.parse_datetime(nil) == nil
  end
end
