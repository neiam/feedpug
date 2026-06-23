defmodule FeedPug.Feeds.Fetcher do
  @moduledoc """
  Fetches and parses a single canonical feed.

  Uses conditional HTTP (ETag / Last-Modified) to avoid redundant downloads,
  parses RSS/Atom/JSON via `FastRSS`, stores new items, and maintains the feed's
  scheduling metadata (next fetch time, failure backoff).
  """
  require Logger

  alias FeedPug.Feeds
  alias FeedPug.Feeds.Feed

  @max_failures 6
  @min_interval 900
  @max_interval 86_400

  @doc """
  Refreshes `feed`. Returns `{:ok, inserted_items}`, `{:ok, :not_modified}`, or
  `{:error, reason}`. Always updates the feed's scheduling metadata.
  """
  def refresh(%Feed{} = feed, req_opts \\ []) do
    headers = conditional_headers(feed)

    opts =
      [headers: headers, redirect: true, max_retries: 0, decode_body: false]
      |> Keyword.merge(Application.get_env(:feed_pug, :req_options, []))
      |> Keyword.merge(req_opts)

    case Req.get(feed.url, opts) do
      {:ok, %{status: 304}} ->
        mark_success(feed, %{}, [])
        {:ok, :not_modified}

      {:ok, %{status: status, body: body} = resp} when status in 200..299 ->
        handle_body(feed, body, resp)

      {:ok, %{status: status}} ->
        mark_failure(feed, "http_status_#{status}")

      {:error, reason} ->
        mark_failure(feed, inspect(reason))
    end
  end

  defp handle_body(feed, body, resp) do
    case parse(body) do
      {:ok, parsed} ->
        entries = Enum.map(parsed_items(parsed), &normalize_entry/1)
        {_total, inserted} = Feeds.store_items(feed, entries)

        meta = %{
          "title" => first_present([feed.title, parsed["title"]]),
          "site_url" => first_present([parsed["link"], feed.site_url]),
          "description" => first_present([parsed["description"], feed.description]),
          "etag" => header(resp, "etag"),
          "last_modified" => header(resp, "last-modified")
        }

        mark_success(feed, meta, inserted)
        broadcast(feed, inserted)
        {:ok, inserted}

      {:error, reason} ->
        mark_failure(feed, "parse_error:#{inspect(reason)}")
    end
  end

  ## Parsing ------------------------------------------------------------------

  defp parse(body) do
    with {:error, _} <- FastRSS.parse_rss(body),
         {:error, _} <- FastRSS.parse_atom(body) do
      {:error, :unrecognized_feed}
    end
  end

  # Both the RSS and Atom maps from FastRSS expose entries under "items"/"entries".
  defp parsed_items(%{"items" => items}) when is_list(items), do: items
  defp parsed_items(%{"entries" => entries}) when is_list(entries), do: entries
  defp parsed_items(_), do: []

  defp normalize_entry(item) do
    %{
      guid: extract_guid(item),
      title: item["title"],
      url: extract_link(item),
      summary: item["description"] || item["summary"],
      content: extract_content(item),
      author: extract_author(item),
      published_at: parse_datetime(item["pub_date"] || item["published"] || item["date"]),
      revised_at: parse_datetime(item["updated"])
    }
  end

  defp extract_guid(item) do
    case item["guid"] || item["id"] do
      %{"value" => value} -> value
      value when is_binary(value) -> value
      _ -> extract_link(item) || item["title"]
    end
  end

  defp extract_link(item) do
    case item["link"] || item["links"] do
      link when is_binary(link) -> link
      [%{"href" => href} | _] -> href
      [link | _] when is_binary(link) -> link
      _ -> nil
    end
  end

  defp extract_content(item) do
    case item["content"] do
      %{"value" => value} -> value
      value when is_binary(value) -> value
      _ -> item["description"]
    end
  end

  defp extract_author(item) do
    case item["author"] || item["dublin_core"] do
      author when is_binary(author) -> author
      %{"creators" => [creator | _]} -> creator
      _ -> nil
    end
  end

  @doc false
  def parse_datetime(nil), do: nil

  def parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> parse_rfc822(str)
    end
  end

  # Minimal RFC-822/1123 parser, e.g. "Wed, 02 Oct 2002 13:00:00 GMT".
  defp parse_rfc822(str) do
    case Regex.run(~r/(\d{1,2})\s+(\w{3})\s+(\d{2,4})\s+(\d{2}):(\d{2})(?::(\d{2}))?/, str) do
      [_, d, mon, y, h, min | rest] ->
        with {:ok, month} <- month_number(mon) do
          year = String.to_integer(y) |> normalize_year()
          sec = rest |> List.first() |> to_int(0)

          case DateTime.new(
                 Date.new!(year, month, String.to_integer(d)),
                 Time.new!(String.to_integer(h), String.to_integer(min), sec)
               ) do
            {:ok, dt} -> dt
            _ -> nil
          end
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp normalize_year(y) when y < 100, do: 2000 + y
  defp normalize_year(y), do: y

  defp to_int(nil, default), do: default
  defp to_int("", default), do: default
  defp to_int(str, _default), do: String.to_integer(str)

  @months ~w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
  defp month_number(mon) do
    case Enum.find_index(@months, &(&1 == String.capitalize(mon))) do
      nil -> :error
      idx -> {:ok, idx + 1}
    end
  end

  ## Feed metadata updates ----------------------------------------------------

  defp mark_success(feed, meta, _inserted) do
    interval = clamp(feed.fetch_interval_seconds, @min_interval, @max_interval)
    now = DateTime.utc_now()

    attrs =
      meta
      |> drop_blank()
      |> Map.merge(%{
        "last_fetched_at" => now,
        "next_fetch_at" => DateTime.add(now, interval, :second),
        "failure_count" => 0,
        "status" => "active"
      })

    Feeds.update_feed(feed, attrs)
  end

  defp mark_failure(feed, reason) do
    Logger.warning("feed #{feed.id} fetch failed: #{reason}")
    failures = feed.failure_count + 1
    # Exponential backoff capped at @max_interval.
    backoff = min(@max_interval, @min_interval * round(:math.pow(2, min(failures, 5))))
    status = if failures >= @max_failures, do: "failed", else: "active"

    Feeds.update_feed(feed, %{
      "failure_count" => failures,
      "status" => status,
      "last_fetched_at" => DateTime.utc_now(),
      "next_fetch_at" => DateTime.add(DateTime.utc_now(), backoff, :second)
    })

    {:error, reason}
  end

  defp broadcast(_feed, []), do: :ok

  defp broadcast(feed, inserted) do
    Phoenix.PubSub.broadcast(
      FeedPug.PubSub,
      Feeds.feed_topic(feed.id),
      {:new_items, feed.id, inserted}
    )
  end

  ## Helpers ------------------------------------------------------------------

  defp conditional_headers(feed) do
    []
    |> maybe_header("if-none-match", feed.etag)
    |> maybe_header("if-modified-since", feed.last_modified)
  end

  defp maybe_header(headers, _key, nil), do: headers
  defp maybe_header(headers, _key, ""), do: headers
  defp maybe_header(headers, key, value), do: [{key, value} | headers]

  defp header(resp, key) do
    case Req.Response.get_header(resp, key) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp first_present(values), do: Enum.find(values, &present?/1)

  defp present?(nil), do: false
  defp present?(""), do: false
  defp present?(_), do: true

  defp drop_blank(map), do: for({k, v} <- map, present?(v), into: %{}, do: {k, v})

  defp clamp(nil, lo, _hi), do: lo
  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)
end
