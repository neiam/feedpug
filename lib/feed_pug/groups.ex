defmodule FeedPug.Groups do
  @moduledoc """
  The Groups context: user-owned hierarchical groups of feeds, cross-user
  follows, subgroup exclusions, and resolution of a user's effective newsfeed
  feed set.

  All write operations are scoped through `%FeedPug.Accounts.Scope{}`. The
  materialized `path` of a group is maintained exclusively here.
  """
  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias FeedPug.Repo
  alias FeedPug.Accounts.Scope
  alias FeedPug.Feeds
  alias FeedPug.Groups.{Group, GroupFeed, GroupFollow, FollowExclusion}

  @default_group_names ~w(blogs comics news podcasts)
  @path_separator "."

  ## PubSub -------------------------------------------------------------------

  @doc "PubSub topic carrying newsfeed-invalidation events for a user."
  def newsfeed_topic(user_id), do: "newsfeed:#{user_id}"

  defp broadcast_newsfeed_change(user_id) do
    Phoenix.PubSub.broadcast(FeedPug.PubSub, newsfeed_topic(user_id), :newsfeed_changed)
  end

  ## Default groups -----------------------------------------------------------

  @doc """
  Appends inserts for the default root groups onto an `Ecto.Multi`, reading the
  freshly-inserted user from the `:user` change so it runs in the registration
  transaction.
  """
  def seed_default_groups_multi(multi) do
    Enum.reduce(@default_group_names, multi, fn name, multi ->
      Multi.insert(multi, {:default_group, name}, fn %{user: user} ->
        slug = slugify(name)

        Group.placement_changeset(%Group{}, %{
          name: name,
          slug: slug,
          path: slug,
          user_id: user.id,
          is_default: true
        })
      end)
    end)
  end

  def default_group_names, do: @default_group_names

  ## Reading groups -----------------------------------------------------------

  @doc "All of the scoped user's own groups, ordered by path."
  def list_groups(%Scope{user: user}) do
    from(g in Group, where: g.user_id == ^user.id, order_by: [asc: g.path])
    |> Repo.all()
  end

  @doc "Fetch one of the scoped user's own groups."
  def get_group!(%Scope{user: user}, id) do
    Repo.get_by!(Group, id: id, user_id: user.id)
  end

  @doc "Fetch any group by id (used to follow another user's group)."
  def get_group(id), do: Repo.get(Group, id)

  @doc "Fetch a scoped user's child group by parent and name, if it exists."
  def get_subgroup(%Scope{user: user}, parent_id, name) do
    Repo.get_by(Group, user_id: user.id, parent_id: parent_id, name: name)
  end

  @doc "Feeds placed directly in a group, with the canonical feed preloaded."
  def list_group_feeds(%Group{id: group_id}) do
    from(gf in GroupFeed,
      where: gf.group_id == ^group_id,
      preload: [:feed],
      order_by: [asc: gf.id]
    )
    |> Repo.all()
  end

  @doc "Descendant subgroups of a group (excluding the group itself), by path."
  def list_descendant_groups(%Group{} = group) do
    prefix = group.path <> @path_separator <> "%"

    from(g in Group,
      where: g.user_id == ^group.user_id and like(g.path, ^prefix),
      order_by: [asc: g.path]
    )
    |> Repo.all()
  end

  @doc "All feeds in a group's whole subtree (the group and its descendants)."
  def list_subtree_feeds(%Group{} = group) do
    prefix = group.path <> @path_separator <> "%"

    from(gf in GroupFeed,
      join: g in Group,
      on: g.id == gf.group_id,
      where: g.user_id == ^group.user_id and (g.path == ^group.path or like(g.path, ^prefix)),
      preload: [:feed],
      order_by: [asc: g.path, asc: gf.id]
    )
    |> Repo.all()
  end

  ## Creating / mutating groups ----------------------------------------------

  @doc """
  Creates a subgroup under `parent` (or a root group when `parent` is nil) for
  the scoped user. Computes the slug and materialized path.
  """
  def create_group(%Scope{user: user}, attrs, parent \\ nil) do
    name = attrs |> Map.get("name", Map.get(attrs, :name)) |> to_string() |> String.trim()
    parent = parent && ensure_owned!(user, parent)
    slug = unique_sibling_slug(user.id, parent_id(parent), slugify(name))
    path = build_path(parent, slug)

    %Group{}
    |> Group.placement_changeset(%{
      name: name,
      slug: slug,
      path: path,
      parent_id: parent_id(parent),
      user_id: user.id
    })
    |> Repo.insert()
    |> tap_ok(fn _ -> broadcast_newsfeed_change(user.id) end)
  end

  @doc """
  Renames a group, rewriting the materialized path of the whole subtree in one
  transaction so `path` and `parent_id` can never disagree.
  """
  def rename_group(%Scope{user: user} = scope, %Group{} = group, new_name) do
    group = ensure_owned!(user, group)
    new_name = new_name |> to_string() |> String.trim()
    parent = group.parent_id && get_group!(scope, group.parent_id)
    new_slug = unique_sibling_slug(user.id, group.parent_id, slugify(new_name), group.id)
    new_path = build_path(parent, new_slug)

    Multi.new()
    |> Multi.update(
      :group,
      Group.placement_changeset(group, %{name: new_name, slug: new_slug, path: new_path})
    )
    |> rewrite_descendants(group.path, new_path)
    |> Repo.transaction()
    |> case do
      {:ok, %{group: updated}} ->
        broadcast_newsfeed_change(user.id)
        {:ok, updated}

      {:error, _step, changeset, _} ->
        {:error, changeset}
    end
  end

  @doc "Deletes a group (and, by FK cascade, its subtree, feeds, and follows)."
  def delete_group(%Scope{user: user}, %Group{} = group) do
    group = ensure_owned!(user, group)

    if group.is_default do
      {:error, :default_group}
    else
      group
      |> Repo.delete()
      |> tap_ok(fn _ -> broadcast_newsfeed_change(user.id) end)
    end
  end

  ## Feeds in groups ----------------------------------------------------------

  @doc """
  Adds a feed (by URL) to one of the scoped user's groups, creating the
  canonical feed if needed.
  """
  def add_feed_to_group(%Scope{user: user}, %Group{} = group, url, custom_title \\ nil) do
    group = ensure_owned!(user, group)

    with {:ok, feed} <- Feeds.upsert_feed_by_url(url) do
      place_feed(user, group, feed, custom_title)
    end
  end

  @doc """
  Copies an existing canonical feed into one of the scoped user's own groups
  (e.g. pinning a feed seen in a followed group). No feed/item duplication.
  """
  def copy_feed_to_group(%Scope{user: user}, %Group{} = group, feed_id, custom_title \\ nil) do
    group = ensure_owned!(user, group)
    feed = Feeds.get_feed!(feed_id)
    place_feed(user, group, feed, custom_title)
  end

  defp place_feed(_user, group, feed, custom_title) do
    %GroupFeed{}
    |> GroupFeed.changeset(%{group_id: group.id, feed_id: feed.id, custom_title: custom_title})
    |> Repo.insert()
    |> tap_ok(fn _ -> notify_followers_of_group_change(group) end)
  end

  @doc "Removes a feed membership from one of the scoped user's groups."
  def remove_feed_from_group(%Scope{user: user}, %GroupFeed{} = group_feed) do
    group = ensure_owned!(user, get_group(group_feed.group_id))

    group_feed
    |> Repo.delete()
    |> tap_ok(fn _ -> notify_followers_of_group_change(group) end)
  end

  ## OPML export ---------------------------------------------------------------

  @doc """
  Builds a nested OPML node tree (folders + feeds) of the scoped user's own
  groups, suitable for `FeedPug.Opml.export/2`. Mirrors the group hierarchy:
  subgroups become nested folder outlines, feeds become rss outlines.
  """
  def export_tree(%Scope{} = scope) do
    groups = list_groups(scope)
    feeds_by_group = Map.new(groups, fn g -> {g.id, list_group_feeds(g)} end)
    children_by_parent = Enum.group_by(groups, & &1.parent_id)
    build_export_nodes(Map.get(children_by_parent, nil, []), children_by_parent, feeds_by_group)
  end

  defp build_export_nodes(groups, children_by_parent, feeds_by_group) do
    Enum.map(groups, fn group ->
      subgroups =
        build_export_nodes(
          Map.get(children_by_parent, group.id, []),
          children_by_parent,
          feeds_by_group
        )

      feeds =
        feeds_by_group
        |> Map.get(group.id, [])
        |> Enum.map(fn gf ->
          %{
            type: :feed,
            title: gf.custom_title || gf.feed.title || gf.feed.url,
            xml_url: gf.feed.url,
            html_url: gf.feed.site_url
          }
        end)

      %{type: :group, name: group.name, children: subgroups ++ feeds}
    end)
  end

  ## OPML import ---------------------------------------------------------------

  @doc """
  Imports a parsed OPML node tree (see `FeedPug.Opml.parse/1`) into the scoped
  user's account.

  `target` is either a `%Group{}` (folders nest beneath it, feeds attach to it)
  or `:root` (the OPML's top-level folders become new root groups; loose
  top-level feeds land in an "Imported" root group). Existing same-named groups
  are reused, so re-imports are idempotent. Returns `{groups_created, feeds_added}`.
  """
  def import_opml(scope, nodes, target)

  def import_opml(%Scope{} = scope, nodes, %Group{} = target) when is_list(nodes) do
    import_into(scope, nodes, target)
  end

  def import_opml(%Scope{} = scope, nodes, :root) when is_list(nodes) do
    Enum.reduce(nodes, {0, 0}, fn
      %{type: :group, name: name, children: children}, {groups, feeds} ->
        {root, created} = ensure_group(scope, nil, name)
        {g2, f2} = import_into(scope, children, root)
        {groups + created + g2, feeds + f2}

      %{type: :feed} = node, {groups, feeds} ->
        # Loose top-level feeds have no folder — collect them in an "Imported" root.
        {root, created} = ensure_group(scope, nil, "Imported")
        {_g, f2} = import_into(scope, [node], root)
        {groups + created, feeds + f2}
    end)
  end

  defp import_into(scope, nodes, %Group{} = parent) do
    Enum.reduce(nodes, {0, 0}, fn
      %{type: :feed, xml_url: url, title: title}, {groups, feeds} ->
        case add_feed_to_group(scope, parent, url, title) do
          {:ok, _} -> {groups, feeds + 1}
          # Duplicate within the group — skip, don't abort the import.
          {:error, _} -> {groups, feeds}
        end

      %{type: :group, name: name, children: children}, {groups, feeds} ->
        {sub, created} = ensure_group(scope, parent, name)
        {g2, f2} = import_into(scope, children, sub)
        {groups + created + g2, feeds + f2}
    end)
  end

  # Creates a group under `parent` (or a root when nil), reusing an existing
  # same-named one on collision. Returns `{group, 1 | 0}`.
  defp ensure_group(%Scope{} = scope, parent, name) do
    case create_group(scope, %{"name" => name}, parent) do
      {:ok, group} -> {group, 1}
      {:error, _changeset} -> {get_subgroup(scope, parent && parent.id, name), 0}
    end
  end

  ## Following ----------------------------------------------------------------

  @doc "Groups owned by other users that the scoped user can browse/follow."
  def list_followable_groups(%Scope{user: user}) do
    from(g in Group,
      where: g.user_id != ^user.id and is_nil(g.parent_id),
      order_by: [asc: g.name],
      preload: [:user]
    )
    |> Repo.all()
  end

  def list_follows(%Scope{user: user}) do
    from(f in GroupFollow,
      where: f.follower_user_id == ^user.id,
      preload: [group: :user, exclusions: :excluded_group]
    )
    |> Repo.all()
  end

  @doc "Follows another user's group. Rejects following your own group."
  def follow_group(%Scope{user: user}, %Group{} = group) do
    cond do
      group.user_id == user.id ->
        {:error, :cannot_follow_own_group}

      true ->
        %GroupFollow{}
        |> GroupFollow.changeset(%{follower_user_id: user.id, group_id: group.id})
        |> Repo.insert()
        |> tap_ok(fn _ -> broadcast_newsfeed_change(user.id) end)
    end
  end

  def unfollow_group(%Scope{user: user}, %GroupFollow{} = follow) do
    true = follow.follower_user_id == user.id

    follow
    |> Repo.delete()
    |> tap_ok(fn _ -> broadcast_newsfeed_change(user.id) end)
  end

  @doc "Excludes a descendant subgroup from a follow."
  def add_exclusion(%Scope{user: user}, %GroupFollow{} = follow, %Group{} = excluded) do
    true = follow.follower_user_id == user.id

    if descendant?(follow.group_id, excluded) do
      %FollowExclusion{}
      |> FollowExclusion.changeset(%{group_follow_id: follow.id, excluded_group_id: excluded.id})
      |> Repo.insert()
      |> tap_ok(fn _ -> broadcast_newsfeed_change(user.id) end)
    else
      {:error, :not_a_descendant}
    end
  end

  def remove_exclusion(%Scope{user: user}, %FollowExclusion{} = exclusion) do
    exclusion = Repo.preload(exclusion, :group_follow)
    true = exclusion.group_follow.follower_user_id == user.id

    exclusion
    |> Repo.delete()
    |> tap_ok(fn _ -> broadcast_newsfeed_change(user.id) end)
  end

  ## Effective feed resolution ------------------------------------------------

  @doc """
  Resolves the set of feed ids feeding a user's newsfeed: feeds in their own
  groups, plus feeds in the descendants of every group they follow, minus
  excluded subtrees. Deduped.
  """
  def effective_feed_ids(%Scope{user: user}) do
    own_group_ids =
      from(g in Group, where: g.user_id == ^user.id, select: g.id) |> Repo.all()

    followed_group_ids = followed_group_ids(user)
    group_ids = Enum.uniq(own_group_ids ++ followed_group_ids)

    case group_ids do
      [] ->
        []

      ids ->
        from(gf in GroupFeed, where: gf.group_id in ^ids, select: gf.feed_id, distinct: true)
        |> Repo.all()
    end
  end

  @doc """
  The selectable "sources" feeding a user's newsfeed, for filtering: each of
  their own root groups and each group they follow, with the feed ids each
  contributes (own = subtree; followed = subtree minus exclusions).
  """
  def list_newsfeed_sources(%Scope{user: user}) do
    own =
      from(g in Group,
        where: g.user_id == ^user.id and is_nil(g.parent_id),
        order_by: [asc: g.name]
      )
      |> Repo.all()
      |> Enum.map(fn g ->
        %{key: "group:#{g.id}", label: g.name, kind: :own, feed_ids: subtree_feed_ids(g)}
      end)

    followed =
      from(f in GroupFollow,
        where: f.follower_user_id == ^user.id,
        preload: [group: :user, exclusions: :excluded_group]
      )
      |> Repo.all()
      |> Enum.map(fn f ->
        %{
          key: "follow:#{f.id}",
          label: f.group.name,
          kind: :follow,
          feed_ids: follow_feed_ids(f)
        }
      end)

    own ++ followed
  end

  defp subtree_feed_ids(%Group{} = group) do
    prefix = group.path <> @path_separator <> "%"

    ids =
      from(g in Group,
        where: g.user_id == ^group.user_id and (g.path == ^group.path or like(g.path, ^prefix)),
        select: g.id
      )
      |> Repo.all()

    feed_ids_in_groups(ids)
  end

  defp follow_feed_ids(%GroupFollow{} = follow) do
    case follow_condition(follow) do
      nil ->
        []

      condition ->
        ids = from(g in Group, where: ^condition, select: g.id) |> Repo.all()
        feed_ids_in_groups(ids)
    end
  end

  defp feed_ids_in_groups([]), do: []

  defp feed_ids_in_groups(group_ids) do
    from(gf in GroupFeed, where: gf.group_id in ^group_ids, select: gf.feed_id, distinct: true)
    |> Repo.all()
  end

  defp followed_group_ids(user) do
    follows =
      from(f in GroupFollow,
        where: f.follower_user_id == ^user.id,
        preload: [:group, exclusions: :excluded_group]
      )
      |> Repo.all()

    conditions =
      follows
      |> Enum.map(&follow_condition/1)
      |> Enum.reject(&is_nil/1)

    case conditions do
      [] ->
        []

      [first | rest] ->
        combined = Enum.reduce(rest, first, fn c, acc -> dynamic(^acc or ^c) end)
        from(g in Group, where: ^combined, select: g.id) |> Repo.all()
    end
  end

  # A follow contributes: root's subtree, minus each excluded subtree.
  defp follow_condition(%GroupFollow{group: %Group{} = root} = follow) do
    base = subtree_dynamic(root.user_id, root.path)

    case follow.exclusions do
      [] ->
        base

      exclusions ->
        excl =
          exclusions
          |> Enum.map(fn e ->
            subtree_dynamic(e.excluded_group.user_id, e.excluded_group.path)
          end)
          |> Enum.reduce(fn c, acc -> dynamic(^acc or ^c) end)

        dynamic(^base and not (^excl))
    end
  end

  defp follow_condition(_), do: nil

  # "group is at or below (user_id, path)" — a safe prefix match (slugs contain
  # no LIKE wildcards).
  defp subtree_dynamic(user_id, path) do
    prefix = path <> @path_separator <> "%"
    dynamic([g], g.user_id == ^user_id and (g.path == ^path or like(g.path, ^prefix)))
  end

  ## Path / slug maintenance --------------------------------------------------

  defp rewrite_descendants(multi, old_path, new_path) do
    old_prefix = old_path <> @path_separator
    new_prefix = new_path <> @path_separator
    like = old_prefix <> "%"
    # Replace the old path prefix with the new one for every descendant.
    cut = String.length(old_prefix)

    Multi.update_all(
      multi,
      :descendants,
      fn _ ->
        from(g in Group,
          where: like(g.path, ^like),
          update: [
            set: [
              path: fragment("? || substring(?, ?::integer)", ^new_prefix, g.path, ^(cut + 1))
            ]
          ]
        )
      end,
      []
    )
  end

  defp descendant?(ancestor_id, %Group{} = node) do
    case get_group(ancestor_id) do
      %Group{} = ancestor ->
        ancestor.user_id == node.user_id and
          (node.path == ancestor.path or
             String.starts_with?(node.path, ancestor.path <> @path_separator))

      _ ->
        false
    end
  end

  defp build_path(nil, slug), do: slug
  defp build_path(%Group{path: parent_path}, slug), do: parent_path <> @path_separator <> slug

  defp parent_id(nil), do: nil
  defp parent_id(%Group{id: id}), do: id

  defp unique_sibling_slug(user_id, parent_id, base, exclude_id \\ nil) do
    taken = sibling_slugs(user_id, parent_id, exclude_id)
    if base not in taken, do: base, else: next_free_slug(base, taken, 2)
  end

  defp next_free_slug(base, taken, n) do
    candidate = "#{base}-#{n}"
    if candidate in taken, do: next_free_slug(base, taken, n + 1), else: candidate
  end

  defp sibling_slugs(user_id, parent_id, exclude_id) do
    query =
      from(g in Group,
        where: g.user_id == ^user_id and g.slug != "",
        select: g.slug
      )

    query =
      if is_nil(parent_id) do
        from(g in query, where: is_nil(g.parent_id))
      else
        from(g in query, where: g.parent_id == ^parent_id)
      end

    query =
      if exclude_id, do: from(g in query, where: g.id != ^exclude_id), else: query

    Repo.all(query)
  end

  @doc "Slugifies a display name into `[a-z0-9-]` with single hyphen runs."
  def slugify(name) do
    slug =
      name
      |> to_string()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")

    if slug == "", do: "group", else: slug
  end

  ## Follower notification ----------------------------------------------------

  # Notify the owner plus everyone whose follow subtree contains `group`.
  defp notify_followers_of_group_change(%Group{} = group) do
    broadcast_newsfeed_change(group.user_id)

    follower_ids =
      from(f in GroupFollow,
        join: g in Group,
        on: g.id == f.group_id,
        where:
          g.user_id == ^group.user_id and
            (g.path == ^group.path or
               fragment("? LIKE ? || '.%'", ^group.path, g.path)),
        select: f.follower_user_id,
        distinct: true
      )
      |> Repo.all()

    Enum.each(follower_ids, &broadcast_newsfeed_change/1)
    :ok
  end

  ## Misc ---------------------------------------------------------------------

  defp ensure_owned!(user, %Group{user_id: uid} = group) when uid == user.id, do: group
  defp ensure_owned!(_user, %Group{}), do: raise(FeedPug.Groups.NotOwnerError)

  defp tap_ok({:ok, _} = res, fun), do: tap(res, fn _ -> fun.(res) end)
  defp tap_ok(other, _fun), do: other
end
