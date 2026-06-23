defmodule FeedPug.Opml do
  @moduledoc """
  Parses and renders OPML subscription lists as a nested node tree.

  Each node is either a feed (`%{type: :feed, title, xml_url, html_url}`) or a
  folder (`%{type: :group, name, children}`). Folders nest arbitrarily, mapping
  directly onto FeedPug's subgroup hierarchy. `parse/1` reads OPML into nodes;
  `export/2` renders nodes back to an OPML document (see `FeedPug.Groups`).
  """
  require Record

  Record.defrecordp(:xmlElement, Record.extract(:xmlElement, from_lib: "xmerl/include/xmerl.hrl"))

  Record.defrecordp(
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  @type node_t :: %{required(:type) => :feed | :group, optional(atom()) => any()}

  ## Export -------------------------------------------------------------------

  @doc """
  Renders a nested node tree (folders + feeds) into an OPML 2.0 document.
  Inverse of `parse/1`. Opts: `:title` (defaults to "FeedPug subscriptions").
  """
  @spec export([node_t()], keyword()) :: String.t()
  def export(nodes, opts \\ []) when is_list(nodes) do
    title = Keyword.get(opts, :title, "FeedPug subscriptions")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="2.0">
      <head>
        <title>#{escape(title)}</title>
      </head>
      <body>
    #{render_nodes(nodes, 4)}  </body>
    </opml>
    """
  end

  defp render_nodes(nodes, indent), do: Enum.map_join(nodes, "", &render_node(&1, indent))

  defp render_node(%{type: :feed} = feed, indent) do
    pad = String.duplicate(" ", indent)
    title = feed[:title] || feed[:xml_url]

    attrs =
      ~s(text="#{escape(title)}" title="#{escape(title)}" type="rss" xmlUrl="#{escape(feed[:xml_url])}")

    attrs =
      if feed[:html_url], do: attrs <> ~s( htmlUrl="#{escape(feed[:html_url])}"), else: attrs

    "#{pad}<outline #{attrs}/>\n"
  end

  defp render_node(%{type: :group, name: name, children: children}, indent) do
    pad = String.duplicate(" ", indent)
    open = ~s(<outline text="#{escape(name)}" title="#{escape(name)}">)
    "#{pad}#{open}\n#{render_nodes(children, indent + 2)}#{pad}</outline>\n"
  end

  defp escape(nil), do: ""

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  ## Parse --------------------------------------------------------------------

  @doc "Parses OPML text into a list of top-level nodes."
  @spec parse(binary()) :: {:ok, [node_t()]} | {:error, term()}
  def parse(xml) when is_binary(xml) do
    # xmerl decodes the byte stream itself per the document's `encoding`
    # declaration, so hand it raw bytes — NOT String.to_charlist/1, which would
    # pre-decode UTF-8 into codepoints and cause a double-decode on non-ASCII.
    {doc, _rest} = :xmerl_scan.string(:erlang.binary_to_list(xml), quiet: true)

    case find_element(doc, :body) do
      nil -> {:error, :no_body}
      body -> {:ok, body |> child_outlines() |> Enum.map(&to_node/1)}
    end
  rescue
    _ -> {:error, :invalid_opml}
  catch
    :exit, _ -> {:error, :invalid_opml}
  end

  defp to_node(el) do
    attrs = attr_map(el)
    label = attrs["text"] || attrs["title"]

    case blank_to_nil(attrs["xmlUrl"]) do
      nil ->
        %{
          type: :group,
          name: label || "Imported",
          children: el |> child_outlines() |> Enum.map(&to_node/1)
        }

      url ->
        %{type: :feed, title: label, xml_url: url}
    end
  end

  ## xmerl helpers

  defp child_outlines(el) do
    for child <- xmlElement(el, :content),
        Record.is_record(child, :xmlElement),
        xmlElement(child, :name) == :outline,
        do: child
  end

  defp find_element(el, name) do
    cond do
      not Record.is_record(el, :xmlElement) -> nil
      xmlElement(el, :name) == name -> el
      true -> el |> xmlElement(:content) |> Enum.find_value(&find_element(&1, name))
    end
  end

  defp attr_map(el) do
    for attr <- xmlElement(el, :attributes), into: %{} do
      {to_string(xmlAttribute(attr, :name)), to_string(xmlAttribute(attr, :value))}
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(str) do
    case String.trim(str) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
