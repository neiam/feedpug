defmodule FeedPug.ReactionsTest do
  use FeedPug.DataCase, async: true

  import FeedPug.AccountsFixtures

  alias FeedPug.{Feeds, Reactions}

  defp item_fixture do
    {:ok, feed} = Feeds.upsert_feed_by_url("https://ex.com/feed.xml")

    {_n, [item]} =
      Feeds.store_items(feed, [
        %{guid: "g1", title: "Item", published_at: ~U[2024-01-01 00:00:00Z]}
      ])

    item
  end

  test "registration seeds the default palette" do
    scope = user_scope_fixture()
    emojis = scope |> Reactions.list_reactions() |> Enum.map(& &1.emoji)
    assert emojis == ["⭐", "❤️", "❗"]
  end

  test "add and remove palette entries" do
    scope = user_scope_fixture()
    assert {:ok, r} = Reactions.add_reaction(scope, "❓", "question")
    assert "❓" in Enum.map(Reactions.list_reactions(scope), & &1.emoji)

    assert {:ok, _} = Reactions.delete_reaction(scope, r.id)
    refute "❓" in Enum.map(Reactions.list_reactions(scope), & &1.emoji)
  end

  test "toggling an item reaction on and off" do
    scope = user_scope_fixture()
    item = item_fixture()

    assert :on = Reactions.toggle_item_reaction(scope, item.id, "⭐")
    assert Reactions.reactions_for_items(scope, [item.id]) == %{item.id => ["⭐"]}

    assert :off = Reactions.toggle_item_reaction(scope, item.id, "⭐")
    assert Reactions.reactions_for_items(scope, [item.id]) == %{}
  end

  test "put_reactions enriches items and list_reacted_items returns saved ones" do
    scope = user_scope_fixture()
    item = item_fixture()
    Reactions.toggle_item_reaction(scope, item.id, "❤️")

    [enriched] = Reactions.put_reactions(scope, [item])
    assert enriched.reactions == ["❤️"]

    assert [saved] = Reactions.list_reacted_items(scope, "❤️")
    assert saved.id == item.id
    assert saved.reactions == ["❤️"]
    assert Reactions.list_reacted_items(scope, "⭐") == []
  end

  test "deleting a palette emoji also clears its applications" do
    scope = user_scope_fixture()
    item = item_fixture()
    [star] = scope |> Reactions.list_reactions() |> Enum.filter(&(&1.emoji == "⭐"))
    Reactions.toggle_item_reaction(scope, item.id, "⭐")

    {:ok, _} = Reactions.delete_reaction(scope, star.id)
    assert Reactions.list_reacted_items(scope, "⭐") == []
  end

  test "ensure_default_reactions seeds the defaults only when the palette is empty" do
    scope = user_scope_fixture()

    for r <- Reactions.list_reactions(scope), do: Reactions.delete_reaction(scope, r.id)
    assert Reactions.list_reactions(scope) == []

    assert palette = Reactions.ensure_default_reactions(scope)
    assert Enum.map(palette, & &1.emoji) == ["⭐", "❤️", "❗"]

    # Idempotent once non-empty: a second call doesn't re-add anything.
    {:ok, _} = Reactions.add_reaction(scope, "❓", "question")

    assert Enum.map(Reactions.ensure_default_reactions(scope), & &1.emoji) ==
             ["⭐", "❤️", "❗", "❓"]
  end

  test "ensure_default_reactions does NOT restore a removed default while others remain" do
    scope = user_scope_fixture()
    [star | _] = Reactions.list_reactions(scope)
    {:ok, _} = Reactions.delete_reaction(scope, star.id)

    palette = Reactions.ensure_default_reactions(scope)
    refute "⭐" in Enum.map(palette, & &1.emoji)
    assert length(palette) == 2
  end

  test "reactions are per-user" do
    a = user_scope_fixture()
    b = user_scope_fixture()
    item = item_fixture()
    Reactions.toggle_item_reaction(a, item.id, "⭐")

    assert Reactions.reactions_for_items(a, [item.id]) == %{item.id => ["⭐"]}
    assert Reactions.reactions_for_items(b, [item.id]) == %{}
  end
end
