defmodule FeedPug.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias FeedPug.Repo

  alias FeedPug.Accounts.{User, UserToken, UserNotifier, ApiToken, Scope, Invite}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    changeset = User.email_changeset(%User{}, attrs)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, changeset)
    |> FeedPug.Groups.seed_default_groups_multi()
    |> FeedPug.Reactions.seed_default_reactions_multi()
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _changes} -> {:error, changeset}
    end
  end

  ## API tokens

  @doc "Lists a user's API tokens, newest first."
  def list_api_tokens(%Scope{user: user}) do
    from(t in ApiToken, where: t.user_id == ^user.id, order_by: [desc: t.inserted_at])
    |> Repo.all()
  end

  @doc """
  Creates an API token for the scoped user. `opts` may include `:label` and
  `:expires_in_days`. Returns `{:ok, %ApiToken{}}` with the cleartext `token`.
  """
  def create_api_token(%Scope{user: user}, opts \\ []) do
    expires_at =
      case Keyword.get(opts, :expires_in_days) do
        days when is_integer(days) and days > 0 ->
          DateTime.utc_now() |> DateTime.add(days * 86_400, :second) |> DateTime.truncate(:second)

        _ ->
          nil
      end

    %ApiToken{}
    |> ApiToken.changeset(%{
      token: generate_api_token(),
      label: opts |> Keyword.get(:label) |> normalize_label(),
      expires_at: expires_at,
      user_id: user.id
    })
    |> Repo.insert()
  end

  def delete_api_token(%Scope{user: user}, id) do
    case Repo.get_by(ApiToken, id: id, user_id: user.id) do
      nil -> {:error, :not_found}
      token -> Repo.delete(token)
    end
  end

  @doc """
  Resolves the active user for a bearer token, bumping `last_used_at`. Returns
  `nil` for unknown or expired tokens.
  """
  def fetch_user_by_api_token(token) when is_binary(token) do
    now = DateTime.utc_now()

    case Repo.get_by(ApiToken, token: token) do
      nil ->
        nil

      %ApiToken{expires_at: exp} when not is_nil(exp) ->
        if DateTime.compare(exp, now) == :gt, do: touch_and_user(token, now), else: nil

      %ApiToken{} ->
        touch_and_user(token, now)
    end
  end

  def fetch_user_by_api_token(_), do: nil

  defp touch_and_user(token, now) do
    {_n, _} =
      from(t in ApiToken, where: t.token == ^token)
      |> Repo.update_all(set: [last_used_at: DateTime.truncate(now, :second)])

    Repo.one(from(t in ApiToken, where: t.token == ^token, join: u in assoc(t, :user), select: u))
  end

  defp generate_api_token do
    "fp_" <> (:crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false))
  end

  defp normalize_label(nil), do: nil

  defp normalize_label(label) when is_binary(label) do
    case String.trim(label) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  ## Invites

  @doc """
  Returns true when public registration is open. When false, registration
  requires a valid invite token.
  """
  @spec registration_open?() :: boolean()
  def registration_open? do
    Application.get_env(:feed_pug, :registration_open, false) == true
  end

  @doc "Creates an invite token, owned by the given user."
  def create_invite(%User{id: id}, attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("created_by_id", id)

    %Invite{}
    |> Invite.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates an unowned (system) invite — used to bootstrap the first account when
  registration is gated and there is no logged-in user yet.
  """
  def create_system_invite(attrs \\ %{}) do
    attrs =
      attrs
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.delete("created_by_id")

    %Invite{}
    |> Invite.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc "Lists invites created by a user, newest first, with the redeemer preloaded."
  def list_invites(%User{id: id}) do
    from(i in Invite,
      where: i.created_by_id == ^id,
      order_by: [desc: i.inserted_at],
      preload: [:consumed_by]
    )
    |> Repo.all()
  end

  @doc "Looks up an invite by token and returns it if active."
  @spec get_active_invite(binary()) :: Invite.t() | nil
  def get_active_invite(token) when is_binary(token) do
    case Repo.get_by(Invite, token: token) do
      nil -> nil
      invite -> if Invite.active?(invite), do: invite, else: nil
    end
  end

  def get_active_invite(_), do: nil

  @doc "Marks an invite as consumed by the given user."
  def consume_invite(%Invite{} = invite, %User{} = user) do
    invite
    |> Invite.consume_changeset(user)
    |> Repo.update()
  end

  @doc "Revokes an unused invite the user owns (stamps consumed_at, no consumer)."
  def revoke_invite(%User{id: owner_id}, %Invite{created_by_id: owner_id} = invite) do
    invite
    |> Ecto.Changeset.change(
      consumed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      consumed_by_id: nil
    )
    |> Repo.update()
  end

  def revoke_invite(_, _), do: {:error, :forbidden}

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `FeedPug.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `FeedPug.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
