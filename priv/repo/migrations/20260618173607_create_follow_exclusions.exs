defmodule FeedPug.Repo.Migrations.CreateFollowExclusions do
  use Ecto.Migration

  def change do
    create table(:follow_exclusions) do
      add :group_follow_id, references(:group_follows, on_delete: :delete_all), null: false
      add :excluded_group_id, references(:groups, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:follow_exclusions, [:group_follow_id, :excluded_group_id])
  end
end
