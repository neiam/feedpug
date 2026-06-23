defmodule FeedPug.Repo.Migrations.CreateReactions do
  use Ecto.Migration

  def change do
    # A user's palette of reaction emojis.
    create table(:reactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :emoji, :string, null: false
      add :label, :string
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:reactions, [:user_id, :emoji])
    create index(:reactions, [:user_id])

    # A reaction applied to an item by a user ("saving" / tagging it).
    create table(:item_reactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :delete_all), null: false
      add :emoji, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:item_reactions, [:user_id, :item_id, :emoji])
    create index(:item_reactions, [:user_id, :emoji])
    create index(:item_reactions, [:item_id])
  end
end
