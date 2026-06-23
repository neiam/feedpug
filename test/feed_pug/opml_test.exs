defmodule FeedPug.OpmlTest do
  use ExUnit.Case, async: true

  alias FeedPug.Opml

  @opml """
  <?xml version="1.0" encoding="UTF-8"?>
  <opml version="2.0">
    <head><title>subs</title></head>
    <body>
      <outline text="Comics">
        <outline text="Sad">
          <outline type="rss" text="Sad Comic" xmlUrl="https://ex.com/sad.xml"/>
        </outline>
        <outline type="rss" text="Funny" xmlUrl="https://ex.com/funny.xml"/>
      </outline>
      <outline type="rss" title="Toplevel" xmlUrl="https://ex.com/top.xml"/>
    </body>
  </opml>
  """

  test "parses nested folders and feeds" do
    assert {:ok, nodes} = Opml.parse(@opml)

    assert [comics, top] = nodes
    assert comics.type == :group
    assert comics.name == "Comics"
    assert top == %{type: :feed, title: "Toplevel", xml_url: "https://ex.com/top.xml"}

    assert [sad, funny] = comics.children
    assert sad.type == :group and sad.name == "Sad"
    assert funny == %{type: :feed, title: "Funny", xml_url: "https://ex.com/funny.xml"}
    assert [%{type: :feed, xml_url: "https://ex.com/sad.xml"}] = sad.children
  end

  test "returns an error for non-OPML input" do
    assert {:error, _} = Opml.parse("this is not xml at all <<<")
  end

  test "handles UTF-8 (non-ASCII) titles without double-decoding" do
    opml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <opml version="1.0"><body>
      <outline text="Café">
        <outline type="rss" text="Valve » Linux" xmlUrl="https://ex.com/valve.xml"/>
      </outline>
    </body></opml>
    """

    assert {:ok, [folder]} = Opml.parse(opml)
    assert folder.name == "Café"
    assert [%{title: "Valve » Linux"}] = folder.children
  end
end
