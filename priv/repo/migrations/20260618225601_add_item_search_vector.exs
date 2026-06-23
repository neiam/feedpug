defmodule FeedPug.Repo.Migrations.AddItemSearchVector do
  use Ecto.Migration

  # Full-text search over item title + summary + content. A generated tsvector
  # column keeps the index in sync automatically; queried via the GIN index with
  # `websearch_to_tsquery`. Never SELECTed (Postgrex can't decode tsvector), only
  # used in WHERE, so it stays out of the Ecto schema.
  def up do
    execute("""
    ALTER TABLE items ADD COLUMN search_vector tsvector
    GENERATED ALWAYS AS (
      to_tsvector(
        'english',
        coalesce(title, '') || ' ' || coalesce(summary, '') || ' ' || coalesce(content, '')
      )
    ) STORED
    """)

    execute("CREATE INDEX items_search_vector_gin ON items USING gin (search_vector)")
  end

  def down do
    execute("DROP INDEX IF EXISTS items_search_vector_gin")
    execute("ALTER TABLE items DROP COLUMN IF EXISTS search_vector")
  end
end
