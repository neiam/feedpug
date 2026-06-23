defmodule FeedPug.Repo.Migrations.CreateGroupFeeds do
  use Ecto.Migration

  def change do
    create table(:group_feeds) do
      add :group_id, references(:groups, on_delete: :delete_all), null: false
      # Shared canonical feeds are never orphaned by a membership delete.
      add :feed_id, references(:feeds, on_delete: :restrict), null: false
      add :custom_title, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:group_feeds, [:group_id, :feed_id])
    create index(:group_feeds, [:feed_id])
  end
end
