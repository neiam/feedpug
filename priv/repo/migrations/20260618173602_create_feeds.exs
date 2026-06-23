defmodule FeedPug.Repo.Migrations.CreateFeeds do
  use Ecto.Migration

  def change do
    create table(:feeds) do
      add :url, :string, null: false
      add :site_url, :string
      add :title, :string
      add :description, :text
      add :etag, :string
      add :last_modified, :string
      add :last_fetched_at, :utc_datetime
      add :next_fetch_at, :utc_datetime
      add :fetch_interval_seconds, :integer, null: false, default: 3600
      add :failure_count, :integer, null: false, default: 0
      add :status, :string, null: false, default: "active"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:feeds, [:url])
    create index(:feeds, [:status, :next_fetch_at])
  end
end
