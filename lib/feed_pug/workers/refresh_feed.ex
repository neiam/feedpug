defmodule FeedPug.Workers.RefreshFeed do
  @moduledoc """
  Oban worker that refreshes a single feed. Uniqueness prevents piling up
  duplicate jobs for the same feed while one is pending/executing.
  """
  use Oban.Worker,
    queue: :feeds,
    max_attempts: 3,
    unique: [keys: [:feed_id], states: Oban.Job.states() -- [:completed, :discarded, :cancelled]]

  alias FeedPug.Feeds
  alias FeedPug.Feeds.Fetcher

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"feed_id" => feed_id}}) do
    case Feeds.get_feed(feed_id) do
      nil -> :ok
      feed -> handle(Fetcher.refresh(feed))
    end
  end

  # A fetch failure is already recorded on the feed (with backoff); don't fail
  # the Oban job for an expected upstream error.
  defp handle({:error, _reason}), do: :ok
  defp handle(_), do: :ok
end
