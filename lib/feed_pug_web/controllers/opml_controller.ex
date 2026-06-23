defmodule FeedPugWeb.OpmlController do
  use FeedPugWeb, :controller

  alias FeedPug.{Groups, Opml}

  @doc "GET /opml/export — download the user's subscriptions as an OPML file."
  def export(conn, _params) do
    scope = conn.assigns.current_scope
    xml = scope |> Groups.export_tree() |> Opml.export(title: "FeedPug subscriptions")

    conn
    |> put_resp_content_type("text/x-opml")
    |> put_resp_header(
      "content-disposition",
      ~s(attachment; filename="feedpug-subscriptions.opml")
    )
    |> send_resp(200, xml)
  end
end
