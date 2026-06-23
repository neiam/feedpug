defmodule FeedPug.Feeds do
  @moduledoc """
  The Feeds context: canonical, globally-shared feeds and their items.

  Feeds are deduped by URL and items by `{feed_id, guid}`, so a feed referenced
  by many groups is still fetched and stored exactly once.
  """
  import Ecto.Query, warn: false

  alias FeedPug.Repo
  alias FeedPug.Feeds.{Feed, Item, ItemRead}

  @topic "feeds"

  @doc "PubSub topic for new items on a given feed."
  def feed_topic(feed_id), do: "#{@topic}:#{feed_id}"

  ## Feeds

  def get_feed!(id), do: Repo.get!(Feed, id)

  def get_feed(id), do: Repo.get(Feed, id)

  def get_item!(id), do: Item |> Repo.get!(id) |> Repo.preload(:feed)

  @doc "Fetches an item with the feed preloaded and the `read` flag set for the user."
  def get_user_item!(user_id, id) do
    from(i in Item,
      where: i.id == ^id,
      left_join: r in ItemRead,
      on: r.item_id == i.id and r.user_id == ^user_id,
      preload: [:feed],
      select_merge: %{read: not is_nil(r.id)}
    )
    |> Repo.one!()
  end

  def get_feed_by_url(url), do: Repo.get_by(Feed, url: url)

  @doc """
  Finds the canonical feed for `url`, creating a pending one (due immediately)
  if it does not exist yet. Idempotent under concurrent inserts.
  """
  def upsert_feed_by_url(url, attrs \\ %{}) do
    url = normalize_url(url)

    case get_feed_by_url(url) do
      %Feed{} = feed ->
        {:ok, feed}

      nil ->
        %Feed{}
        |> Feed.changeset(
          Map.merge(attrs, %{"url" => url, "next_fetch_at" => DateTime.utc_now()})
        )
        |> Repo.insert()
        |> case do
          {:ok, feed} -> {:ok, feed}
          # Lost a race: another process inserted the same URL first.
          {:error, _changeset} -> {:ok, get_feed_by_url(url)}
        end
    end
  end

  def update_feed(%Feed{} = feed, attrs) do
    feed |> Feed.changeset(attrs) |> Repo.update()
  end

  @doc "Feeds whose next fetch is due and that are still active."
  def due_feeds(now \\ DateTime.utc_now(), limit \\ 500) do
    from(f in Feed,
      where: f.status == "active",
      where: is_nil(f.next_fetch_at) or f.next_fetch_at <= ^now,
      order_by: [asc_nulls_first: f.next_fetch_at],
      limit: ^limit
    )
    |> Repo.all()
  end

  ## Items

  @doc """
  Bulk-upserts parsed items for a feed, deduping on `{feed_id, guid}`.

  Returns `{count_total, inserted_items}` where `inserted_items` are the rows
  that were newly inserted (used to drive live newsfeed updates).
  """
  def store_items(%Feed{id: feed_id}, entries) when is_list(entries) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      entries
      |> Enum.map(&normalize_entry(&1, feed_id, now))
      |> Enum.reject(&is_nil(&1.guid))
      |> Enum.uniq_by(& &1.guid)

    {_n, inserted} =
      Repo.insert_all(Item, rows,
        on_conflict: :nothing,
        conflict_target: [:feed_id, :guid],
        returning: true
      )

    {length(rows), inserted}
  end

  @doc """
  Time-ordered newsfeed items across a set of feed ids, newest first.

  Supports keyset pagination via `:before` = `{published_at, id}` of the last
  seen item. Returns `[]` for an empty feed set without hitting the DB.
  """
  def list_newsfeed_items(feed_ids, opts \\ [])
  def list_newsfeed_items([], _opts), do: []

  def list_newsfeed_items(feed_ids, opts) do
    limit = Keyword.get(opts, :limit, 50)

    query =
      from(i in Item,
        where: i.feed_id in ^feed_ids,
        order_by: [desc: i.sort_at, desc: i.id],
        limit: ^limit,
        preload: [:feed]
      )

    query =
      case Keyword.get(opts, :before) do
        {sort_at, id} ->
          from(i in query,
            where: i.sort_at < ^sort_at or (i.sort_at == ^sort_at and i.id < ^id)
          )

        nil ->
          query
      end

    query
    |> search(Keyword.get(opts, :query))
    |> apply_read_flag(Keyword.get(opts, :user_id), Keyword.get(opts, :unread_only, false))
    |> Repo.all()
  end

  @doc """
  Adds a full-text WHERE clause over the item search vector, if a query is given.

  Each word becomes a prefix term (`word:*`) AND-ed together, so partial words
  match — e.g. "holo" matches "holographic", "elix rel" matches "Elixir release".
  """
  def search(query, term) do
    case prefix_tsquery(term) do
      nil ->
        query

      tsquery ->
        from(i in query,
          where: fragment("search_vector @@ to_tsquery('english', ?)", ^tsquery)
        )
    end
  end

  # Builds a safe `to_tsquery` string from free text: split on non-alphanumerics
  # (so no tsquery operators can be injected), lower-case, suffix each word with
  # `:*` for prefix matching, and AND them together. Returns nil for blank input.
  defp prefix_tsquery(nil), do: nil

  defp prefix_tsquery(term) when is_binary(term) do
    term
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> case do
      [] -> nil
      words -> words |> Enum.map_join(" & ", &(&1 <> ":*"))
    end
  end

  # Annotates each item with the virtual `read` flag for the given user, and
  # optionally restricts the result to unread items only.
  defp apply_read_flag(query, nil, _unread_only), do: query

  defp apply_read_flag(query, user_id, unread_only) do
    joined =
      from(i in query,
        left_join: r in ItemRead,
        on: r.item_id == i.id and r.user_id == ^user_id,
        select_merge: %{read: not is_nil(r.id)}
      )

    if unread_only do
      from([_i, r] in joined, where: is_nil(r.id))
    else
      joined
    end
  end

  ## Read / unread state

  @doc "Marks a single item read for a user (idempotent)."
  def mark_read(user_id, item_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert_all(
      ItemRead,
      [%{id: UUIDv7.generate(), user_id: user_id, item_id: item_id, inserted_at: now}],
      on_conflict: :nothing,
      conflict_target: [:user_id, :item_id]
    )

    :ok
  end

  @doc "Marks a single item unread for a user (removes the read marker)."
  def mark_unread(user_id, item_id) do
    from(r in ItemRead, where: r.user_id == ^user_id and r.item_id == ^item_id)
    |> Repo.delete_all()

    :ok
  end

  @doc "Marks every currently-unread item across `feed_ids` read for a user."
  def mark_all_read(_user_id, []), do: :ok

  def mark_all_read(user_id, feed_ids) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # UUIDv7 ids are generated app-side, so build the rows in Elixir rather than
    # via a query-sourced insert_all (which couldn't fill the binary id).
    rows =
      from(i in Item,
        left_join: r in ItemRead,
        on: r.item_id == i.id and r.user_id == ^user_id,
        where: i.feed_id in ^feed_ids and is_nil(r.id),
        select: i.id
      )
      |> Repo.all()
      |> Enum.map(fn item_id ->
        %{id: UUIDv7.generate(), user_id: user_id, item_id: item_id, inserted_at: now}
      end)

    Repo.insert_all(ItemRead, rows, on_conflict: :nothing, conflict_target: [:user_id, :item_id])
    :ok
  end

  @doc "Total unread item count for a user across a feed set."
  def unread_count(_user_id, []), do: 0

  def unread_count(user_id, feed_ids) do
    from(i in Item,
      left_join: r in ItemRead,
      on: r.item_id == i.id and r.user_id == ^user_id,
      where: i.feed_id in ^feed_ids and is_nil(r.id),
      select: count(i.id)
    )
    |> Repo.one()
  end

  @doc "Unread counts keyed by feed id (only feeds with unread items appear)."
  def unread_counts_by_feed(_user_id, []), do: %{}

  def unread_counts_by_feed(user_id, feed_ids) do
    from(i in Item,
      left_join: r in ItemRead,
      on: r.item_id == i.id and r.user_id == ^user_id,
      where: i.feed_id in ^feed_ids and is_nil(r.id),
      group_by: i.feed_id,
      select: {i.feed_id, count(i.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  ## Helpers

  defp normalize_url(url), do: url |> to_string() |> String.trim()

  defp normalize_entry(entry, feed_id, now) do
    published = truncate_second(Map.get(entry, :published_at))
    revised = truncate_second(Map.get(entry, :revised_at))
    available = Enum.reject([published, revised], &is_nil/1)

    %{
      id: UUIDv7.generate(),
      feed_id: feed_id,
      guid: entry |> Map.get(:guid) |> presence(),
      title: Map.get(entry, :title),
      url: Map.get(entry, :url),
      summary: Map.get(entry, :summary),
      content: Map.get(entry, :content),
      author: Map.get(entry, :author),
      published_at: published || revised || now,
      revised_at: revised,
      # Timeline sort key: the most recent date the feed gave us, else ingest time.
      sort_at: latest_date(available) || now,
      inserted_at: now,
      updated_at: now
    }
  end

  defp latest_date([]), do: nil
  defp latest_date(dates), do: Enum.max(dates, DateTime)

  defp truncate_second(nil), do: nil
  defp truncate_second(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(str), do: str
end
