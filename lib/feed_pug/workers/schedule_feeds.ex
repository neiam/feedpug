defmodule FeedPug.Workers.ScheduleFeeds do
  @moduledoc """
  Oban cron worker (runs every minute) that enqueues a `RefreshFeed` job for
  each feed whose next fetch is due.
  """
  use Oban.Worker, queue: :feeds, max_attempts: 1

  alias FeedPug.Feeds
  alias FeedPug.Workers.RefreshFeed

  @impl Oban.Worker
  def perform(_job) do
    Feeds.due_feeds()
    |> Enum.map(&RefreshFeed.new(%{feed_id: &1.id}))
    |> Oban.insert_all()

    :ok
  end
end
