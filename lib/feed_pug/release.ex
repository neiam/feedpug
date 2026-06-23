defmodule FeedPug.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :feed_pug

  def migrate do
    load_app()

    for repo <- repos() do
      ensure_storage(repo)
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  # Creates the database if it doesn't exist yet, so a fresh deploy against an
  # empty (e.g. StackGres-provisioned) Postgres server provisions its own DB.
  defp ensure_storage(repo) do
    case repo.__adapter__().storage_up(repo.config()) do
      :ok -> :ok
      {:error, :already_up} -> :ok
      {:error, reason} -> raise "database storage_up failed: #{inspect(reason)}"
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Sends a test email through the configured mailer, to verify SMTP delivery in a
  deployed release. Recipient comes from the argument or the `TEST_EMAIL` env.

      bin/feed_pug eval 'FeedPug.Release.send_test_email("you@example.com")'
      # or:  bin/test-email you@example.com
  """
  def send_test_email(recipient \\ System.get_env("TEST_EMAIL")) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:swoosh)
    _ = Application.ensure_all_started(:gen_smtp)

    to =
      recipient ||
        raise "no recipient — pass one or set TEST_EMAIL (e.g. bin/test-email you@example.com)"

    config = Application.get_env(@app, FeedPug.Mailer, [])
    IO.puts("Mailer adapter: #{inspect(Keyword.get(config, :adapter))}")
    IO.puts("Sending test email to #{to} …")

    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to)
      |> Swoosh.Email.from(
        {Keyword.get(config, :from_name, "FeedPug"),
         Keyword.get(config, :from_address, "noreply@localhost")}
      )
      |> Swoosh.Email.subject("FeedPug SMTP test")
      |> Swoosh.Email.text_body(
        "Test email from FeedPug at #{DateTime.utc_now()}.\n" <>
          "If you received this, outbound mail delivery is working.\n"
      )

    case FeedPug.Mailer.deliver(email) do
      {:ok, meta} ->
        IO.puts("✓ delivered: #{inspect(meta)}")
        :ok

      {:error, reason} ->
        IO.puts("✗ delivery failed: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
