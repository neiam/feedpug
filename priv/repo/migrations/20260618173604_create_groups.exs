defmodule FeedPug.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :parent_id, references(:groups, on_delete: :delete_all)
      add :name, :string, null: false
      add :slug, :string, null: false
      # Dot-separated materialized path of slugs, e.g. "blogs.tech.erlang".
      # Slugs are restricted to [a-z0-9-] so the path never contains LIKE
      # wildcards, making descendant prefix queries safe and index-friendly.
      add :path, :string, null: false
      add :is_default, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:groups, [:user_id])

    # Descendant queries use `path = X OR path LIKE X || '.%'`; the
    # text_pattern_ops index serves the prefix LIKE under any locale.
    execute(
      "CREATE INDEX groups_path_prefix_index ON groups (path text_pattern_ops)",
      "DROP INDEX groups_path_prefix_index"
    )

    create unique_index(:groups, [:user_id, :path])

    # NULLs are distinct in Postgres, so root uniqueness needs a partial index.
    create unique_index(:groups, [:user_id, :name],
             where: "parent_id IS NULL",
             name: :groups_root_name_index
           )

    create unique_index(:groups, [:user_id, :parent_id, :name], name: :groups_child_name_index)
  end
end
