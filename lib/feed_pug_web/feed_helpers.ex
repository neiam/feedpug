defmodule FeedPugWeb.FeedHelpers do
  @moduledoc """
  View helpers for rendering feeds: favicons, fetch-health badges, and relative
  timestamps. Imported app-wide via `feed_pug_web.ex`.
  """
  use Phoenix.Component

  import FeedPugWeb.CoreComponents, only: [icon: 1]

  @doc """
  A feed's favicon, sourced from DuckDuckGo's icon service keyed on the feed's
  host. Falls back to a generic icon if the host can't be determined or the
  image fails to load.
  """
  attr :feed, :map, required: true
  attr :class, :string, default: "size-4 rounded-sm"

  def favicon(assigns) do
    assigns = assign(assigns, :host, feed_host(assigns.feed))

    ~H"""
    <img
      :if={@host}
      src={"https://icons.duckduckgo.com/ip3/#{@host}.ico"}
      alt=""
      loading="lazy"
      class={["shrink-0 object-contain", @class]}
      onerror="this.style.visibility='hidden'"
    />
    """
  end

  @doc "Health badge for a feed: failing / paused / fresh fetch time."
  attr :feed, :map, required: true

  def feed_health(assigns) do
    ~H"""
    <%= cond do %>
      <% @feed.status == "failed" -> %>
        <span class="badge badge-error badge-sm gap-1">
          <.icon name="hero-exclamation-triangle-micro" class="size-3" /> failing
        </span>
      <% @feed.status == "paused" -> %>
        <span class="badge badge-ghost badge-sm">paused</span>
      <% @feed.failure_count > 0 -> %>
        <span class="badge badge-warning badge-sm">retrying</span>
      <% true -> %>
        <span class="text-xs opacity-50">updated {relative_time(@feed.last_fetched_at)}</span>
    <% end %>
    """
  end

  @doc """
  Best-effort sanitization of an item's HTML body for display in the reading
  pane. Strips script/style/embedding tags, inline event handlers, and
  `javascript:` URLs.

  This is a conservative filter, not a hardened sanitizer — for production-grade
  safety, swap in `html_sanitize_ex`.
  """
  def content_html(item) do
    (item.content || item.summary || "")
    |> strip(~r/<script\b[^>]*>.*?<\/script>/is)
    |> strip(~r/<style\b[^>]*>.*?<\/style>/is)
    |> strip(
      ~r/<\/?(?:script|style|iframe|object|embed|form|input|button|link|meta|base)\b[^>]*>/i
    )
    |> strip(~r/\son\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/i)
    |> String.replace(~r/(href|src)\s*=\s*(['"]?)\s*javascript:[^'">\s]*/i, "\\1=\\2#")
  end

  defp strip(html, regex), do: String.replace(html, regex, "")

  @doc "Coarse relative time, e.g. \"5m ago\", \"3d ago\", \"never\"."
  def relative_time(nil), do: "never"

  def relative_time(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp feed_host(%{site_url: site_url, url: url}) do
    host = uri_host(site_url) || uri_host(url)
    host && String.replace_prefix(host, "www.", "")
  end

  defp uri_host(nil), do: nil

  defp uri_host(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) and host != "" -> host
      _ -> nil
    end
  end
end
