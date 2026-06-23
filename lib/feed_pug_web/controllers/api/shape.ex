defmodule FeedPugWeb.Api.Shape do
  @moduledoc "Shapes domain structs into plain maps for JSON API responses."

  def item(item) do
    %{
      id: item.id,
      title: item.title,
      url: item.url,
      summary: item.summary,
      author: item.author,
      published_at: item.published_at,
      revised_at: item.revised_at,
      sort_at: item.sort_at,
      read: item.read || false,
      reactions: item.reactions || [],
      feed: feed(item.feed)
    }
  end

  def item_full(item) do
    item |> item() |> Map.put(:content, item.content)
  end

  def feed(%Ecto.Association.NotLoaded{}), do: nil

  def feed(feed) do
    %{id: feed.id, title: feed.title, url: feed.url, site_url: feed.site_url, status: feed.status}
  end

  def source(source) do
    %{
      key: source.key,
      label: source.label,
      kind: source.kind,
      feed_count: length(source.feed_ids)
    }
  end

  def reaction(reaction) do
    %{id: reaction.id, emoji: reaction.emoji, label: reaction.label, position: reaction.position}
  end

  def group(group) do
    %{
      id: group.id,
      name: group.name,
      path: group.path,
      display_path: String.replace(group.path, ".", ":"),
      parent_id: group.parent_id,
      is_default: group.is_default
    }
  end

  def group_feed(group_feed) do
    %{id: group_feed.id, custom_title: group_feed.custom_title, feed: feed(group_feed.feed)}
  end

  def slice(slice) do
    %{
      id: slice.id,
      name: slice.name,
      source_keys: slice.source_keys,
      unread_only: slice.unread_only,
      reaction_emoji: slice.reaction_emoji
    }
  end

  def follow(follow) do
    %{
      id: follow.id,
      group: group(follow.group),
      owner_email: follow.group.user.email,
      excluded_group_ids: Enum.map(follow.exclusions, & &1.excluded_group_id)
    }
  end
end
