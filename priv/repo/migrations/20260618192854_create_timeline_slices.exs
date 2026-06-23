defmodule FeedPug.Repo.Migrations.CreateTimelineSlices do
  use Ecto.Migration

  def change do
    # A named, saved newsfeed filterset: which sources, unread-only, reaction.
    create table(:timeline_slices) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :source_keys, {:array, :string}, null: false, default: []
      add :unread_only, :boolean, null: false, default: false
      add :reaction_emoji, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:timeline_slices, [:user_id, :name])
    create index(:timeline_slices, [:user_id])
  end
end
