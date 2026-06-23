defmodule FeedPug.Repo.Migrations.CreateItems do
  use Ecto.Migration

  def change do
    create table(:items) do
      add :feed_id, references(:feeds, on_delete: :delete_all), null: false
      add :guid, :string, null: false
      add :title, :string
      add :url, :string
      add :summary, :text
      add :content, :text
      add :author, :string
      add :published_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:items, [:feed_id, :guid])
    # Primary newsfeed access pattern: recent items across a set of feed_ids.
    create index(:items, [:feed_id, "published_at DESC", "id DESC"])
  end
end
