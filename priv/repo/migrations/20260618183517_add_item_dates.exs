defmodule FeedPug.Repo.Migrations.AddItemDates do
  use Ecto.Migration

  def up do
    alter table(:items) do
      # The entry's own "updated/revised" date, when the feed provides one.
      add :revised_at, :utc_datetime
      # Timeline sort key: the most recent meaningful date for the entry.
      add :sort_at, :utc_datetime
    end

    execute("UPDATE items SET sort_at = published_at")
    execute("ALTER TABLE items ALTER COLUMN sort_at SET NOT NULL")

    create index(:items, [:feed_id, "sort_at DESC", "id DESC"])
  end

  def down do
    drop index(:items, [:feed_id, "sort_at DESC", "id DESC"])

    alter table(:items) do
      remove :revised_at
      remove :sort_at
    end
  end
end
