defmodule FeedPug.Repo.Migrations.CreateItemReads do
  use Ecto.Migration

  def change do
    create table(:item_reads) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :item_id, references(:items, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:item_reads, [:user_id, :item_id])
    create index(:item_reads, [:item_id])
  end
end
