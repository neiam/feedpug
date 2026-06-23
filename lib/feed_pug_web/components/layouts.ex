defmodule FeedPugWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use FeedPugWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :wide, :boolean,
    default: false,
    doc: "when true the content uses a wide container for full-width desktop layouts"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8 border-b border-base-content/10">
      <div class="flex-1">
        <.link navigate={~p"/"} class="flex w-fit items-center gap-2">
          <span class="font-mono font-bold tracking-[0.16em] text-accent">FEEDPUG</span>
        </.link>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-1 sm:space-x-3 items-center">
          <%= if @current_scope do %>
            <li>
              <.link navigate={~p"/"} class="btn btn-ghost btn-sm gap-2">
                <.icon name="hero-newspaper-micro" class="size-4" />
                <span class="hidden sm:inline">Newsfeed</span>
              </.link>
            </li>
            <li>
              <.link navigate={~p"/groups"} class="btn btn-ghost btn-sm gap-2">
                <.icon name="hero-rectangle-stack-micro" class="size-4" />
                <span class="hidden sm:inline">Groups</span>
              </.link>
            </li>
            <li>
              <.link navigate={~p"/discover"} class="btn btn-ghost btn-sm gap-2">
                <.icon name="hero-globe-alt-micro" class="size-4" />
                <span class="hidden sm:inline">Discover</span>
              </.link>
            </li>
            <li><.theme_toggle /></li>
            <li>
              <details class="dropdown dropdown-end">
                <summary class="btn btn-ghost btn-sm">
                  <.icon name="hero-user-circle-micro" class="size-4" />
                  <span class="hidden sm:inline truncate max-w-[16ch]">
                    {@current_scope.user.email}
                  </span>
                </summary>
                <ul class="dropdown-content menu bg-base-200 border border-base-300 rounded-box z-10 mt-1 w-44 p-1 shadow-lg">
                  <li>
                    <.link navigate={~p"/users/invites"}>
                      <.icon name="hero-ticket-micro" class="size-4" /> Invites
                    </.link>
                  </li>
                  <li>
                    <.link navigate={~p"/devices"}>
                      <.icon name="hero-device-phone-mobile-micro" class="size-4" /> Devices
                    </.link>
                  </li>
                  <li>
                    <.link navigate={~p"/users/settings"}>
                      <.icon name="hero-cog-6-tooth-micro" class="size-4" /> Settings
                    </.link>
                  </li>
                  <li>
                    <.link href={~p"/users/log-out"} method="delete">
                      <.icon name="hero-arrow-right-on-rectangle-micro" class="size-4" /> Log out
                    </.link>
                  </li>
                </ul>
              </details>
            </li>
          <% else %>
            <li><.theme_toggle /></li>
            <li><.link navigate={~p"/users/log-in"} class="btn btn-primary btn-sm">Log in</.link></li>
          <% end %>
        </ul>
      </div>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class={["mx-auto space-y-4", if(@wide, do: "max-w-[110rem]", else: "max-w-3xl")]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Theme picker dropdown listing every theme defined in `app.css`, including
  the 6 ported neiam-co themes. The selected theme is persisted to
  localStorage by the script in `root.html.heex`, which also handles the
  `phx:set-theme` event dispatched here.
  """
  def theme_toggle(assigns) do
    assigns = assign_new(assigns, :themes, fn -> FeedPug.Themes.all() end)

    ~H"""
    <div class="dropdown dropdown-end">
      <div tabindex="0" role="button" class="btn btn-ghost btn-sm gap-2" aria-label="Choose theme">
        <.icon name="hero-swatch-micro" class="size-4" />
        <span class="hidden sm:inline">Theme</span>
      </div>
      <ul
        tabindex="0"
        class="dropdown-content menu bg-base-200 border border-base-300 rounded-box z-10 mt-1 w-44 p-1 shadow-lg"
      >
        <li>
          <button
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme="system"
            class="flex items-center gap-2"
          >
            <.icon name="hero-computer-desktop-micro" class="size-4" /> System
          </button>
        </li>
        <li :for={theme <- @themes}>
          <button
            type="button"
            phx-click={JS.dispatch("phx:set-theme")}
            data-phx-theme={theme}
            class="flex items-center justify-between"
          >
            <span class="capitalize">{theme}</span>
            <span
              class="size-3 rounded-full border border-base-content/20"
              data-theme={theme}
              style="background: var(--color-primary)"
            />
          </button>
        </li>
      </ul>
    </div>
    """
  end
end
