defmodule FeedPug.Accounts.ApiToken do
  @moduledoc """
  A long-lived bearer token a user generates to authenticate API/mobile clients
  (the device-pairing flow). Distinct from the short-lived session tokens used
  by the browser.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_tokens" do
    field :token, :string
    field :label, :string
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :user, FeedPug.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:token, :label, :expires_at, :user_id])
    |> validate_required([:token, :user_id])
    |> unique_constraint(:token)
  end
end
