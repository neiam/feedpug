defmodule FeedPugWeb.DiscoverLive do
  @moduledoc """
  Discover and follow other users' groups, and copy individual feeds from a
  followed group into one of your own groups.
  """
  use FeedPugWeb, :live_view

  alias FeedPug.Groups

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-2xl font-bold">Discover</h1>

      <section class="space-y-2">
        <h2 class="font-semibold opacity-70">Groups you can follow</h2>
        <p :if={@followable == []} class="text-sm opacity-50">
          No other users have shareable groups yet.
        </p>
        <ul class="divide-y divide-base-content/10">
          <li
            :for={group <- @followable}
            id={"followable-#{group.id}"}
            class="flex items-center justify-between py-3"
          >
            <div>
              <span class="font-medium">{group.name}</span>
              <span class="ml-2 text-xs opacity-50">by {group.user.email}</span>
            </div>
            <button
              :if={group.id not in @followed_ids}
              phx-click="follow"
              phx-value-id={group.id}
              class="btn btn-primary btn-xs"
            >
              Follow
            </button>
            <span :if={group.id in @followed_ids} class="badge badge-success badge-sm">
              following
            </span>
          </li>
        </ul>
      </section>

      <section :if={@follows != []} class="space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="font-semibold opacity-70">Following</h2>
          <form phx-change="set_copy_target" class="flex items-center gap-2 text-sm">
            <label for="copy_target">Copy feeds into</label>
            <select id="copy_target" name="copy_target" class="select select-bordered select-sm">
              <option
                :for={{label, id} <- group_options(@own_groups)}
                value={id}
                selected={id == @copy_target}
              >
                {label}
              </option>
            </select>
          </form>
        </div>

        <div
          :for={follow <- @follows}
          id={"follow-#{follow.id}"}
          class="rounded-lg border border-base-content/10 p-3"
        >
          <div class="flex items-center justify-between">
            <span class="font-medium">
              {follow.group.name} <span class="text-xs opacity-50">by {follow.group.user.email}</span>
            </span>
            <button
              phx-click="unfollow"
              phx-value-id={follow.id}
              class="btn btn-ghost btn-xs text-error"
            >
              Unfollow
            </button>
          </div>
          <ul class="mt-2 space-y-1">
            <li
              :for={gf <- @feeds_by_follow[follow.id] || []}
              class="flex items-center justify-between text-sm"
            >
              <div class="flex min-w-0 items-center gap-2">
                <.favicon feed={gf.feed} />
                <span class="truncate">{gf.feed.title || gf.feed.url}</span>
              </div>
              <button
                phx-click="copy_feed"
                phx-value-feed-id={gf.feed_id}
                class="btn btn-ghost btn-xs"
                disabled={is_nil(@copy_target)}
              >
                copy to mine
              </button>
            </li>
          </ul>

          <div
            :if={(@subgroups_by_follow[follow.id] || []) != []}
            class="mt-3 border-t border-base-content/10 pt-2"
          >
            <p class="mb-1 text-xs opacity-50">Subgroups — click to hide from your newsfeed</p>
            <div class="flex flex-wrap gap-1">
              <button
                :for={sub <- @subgroups_by_follow[follow.id]}
                phx-click="toggle_exclusion"
                phx-value-follow-id={follow.id}
                phx-value-group-id={sub.id}
                class={[
                  "btn btn-xs",
                  if(excluded?(@exclusion_by_group, sub.id),
                    do: "btn-ghost opacity-50 line-through",
                    else: "btn-outline"
                  )
                ]}
              >
                {display_path(sub)}
              </button>
            </div>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("follow", %{"id" => id}, socket) do
    group = Groups.get_group(id)

    case Groups.follow_group(socket.assigns.current_scope, group) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Now following #{group.name}") |> load()}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Couldn't follow that group")}
    end
  end

  def handle_event("unfollow", %{"id" => id}, socket) do
    follow = Enum.find(socket.assigns.follows, &(to_string(&1.id) == id))
    {:ok, _} = Groups.unfollow_group(socket.assigns.current_scope, follow)
    {:noreply, socket |> put_flash(:info, "Unfollowed") |> load()}
  end

  def handle_event("toggle_exclusion", %{"follow-id" => fid, "group-id" => gid}, socket) do
    scope = socket.assigns.current_scope

    case Map.get(socket.assigns.exclusion_by_group, gid) do
      nil ->
        follow = Enum.find(socket.assigns.follows, &(to_string(&1.id) == fid))
        Groups.add_exclusion(scope, follow, Groups.get_group(gid))

      exclusion ->
        Groups.remove_exclusion(scope, exclusion)
    end

    {:noreply, load(socket)}
  end

  def handle_event("set_copy_target", %{"copy_target" => target}, socket) do
    {:noreply, assign(socket, :copy_target, parse_id(target))}
  end

  def handle_event("copy_feed", %{"feed-id" => feed_id}, socket) do
    case socket.assigns.copy_target do
      nil ->
        {:noreply, put_flash(socket, :error, "Pick a target group first")}

      target_id ->
        group = Groups.get_group!(socket.assigns.current_scope, target_id)

        case Groups.copy_feed_to_group(socket.assigns.current_scope, group, feed_id) do
          {:ok, _} ->
            {:noreply, put_flash(socket, :info, "Copied into #{display_path(group)}")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Already in that group")}
        end
    end
  end

  ## Helpers

  defp load(socket) do
    scope = socket.assigns.current_scope
    follows = Groups.list_follows(scope)
    own_groups = Groups.list_groups(scope)

    socket
    |> assign(:followable, Groups.list_followable_groups(scope))
    |> assign(:follows, follows)
    |> assign(:followed_ids, Enum.map(follows, & &1.group_id))
    |> assign(:own_groups, own_groups)
    |> assign(:feeds_by_follow, Map.new(follows, &{&1.id, Groups.list_subtree_feeds(&1.group)}))
    |> assign(
      :subgroups_by_follow,
      Map.new(follows, &{&1.id, Groups.list_descendant_groups(&1.group)})
    )
    |> assign(:exclusion_by_group, exclusion_index(follows))
    |> assign_new(:copy_target, fn -> own_groups |> List.first() |> id_or_nil() end)
  end

  # excluded_group_id => the FollowExclusion row, across all of the user's follows.
  defp exclusion_index(follows) do
    follows
    |> Enum.flat_map(& &1.exclusions)
    |> Map.new(&{&1.excluded_group_id, &1})
  end

  defp group_options(groups), do: Enum.map(groups, &{display_path(&1), &1.id})
  defp display_path(group), do: String.replace(group.path, ".", ":")

  defp excluded?(exclusion_by_group, group_id), do: Map.has_key?(exclusion_by_group, group_id)

  defp id_or_nil(nil), do: nil
  defp id_or_nil(%{id: id}), do: id

  defp parse_id(""), do: nil
  defp parse_id(str), do: str
end
