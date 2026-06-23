defmodule FeedPugWeb.DevicesLive do
  @moduledoc """
  Manage API tokens for mobile/API clients and render the QR pairing code.

  The QR encodes `feedpug://pair?base=<server>&token=<api-token>`, which the
  Android app scans (or opens as a deep link) to store its credentials.
  """
  use FeedPugWeb, :live_view

  alias FeedPug.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:shown_token, nil) |> load_tokens()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <h1 class="text-2xl font-bold">Devices &amp; API tokens</h1>
      <p class="text-sm opacity-70">
        Generate a token, then scan its QR code from the FeedPug Android app to pair.
        Treat tokens like passwords — anyone with one can read your feeds.
      </p>

      <.form
        for={@form}
        id="token-form"
        phx-submit="create_token"
        class="flex flex-wrap items-end gap-2 rounded-lg border border-base-content/10 p-4"
      >
        <div class="flex-1">
          <.input field={@form[:label]} type="text" label="Label" placeholder="My phone" />
        </div>
        <div class="w-32">
          <.input field={@form[:days]} type="number" label="Expires (days)" placeholder="never" />
        </div>
        <button class="btn btn-primary">Generate token</button>
      </.form>

      <div
        :if={@shown_token}
        id="pairing"
        class="rounded-lg border border-primary/40 bg-base-200 p-4 text-center space-y-3"
      >
        <div class="flex items-center justify-between">
          <h2 class="font-semibold">Pair “{@shown_token.label || "token"}”</h2>
          <button phx-click="hide_qr" class="btn btn-ghost btn-xs">close</button>
        </div>
        <div class="mx-auto w-56">{raw(qr_svg(pair_uri(@shown_token)))}</div>
        <div class="space-y-1">
          <p class="text-xs opacity-60">Or paste this into the app:</p>
          <code class="block break-all rounded bg-base-300 p-2 text-xs">
            {pair_uri(@shown_token)}
          </code>
        </div>
      </div>

      <div class="space-y-2">
        <div
          :for={token <- @tokens}
          id={"token-#{token.id}"}
          class="flex items-center justify-between rounded-lg border border-base-content/10 p-3"
        >
          <div class="min-w-0">
            <p class="font-medium">{token.label || "Unnamed token"}</p>
            <p class="text-xs opacity-50">
              created {format_time(token.inserted_at)} · {if token.last_used_at,
                do: "last used #{format_time(token.last_used_at)}",
                else: "never used"}
              {if token.expires_at, do: " · expires #{format_time(token.expires_at)}"}
            </p>
          </div>
          <div class="flex items-center gap-1">
            <button
              :if={is_nil(token.last_used_at)}
              phx-click="show_qr"
              phx-value-id={token.id}
              class="btn btn-ghost btn-xs gap-1"
            >
              <.icon name="hero-qr-code-micro" class="size-4" /> Pair
            </button>
            <span :if={token.last_used_at} class="badge badge-ghost badge-sm">paired</span>
            <button
              phx-click="delete_token"
              phx-value-id={token.id}
              data-confirm="Revoke this token? Devices using it will be logged out."
              class="btn btn-ghost btn-xs text-error"
            >
              Revoke
            </button>
          </div>
        </div>
        <p :if={@tokens == []} class="text-sm opacity-50">No tokens yet.</p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("create_token", %{"token" => params}, socket) do
    opts =
      [label: params["label"]]
      |> maybe_days(params["days"])

    case Accounts.create_api_token(socket.assigns.current_scope, opts) do
      {:ok, token} ->
        {:noreply, socket |> assign(:shown_token, token) |> load_tokens()}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create token")}
    end
  end

  def handle_event("show_qr", %{"id" => id}, socket) do
    # Re-read from the DB: a device may have paired since the page loaded.
    socket = refresh_tokens(socket)
    token = Enum.find(socket.assigns.tokens, &(to_string(&1.id) == id))

    cond do
      is_nil(token) ->
        {:noreply, socket}

      is_nil(token.last_used_at) ->
        {:noreply, assign(socket, :shown_token, token)}

      true ->
        {:noreply,
         socket
         |> assign(:shown_token, nil)
         |> put_flash(
           :error,
           "That token has already been used — generate a new one to pair another device."
         )}
    end
  end

  def handle_event("hide_qr", _params, socket), do: {:noreply, assign(socket, :shown_token, nil)}

  def handle_event("delete_token", %{"id" => id}, socket) do
    {:ok, _} = Accounts.delete_api_token(socket.assigns.current_scope, id)

    shown =
      if to_string(socket.assigns.shown_token && socket.assigns.shown_token.id) == id,
        do: nil,
        else: socket.assigns.shown_token

    {:noreply, socket |> assign(:shown_token, shown) |> load_tokens()}
  end

  ## Helpers

  defp load_tokens(socket) do
    socket
    |> refresh_tokens()
    |> assign(:form, to_form(%{"label" => "", "days" => ""}, as: :token))
  end

  defp refresh_tokens(socket) do
    assign(socket, :tokens, Accounts.list_api_tokens(socket.assigns.current_scope))
  end

  defp maybe_days(opts, days) do
    case Integer.parse(to_string(days)) do
      {n, _} when n > 0 -> Keyword.put(opts, :expires_in_days, n)
      _ -> opts
    end
  end

  defp pair_uri(token) do
    "feedpug://pair?base=#{URI.encode_www_form(base_url())}&token=#{URI.encode_www_form(token.token)}"
  end

  defp base_url do
    (System.get_env("FEEDPUG_PUBLIC_URL") || FeedPugWeb.Endpoint.url())
    |> String.trim_trailing("/")
  end

  defp qr_svg(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 220, color: "#000000", background_color: "#ffffff")
  end

  defp format_time(nil), do: "—"
  defp format_time(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
