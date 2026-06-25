defmodule FeedPugWeb.NewsfeedLive do
  @moduledoc """
  The aggregated newsfeed as a master–detail reader: a left column of entry
  titles (newest first) and a right column showing the selected entry's content.
  New items from background polling and changes to the followed group set appear
  live. An "unread only" toggle filters the list.
  """
  use FeedPugWeb, :live_view

  alias FeedPug.{Feeds, Groups, Reactions, Timelines}

  @page_size 40

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    socket =
      socket
      |> assign(
        selected: nil,
        selected_id: nil,
        unread_only: false,
        reaction_filter: nil,
        feed_filter: nil,
        query: "",
        active_slice_id: nil,
        slices: Timelines.list_slices(scope),
        reactions: Reactions.ensure_default_reactions(scope)
      )
      |> load_feed_set()

    {:ok, load_first_page(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} wide>
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h1 class="text-2xl font-bold">Newsfeed</h1>
        <div class="flex items-center gap-3">
          <form phx-change="search" phx-submit="search">
            <input
              type="search"
              name="q"
              value={@query}
              placeholder="Search entries…"
              phx-debounce="300"
              autocomplete="off"
              class="input input-bordered input-sm w-44 sm:w-56"
            />
          </form>
          <label class="flex cursor-pointer items-center gap-2 text-sm">
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-primary"
              checked={@unread_only}
              phx-click="toggle_unread_only"
            /> Unread only
          </label>
          <span class="text-sm opacity-60">{@unread_count} unread · {@feed_count} feeds</span>
          <button :if={@unread_count > 0} phx-click="mark_all_read" class="btn btn-ghost btn-xs gap-1">
            <.icon name="hero-check-circle-micro" class="size-4" /> Mark all read
          </button>
        </div>
      </div>

      <div class="flex flex-wrap items-center gap-1.5">
        <span class="mr-1 text-sm opacity-50">Views:</span>
        <div :for={slice <- @slices} class="join">
          <button
            phx-click="apply_slice"
            phx-value-id={slice.id}
            class={[
              "btn btn-xs join-item",
              (@active_slice_id == slice.id && "btn-primary") || "btn-ghost"
            ]}
          >
            {slice.name}
          </button>
          <button
            phx-click="delete_slice"
            phx-value-id={slice.id}
            data-confirm={"Delete the \"#{slice.name}\" view?"}
            class="btn btn-ghost btn-xs join-item text-error"
            title="Delete view"
          >
            ×
          </button>
        </div>
        <details class="dropdown">
          <summary class="btn btn-ghost btn-xs gap-1">
            <.icon name="hero-bookmark-micro" class="size-4" /> Save view
          </summary>
          <div class="dropdown-content z-10 mt-1 w-64 space-y-2 rounded-box border border-base-300 bg-base-200 p-3 shadow-lg">
            <p class="text-xs opacity-60">Save the current filters as a named view.</p>
            <form phx-submit="save_slice" class="flex items-center gap-1">
              <input
                name="slice[name]"
                maxlength="60"
                required
                placeholder="View name"
                class="input input-bordered input-xs flex-1"
              />
              <button class="btn btn-primary btn-xs">Save</button>
            </form>
          </div>
        </details>
      </div>

      <div class="flex flex-wrap items-center gap-1.5">
        <details :if={@sources != []} class="dropdown">
          <summary class="btn btn-ghost btn-xs gap-1">
            <.icon name="hero-funnel-micro" class="size-4" /> Groups
            <span
              :if={not all_sources_selected?(@selected_source_keys, @source_keys)}
              class="badge badge-primary badge-xs"
            >
              {MapSet.size(@selected_source_keys)}
            </span>
          </summary>
          <div class="dropdown-content z-10 mt-1 max-h-80 w-64 space-y-1 overflow-y-auto rounded-box border border-base-300 bg-base-200 p-3 shadow-lg">
            <div class="flex justify-between pb-1 text-xs opacity-60">
              <button type="button" phx-click="select_all_sources" class="link link-hover">
                All
              </button>
              <button type="button" phx-click="select_no_sources" class="link link-hover">
                None
              </button>
            </div>
            <div :for={source <- @sources} class="group flex items-center gap-2 text-sm">
              <label class="flex min-w-0 flex-1 cursor-pointer items-center gap-2">
                <input
                  type="checkbox"
                  class="checkbox checkbox-xs"
                  checked={MapSet.member?(@selected_source_keys, source.key)}
                  phx-click="toggle_source"
                  phx-value-key={source.key}
                />
                <span class="truncate">{source.label}</span>
                <span :if={source.kind == :follow} class="badge badge-ghost badge-xs">followed</span>
              </label>
              <button
                type="button"
                phx-click="only_source"
                phx-value-key={source.key}
                class="link link-hover shrink-0 text-xs opacity-0 group-hover:opacity-60 focus:opacity-60"
                title="Show only this group"
              >
                only
              </button>
            </div>
          </div>
        </details>

        <span :if={@sources != []} class="mx-1 h-4 w-px bg-base-content/15"></span>

        <span class="mr-1 text-sm opacity-50">Saved:</span>
        <button
          :for={r <- @reactions}
          phx-click="filter_reaction"
          phx-value-emoji={r.emoji}
          title={r.label}
          class={["btn btn-xs", (@reaction_filter == r.emoji && "btn-primary") || "btn-ghost"]}
        >
          {r.emoji}
        </button>
        <details class="dropdown">
          <summary class="btn btn-ghost btn-xs gap-1">
            <.icon name="hero-cog-6-tooth-micro" class="size-4" /> palette
          </summary>
          <div class="dropdown-content z-10 mt-1 w-72 space-y-2 rounded-box border border-base-300 bg-base-200 p-3 shadow-lg">
            <p class="text-xs font-semibold opacity-60">Reaction palette</p>
            <ul class="space-y-1">
              <li
                :for={r <- @reactions}
                class="flex items-center justify-between text-sm"
              >
                <span>{r.emoji} <span class="opacity-60">{r.label}</span></span>
                <button
                  phx-click="delete_reaction"
                  phx-value-id={r.id}
                  class="btn btn-ghost btn-xs text-error"
                >
                  remove
                </button>
              </li>
            </ul>
            <form phx-submit="add_reaction" class="flex items-center gap-1">
              <input
                name="reaction[emoji]"
                maxlength="16"
                placeholder="😀"
                required
                class="input input-bordered input-xs w-14"
              />
              <input
                name="reaction[label]"
                placeholder="label (optional)"
                class="input input-bordered input-xs flex-1"
              />
              <button class="btn btn-primary btn-xs">Add</button>
            </form>
          </div>
        </details>
      </div>

      <p
        :if={@feed_count == 0 and is_nil(@reaction_filter)}
        class="rounded-lg bg-base-200 p-6 text-center opacity-70"
      >
        Your newsfeed is empty. Add feeds in
        <.link navigate={~p"/groups"} class="link link-primary">Groups</.link>
        or follow someone in <.link navigate={~p"/discover"} class="link link-primary">Discover</.link>.
      </p>

      <div
        :if={@feed_filter}
        class="mt-3 flex items-center gap-2 rounded-lg border border-primary/30 bg-primary/5 px-3 py-2 text-sm"
      >
        <.favicon feed={@feed_filter} class="size-4 rounded-sm" />
        <span class="min-w-0 truncate">
          Showing only <span class="font-semibold">{@feed_filter.title || @feed_filter.url}</span>
        </span>
        <button
          type="button"
          phx-click="clear_feed_filter"
          class="btn btn-ghost btn-xs ml-auto gap-1"
        >
          <.icon name="hero-x-mark-micro" class="size-4" /> Clear
        </button>
      </div>

      <div :if={@feed_count > 0 or @reaction_filter} class="grid gap-4 lg:grid-cols-[22rem_1fr]">
        <%!-- Master: titles list --%>
        <div class="rounded-lg border border-base-content/10 lg:max-h-[78vh] lg:overflow-y-auto">
          <ul id="items" phx-update="stream" class="divide-y divide-base-content/10">
            <li
              :for={{dom_id, item} <- @streams.items}
              id={dom_id}
              phx-click="select"
              phx-value-id={item.id}
              class={[
                "flex cursor-pointer items-start gap-2 px-3 py-2.5 transition-colors hover:bg-base-200/60",
                item.id == @selected_id && "bg-base-200",
                item.read && "opacity-60"
              ]}
            >
              <span
                class={[
                  "mt-1.5 size-2 shrink-0 rounded-full",
                  (!item.read && "bg-primary") || "bg-transparent"
                ]}
                aria-hidden="true"
              />
              <div class="min-w-0">
                <div class="flex items-center gap-1.5">
                  <p class={["truncate text-sm", !item.read && "font-semibold"]}>
                    {item.title || "(untitled)"}
                  </p>
                  <span :if={item.reactions != []} class="shrink-0 text-xs leading-none">
                    {Enum.join(item.reactions)}
                  </span>
                </div>
                <div class="mt-0.5 flex items-center gap-1.5 text-xs opacity-50">
                  <button
                    type="button"
                    phx-click="filter_feed"
                    phx-value-feed-id={item.feed.id}
                    title={"Only show #{item.feed.title || item.feed.url}"}
                    class="flex min-w-0 items-center gap-1.5 hover:text-primary hover:opacity-100"
                  >
                    <.favicon feed={item.feed} class="size-3.5 rounded-sm" />
                    <span class="truncate">{item.feed.title || item.feed.url}</span>
                  </button>
                  <span class="shrink-0">· {format_time(item.published_at)}</span>
                </div>
              </div>
            </li>
          </ul>

          <div :if={@has_more} class="p-3 text-center">
            <button phx-click="load_more" class="btn btn-outline btn-xs">Load more</button>
          </div>
        </div>

        <%!-- Detail: selected entry content --%>
        <article class="rounded-lg border border-base-content/10 p-5 lg:max-h-[78vh] lg:overflow-y-auto">
          <%= if @selected do %>
            <h2 class="text-xl font-bold leading-tight">
              <a href={@selected.url} target="_blank" rel="noopener" class="link link-hover">
                {@selected.title || "(untitled)"}
              </a>
            </h2>
            <div class="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs opacity-60">
              <button
                type="button"
                phx-click="filter_feed"
                phx-value-feed-id={@selected.feed.id}
                title={"Only show #{@selected.feed.title || @selected.feed.url}"}
                class="flex items-center gap-2 hover:text-primary hover:opacity-100"
              >
                <.favicon feed={@selected.feed} class="size-4 rounded-sm" />
                <span>{@selected.feed.title || @selected.feed.url}</span>
              </button>
              <span :if={@selected.author}>· {@selected.author}</span>
              <span>· {format_time(@selected.published_at)}</span>
            </div>
            <div class="mt-4 flex flex-wrap items-center gap-1">
              <span class="mr-1 text-xs opacity-50">Save:</span>
              <button
                :for={r <- @reactions}
                phx-click="toggle_reaction"
                phx-value-emoji={r.emoji}
                title={r.label}
                class={[
                  "btn btn-sm",
                  (r.emoji in @selected.reactions && "btn-primary") ||
                    "btn-ghost border border-base-content/10"
                ]}
              >
                {r.emoji}
              </button>
            </div>

            <div class="feed-content mt-4 text-sm">{raw(content_html(@selected))}</div>
            <div class="mt-5">
              <a
                href={@selected.url}
                target="_blank"
                rel="noopener"
                class="btn btn-primary btn-sm gap-1"
              >
                <.icon name="hero-arrow-top-right-on-square-micro" class="size-4" /> Open original
              </a>
            </div>
          <% else %>
            <div class="flex h-full min-h-40 items-center justify-center text-center text-sm opacity-50">
              Select an entry to read it here.
            </div>
          <% end %>
        </article>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("select", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    prev = socket.assigns.selected
    Feeds.mark_read(user_id, id)
    item = %{Feeds.get_item!(id) | read: true}
    item = hd(Reactions.put_reactions(socket.assigns.current_scope, [item]))

    socket =
      assign(socket,
        selected: item,
        selected_id: id,
        unread_count: Feeds.unread_count(user_id, socket.assigns.feed_ids)
      )

    socket =
      if socket.assigns.unread_only do
        # In unread-only mode a just-read item leaves the list.
        stream_delete(socket, :items, item)
      else
        socket = stream_insert(socket, :items, item)
        if prev && prev.id != id, do: stream_insert(socket, :items, prev), else: socket
      end

    {:noreply, socket}
  end

  def handle_event("search", %{"q" => q}, socket) do
    {:noreply, socket |> assign(:query, q) |> load_first_page(reset: true)}
  end

  def handle_event("toggle_unread_only", _params, socket) do
    {:noreply,
     socket
     |> assign(unread_only: !socket.assigns.unread_only, active_slice_id: nil)
     |> load_first_page(reset: true)}
  end

  def handle_event("toggle_reaction", %{"emoji" => emoji}, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, socket}

      item ->
        Reactions.toggle_item_reaction(socket.assigns.current_scope, item.id, emoji)
        reactions = toggle_member(item.reactions, emoji)
        item = %{item | reactions: reactions}
        socket = assign(socket, :selected, item)

        # If filtering by this emoji and it was just removed, drop the row.
        socket =
          if socket.assigns.reaction_filter == emoji and emoji not in reactions,
            do: stream_delete(socket, :items, item),
            else: stream_insert(socket, :items, item)

        {:noreply, socket}
    end
  end

  def handle_event("toggle_source", %{"key" => key}, socket) do
    selected = toggle_member_set(socket.assigns.selected_source_keys, key)
    {:noreply, reload_with_sources(socket, selected)}
  end

  def handle_event("select_all_sources", _params, socket) do
    {:noreply, reload_with_sources(socket, socket.assigns.source_keys)}
  end

  def handle_event("select_no_sources", _params, socket) do
    {:noreply, reload_with_sources(socket, MapSet.new())}
  end

  def handle_event("only_source", %{"key" => key}, socket) do
    {:noreply, reload_with_sources(socket, MapSet.new([key]))}
  end

  def handle_event("filter_reaction", %{"emoji" => emoji}, socket) do
    filter = if socket.assigns.reaction_filter == emoji, do: nil, else: emoji

    {:noreply,
     socket
     |> assign(reaction_filter: filter, active_slice_id: nil, feed_filter: nil)
     |> load_first_page(reset: true)}
  end

  # Drill into a single feed (clicked its favicon/title in a row). Only honour
  # feeds that are actually in the user's current set.
  def handle_event("filter_feed", %{"feed-id" => id}, socket) do
    if id in socket.assigns.feed_ids do
      feed = Feeds.get_feed!(id)
      user_id = socket.assigns.current_scope.user.id

      {:noreply,
       socket
       |> assign(feed_filter: feed, reaction_filter: nil, active_slice_id: nil)
       |> assign(unread_count: Feeds.unread_count(user_id, [feed.id]))
       |> load_first_page(reset: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("clear_feed_filter", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    {:noreply,
     socket
     |> assign(
       feed_filter: nil,
       unread_count: Feeds.unread_count(user_id, socket.assigns.feed_ids)
     )
     |> load_first_page(reset: true)}
  end

  def handle_event("apply_slice", %{"id" => id}, socket) do
    slice = Timelines.get_slice!(socket.assigns.current_scope, id)

    {:noreply,
     socket
     |> assign(
       selected_source_keys: MapSet.new(slice.source_keys),
       unread_only: slice.unread_only,
       reaction_filter: slice.reaction_emoji,
       active_slice_id: slice.id,
       feed_filter: nil
     )
     |> load_feed_set()
     |> load_first_page(reset: true)}
  end

  def handle_event("save_slice", %{"slice" => %{"name" => name}}, socket) do
    attrs = %{
      name: name,
      source_keys: MapSet.to_list(socket.assigns.selected_source_keys),
      unread_only: socket.assigns.unread_only,
      reaction_emoji: socket.assigns.reaction_filter
    }

    case Timelines.create_slice(socket.assigns.current_scope, attrs) do
      {:ok, slice} ->
        {:noreply,
         socket
         |> assign(
           slices: Timelines.list_slices(socket.assigns.current_scope),
           active_slice_id: slice.id
         )
         |> put_flash(:info, "Saved view \"#{slice.name}\"")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't save (name blank or already used?)")}
    end
  end

  def handle_event("delete_slice", %{"id" => id}, socket) do
    {:ok, _} = Timelines.delete_slice(socket.assigns.current_scope, id)

    active =
      if to_string(socket.assigns.active_slice_id) == id,
        do: nil,
        else: socket.assigns.active_slice_id

    {:noreply,
     assign(socket,
       slices: Timelines.list_slices(socket.assigns.current_scope),
       active_slice_id: active
     )}
  end

  def handle_event("add_reaction", %{"reaction" => %{"emoji" => emoji} = params}, socket) do
    case Reactions.add_reaction(socket.assigns.current_scope, emoji, params["label"]) do
      {:ok, _} ->
        {:noreply, assign_palette(socket)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't add that reaction (already in palette?)")}
    end
  end

  def handle_event("delete_reaction", %{"id" => id}, socket) do
    {:ok, _} = Reactions.delete_reaction(socket.assigns.current_scope, id)
    socket = assign_palette(socket)

    # Clear the filter if it pointed at the deleted emoji.
    if socket.assigns.reaction_filter in Enum.map(socket.assigns.reactions, & &1.emoji) do
      {:noreply, socket}
    else
      {:noreply, socket |> assign(:reaction_filter, nil) |> load_first_page(reset: true)}
    end
  end

  def handle_event("load_more", _params, socket) do
    items = list_items(socket, before: socket.assigns.cursor)

    {:noreply,
     socket
     |> stream(:items, items)
     |> assign(cursor: cursor_from(items, socket.assigns.cursor), has_more: full_page?(items))}
  end

  def handle_event("mark_all_read", _params, socket) do
    Feeds.mark_all_read(socket.assigns.current_scope.user.id, current_feed_ids(socket))
    {:noreply, socket |> assign(:unread_count, 0) |> load_first_page(reset: true)}
  end

  @impl true
  def handle_info(:newsfeed_changed, socket) do
    {:noreply, socket |> load_feed_set() |> load_first_page(reset: true)}
  end

  def handle_info({:new_items, feed_id, items}, socket) do
    in_view? = feed_id in current_feed_ids(socket)

    if in_view? do
      items = Enum.map(items, &FeedPug.Repo.preload(&1, :feed))

      {:noreply,
       socket
       |> assign(:unread_count, socket.assigns.unread_count + length(items))
       |> then(fn s -> Enum.reduce(items, s, &stream_insert(&2, :items, &1, at: 0)) end)}
    else
      {:noreply, socket}
    end
  end

  ## Helpers

  defp load_feed_set(socket) do
    scope = socket.assigns.current_scope
    sources = Groups.list_newsfeed_sources(scope)
    all_keys = MapSet.new(sources, & &1.key)
    selected = reconcile_sources(socket, all_keys)

    feed_ids =
      sources
      |> Enum.filter(&MapSet.member?(selected, &1.key))
      |> Enum.flat_map(& &1.feed_ids)
      |> Enum.uniq()

    if connected?(socket) do
      resubscribe(socket.assigns[:feed_ids] || [], feed_ids, scope)
    end

    assign(socket,
      sources: sources,
      source_keys: all_keys,
      selected_source_keys: selected,
      feed_ids: feed_ids,
      feed_count: length(feed_ids),
      unread_count: Feeds.unread_count(scope.user.id, feed_ids)
    )
  end

  # First load selects everything; later loads keep the user's choice while
  # auto-including any newly-appeared source.
  defp reconcile_sources(socket, all_keys) do
    case socket.assigns[:selected_source_keys] do
      nil ->
        all_keys

      selected ->
        new_keys = MapSet.difference(all_keys, socket.assigns[:source_keys] || MapSet.new())
        selected |> MapSet.intersection(all_keys) |> MapSet.union(new_keys)
    end
  end

  defp load_first_page(socket, opts \\ []) do
    items = list_items(socket, [])

    socket
    |> stream(:items, items, reset: Keyword.get(opts, :reset, false))
    |> assign(cursor: cursor_from(items, nil), has_more: full_page?(items))
  end

  # The feed set the timeline currently lists from: a single feed when the user
  # has drilled into one (clicked its favicon/title), otherwise the full
  # source-selected set.
  defp current_feed_ids(%{assigns: %{feed_filter: %{id: id}}}), do: [id]
  defp current_feed_ids(socket), do: socket.assigns.feed_ids

  defp list_items(socket, extra) do
    scope = socket.assigns.current_scope

    case socket.assigns.reaction_filter do
      nil ->
        Feeds.list_newsfeed_items(
          current_feed_ids(socket),
          [
            limit: @page_size,
            user_id: scope.user.id,
            unread_only: socket.assigns.unread_only,
            query: socket.assigns.query
          ] ++ extra
        )
        |> then(&Reactions.put_reactions(scope, &1))

      emoji ->
        # "Saved" view: items the user reacted with `emoji`, across all feeds.
        Reactions.list_reacted_items(
          scope,
          emoji,
          [limit: @page_size, query: socket.assigns.query] ++ extra
        )
    end
  end

  defp full_page?(items), do: length(items) == @page_size

  defp all_sources_selected?(selected, all), do: MapSet.equal?(selected, all)

  defp assign_palette(socket) do
    assign(socket, :reactions, Reactions.list_reactions(socket.assigns.current_scope))
  end

  defp toggle_member(list, value) do
    if value in list, do: List.delete(list, value), else: list ++ [value]
  end

  defp toggle_member_set(set, value) do
    if MapSet.member?(set, value), do: MapSet.delete(set, value), else: MapSet.put(set, value)
  end

  defp reload_with_sources(socket, selected) do
    socket
    |> assign(selected_source_keys: selected, active_slice_id: nil, feed_filter: nil)
    |> load_feed_set()
    |> load_first_page(reset: true)
  end

  defp resubscribe(old_ids, new_ids, scope) do
    Phoenix.PubSub.subscribe(FeedPug.PubSub, Groups.newsfeed_topic(scope.user.id))

    for id <- old_ids -- new_ids,
        do: Phoenix.PubSub.unsubscribe(FeedPug.PubSub, Feeds.feed_topic(id))

    for id <- new_ids -- old_ids,
        do: Phoenix.PubSub.subscribe(FeedPug.PubSub, Feeds.feed_topic(id))
  end

  defp cursor_from([], previous), do: previous

  defp cursor_from(items, _previous) do
    last = List.last(items)
    {last.sort_at, last.id}
  end

  defp format_time(nil), do: ""
  defp format_time(dt), do: Calendar.strftime(dt, "%b %-d, %Y")
end
