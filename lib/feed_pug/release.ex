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
  Mints an unowned (system) invite and prints the registration URL. Bootstraps
  the first account when public registration is gated and no user exists yet.

      bin/feed_pug eval 'FeedPug.Release.create_invite()'
      # or:  bin/invite
  """
  def create_invite do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(FeedPug.Repo, fn _repo ->
        FeedPug.Accounts.create_system_invite()
      end)

    case result do
      {:ok, invite} ->
        host = System.get_env("PHX_HOST") || "localhost"
        url = "https://#{host}/users/register?invite=#{invite.token}"
        IO.puts("Invite created. Registration URL:\n\n  #{url}\n")
        :ok

      {:error, reason} ->
        IO.puts("Failed to create invite: #{inspect(reason)}")
        System.halt(1)
    end
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

  @doc """
  Sets (creates/resets) the password for an existing user, found by email. Useful when email
  delivery is down and the normal "forgot password" flow can't reach the user.

  Pass a password, or omit it to have a strong one generated and printed. All of the user's
  existing sessions/tokens are invalidated on change (standard phx.gen.auth behaviour).

      bin/feed_pug eval 'FeedPug.Release.set_password("user@example.com", "a-long-passphrase")'
      bin/feed_pug eval 'FeedPug.Release.set_password("user@example.com")'   # generates one
      # or:  bin/set-password user@example.com [password]
  """
  def set_password(email, password \\ nil) when is_binary(email) do
    load_app()

    {password, generated?} =
      case password do
        nil -> {random_password(), true}
        p when is_binary(p) -> {p, false}
      end

    {:ok, result, _} =
      Ecto.Migrator.with_repo(FeedPug.Repo, fn _repo ->
        case FeedPug.Accounts.get_user_by_email(email) do
          nil -> {:error, :not_found}
          user -> FeedPug.Accounts.update_user_password(user, %{password: password})
        end
      end)

    case result do
      {:ok, {_user, _expired_tokens}} ->
        IO.puts("✓ password set for #{email}")
        if generated?, do: IO.puts("\n  generated password: #{password}\n")
        :ok

      {:error, :not_found} ->
        IO.puts("No user found with email #{inspect(email)}")
        System.halt(1)

      {:error, %Ecto.Changeset{} = changeset} ->
        IO.puts("Failed to set password:\n#{format_errors(changeset)}")
        System.halt(1)
    end
  end

  # A strong, URL-safe random password comfortably above the 12-char minimum.
  defp random_password do
    :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
  end

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("\n", fn {field, msgs} -> "  #{field}: #{Enum.join(msgs, ", ")}" end)
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
