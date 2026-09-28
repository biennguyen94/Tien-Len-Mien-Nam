defmodule TienLen.Accounts do
  @moduledoc "Player accounts: registration, authentication, display name (A2, A3)."

  alias TienLen.Accounts.User
  alias TienLen.Repo

  @doc "Registers a user. Returns `{:ok, user}` or `{:error, changeset}`."
  def register_user(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.registration_changeset(%User{}, attrs))
    # the starting coins commit together with the account (T19)
    |> TienLen.Economy.grant_starting_coins()
    |> Repo.transaction()
    |> case do
      {:ok, %{starting_coins: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc "Changeset for the registration form (no hashing needed for display)."
  def change_registration(user \\ %User{}, attrs \\ %{}),
    do: User.registration_changeset(user, attrs)

  @doc """
  The user with this username and password, or `nil`. Username case is ignored. Takes the same
  time whether or not the user exists (no account enumeration by timing).
  """
  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username |> String.trim() |> String.downcase())
    if User.valid_password?(user, password), do: user
  end

  def authenticate(_username, _password) do
    User.valid_password?(nil, nil)
    nil
  end

  @doc "A user by id, or `nil`."
  def get_user(id) when is_integer(id), do: Repo.get(User, id)
  def get_user(_), do: nil

  @doc "Changes the display name."
  def change_display_name(%User{} = user, name) do
    user |> User.display_name_changeset(%{display_name: name}) |> Repo.update()
  end
end
