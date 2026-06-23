defmodule FeedPugWeb.GroupsLive do
  @moduledoc """
  Manage the current user's own groups: create subgroups, add/remove feeds,
  delete subgroups. Hierarchy is shown with colon path notation (blogs:tech).
  """
  use FeedPugWeb, :live_view

  alias FeedPug.Groups

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> allow_upload(:opml,
       accept: ~w(.opml .xml),
       max_entries: 1,
       max_file_size: 8_000_000
     )
     |> assign_forms()
     |> load_groups()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex items-center justify-between gap-2">
        <h1 class="text-2xl font-bold">Your Groups</h1>
        <a href={~p"/opml/export"} download class="btn btn-ghost btn-sm gap-1">
          <.icon name="hero-arrow-down-tray-micro" class="size-4" /> Export OPML
        </a>
      </div>

      <div class="grid gap-4 sm:grid-cols-2">
        <.form
          for={@subgroup_form}
          id="subgroup-form"
          phx-submit="create_subgroup"
          class="rounded-lg border border-base-content/10 p-4 space-y-2"
        >
          <h2 class="font-semibold">New subgroup</h2>
          <.input
            field={@subgroup_form[:parent_id]}
            type="select"
            label="Parent"
            options={group_options(@groups)}
          />
          <.input field={@subgroup_form[:name]} type="text" label="Name" placeholder="erlang" />
          <button class="btn btn-primary btn-sm w-full">Create subgroup</button>
        </.form>

        <.form
          for={@feed_form}
          id="feed-form"
          phx-submit="add_feed"
          class="rounded-lg border border-base-content/10 p-4 space-y-2"
        >
          <h2 class="font-semibold">Add a feed</h2>
          <.input
            field={@feed_form[:group_id]}
            type="select"
            label="Into group"
            options={group_options(@groups)}
          />
          <.input
            field={@feed_form[:url]}
            type="url"
            label="Feed URL"
            placeholder="https://example.com/feed.xml"
          />
          <button class="btn btn-primary btn-sm w-full">Add feed</button>
        </.form>

        <.form
          for={@opml_form}
          id="opml-form"
          phx-submit="import_opml"
          phx-change="validate_opml"
          class="rounded-lg border border-base-content/10 p-4 space-y-2 sm:col-span-2"
        >
          <h2 class="font-semibold">Import OPML</h2>
          <div class="flex flex-col gap-2 sm:flex-row sm:items-end">
            <div class="flex-1">
              <.input
                field={@opml_form[:target_id]}
                type="select"
                label="Import into"
                options={[{"Top level (new root groups)", "root"} | group_options(@groups)]}
              />
            </div>
            <div class="flex-1">
              <label class="block text-sm font-semibold mb-1">OPML file</label>
              <.live_file_input
                upload={@uploads.opml}
                class="file-input file-input-bordered file-input-sm w-full"
              />
            </div>
            <button class="btn btn-primary btn-sm">Import</button>
          </div>
          <p :for={err <- upload_errors(@uploads.opml)} class="text-xs text-error">
            {opml_error(err)}
          </p>
        </.form>
      </div>

      <div class="space-y-2">
        <div
          :for={group <- @groups}
          id={"group-#{group.id}"}
          class="rounded-lg border border-base-content/10 p-3"
          style={"margin-left: #{depth(group) * 1.25}rem"}
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="font-semibold">{display_path(group)}</span>
              <span :if={group.is_default} class="badge badge-ghost badge-sm">default</span>
              <% unread = group_unread(@feeds_by_group[group.id] || [], @unread) %>
              <span :if={unread > 0} class="badge badge-primary badge-sm">{unread} unread</span>
            </div>
            <button
              :if={not group.is_default}
              phx-click="delete_group"
              phx-value-id={group.id}
              data-confirm={"Delete #{display_path(group)} and its subgroups?"}
              class="btn btn-ghost btn-xs text-error"
            >
              <.icon name="hero-trash" class="size-4" />
            </button>
          </div>

          <ul class="mt-2 space-y-1">
            <li
              :for={gf <- @feeds_by_group[group.id] || []}
              id={"group-feed-#{gf.id}"}
              class="flex items-center justify-between gap-2 text-sm"
            >
              <div class="flex min-w-0 items-center gap-2">
                <.favicon feed={gf.feed} />
                <span class="truncate">{gf.custom_title || gf.feed.title || gf.feed.url}</span>
                <.feed_health feed={gf.feed} />
              </div>
              <button
                phx-click="remove_feed"
                phx-value-id={gf.id}
                class="btn btn-ghost btn-xs text-error"
              >
                remove
              </button>
            </li>
            <li :if={(@feeds_by_group[group.id] || []) == []} class="text-xs opacity-50">
              no feeds yet
            </li>
          </ul>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event(
        "create_subgroup",
        %{"subgroup" => %{"parent_id" => pid, "name" => name}},
        socket
      ) do
    parent = Groups.get_group!(socket.assigns.current_scope, pid)

    case Groups.create_group(socket.assigns.current_scope, %{"name" => name}, parent) do
      {:ok, _group} ->
        {:noreply,
         socket |> put_flash(:info, "Subgroup created") |> assign_forms() |> load_groups()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create subgroup (name may be taken)")}
    end
  end

  def handle_event("add_feed", %{"feed" => %{"group_id" => gid, "url" => url}}, socket) do
    group = Groups.get_group!(socket.assigns.current_scope, gid)

    case Groups.add_feed_to_group(socket.assigns.current_scope, group, url) do
      {:ok, _gf} ->
        {:noreply, socket |> put_flash(:info, "Feed added") |> assign_forms() |> load_groups()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add feed (already in this group?)")}
    end
  end

  def handle_event("remove_feed", %{"id" => id}, socket) do
    gf = FeedPug.Repo.get!(Groups.GroupFeed, id)
    {:ok, _} = Groups.remove_feed_from_group(socket.assigns.current_scope, gf)
    {:noreply, socket |> put_flash(:info, "Feed removed") |> load_groups()}
  end

  def handle_event("validate_opml", _params, socket), do: {:noreply, socket}

  def handle_event("import_opml", %{"opml" => %{"target_id" => tid}}, socket) do
    target =
      if tid == "root",
        do: :root,
        else: Groups.get_group!(socket.assigns.current_scope, tid)

    contents =
      consume_uploaded_entries(socket, :opml, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case contents do
      [xml] ->
        case FeedPug.Opml.parse(xml) do
          {:ok, nodes} ->
            {groups, feeds} = Groups.import_opml(socket.assigns.current_scope, nodes, target)

            {:noreply,
             socket
             |> put_flash(:info, "Imported #{feeds} feeds and #{groups} subgroups")
             |> assign_forms()
             |> load_groups()}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Could not parse that OPML file")}
        end

      [] ->
        {:noreply, put_flash(socket, :error, "Choose an OPML file to import")}
    end
  end

  def handle_event("delete_group", %{"id" => id}, socket) do
    group = Groups.get_group!(socket.assigns.current_scope, id)

    case Groups.delete_group(socket.assigns.current_scope, group) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Group deleted") |> load_groups()}

      {:error, :default_group} ->
        {:noreply, put_flash(socket, :error, "Can't delete a default group")}
    end
  end

  ## Helpers

  defp load_groups(socket) do
    groups = Groups.list_groups(socket.assigns.current_scope)
    feeds_by_group = Map.new(groups, fn g -> {g.id, Groups.list_group_feeds(g)} end)

    feed_ids = feeds_by_group |> Map.values() |> List.flatten() |> Enum.map(& &1.feed_id)
    unread = FeedPug.Feeds.unread_counts_by_feed(socket.assigns.current_scope.user.id, feed_ids)

    assign(socket, groups: groups, feeds_by_group: feeds_by_group, unread: unread)
  end

  defp group_unread(feeds, unread) do
    feeds |> Enum.map(&Map.get(unread, &1.feed_id, 0)) |> Enum.sum()
  end

  defp assign_forms(socket) do
    socket
    |> assign(:subgroup_form, to_form(%{"parent_id" => nil, "name" => ""}, as: :subgroup))
    |> assign(:feed_form, to_form(%{"group_id" => nil, "url" => ""}, as: :feed))
    |> assign(:opml_form, to_form(%{"target_id" => nil}, as: :opml))
  end

  defp opml_error(:too_large), do: "File is too large (max 8MB)"
  defp opml_error(:not_accepted), do: "Must be an .opml or .xml file"
  defp opml_error(:too_many_files), do: "Choose a single file"
  defp opml_error(other), do: to_string(other)

  defp group_options(groups), do: Enum.map(groups, &{display_path(&1), &1.id})

  defp display_path(group), do: String.replace(group.path, ".", ":")

  defp depth(group), do: group.path |> String.graphemes() |> Enum.count(&(&1 == "."))
end
