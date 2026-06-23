defmodule FeedPug.Repo do
  use Ecto.Repo,
    otp_app: :feed_pug,
    adapter: Ecto.Adapters.Postgres
end
