defmodule TienLen.Accounts do
  @moduledoc "Player accounts: registration, authentication, display name (A2, A3)."

  import Ecto.Query

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

  @doc "Sets a new password (validated like registration)."
  def set_password(%User{} = user, password) do
    user |> User.password_changeset(%{password: password}) |> Repo.update()
  end

  @doc "The player changes their own password; the current one must be right (F3)."
  def change_password(%User{} = user, current, new) do
    if User.valid_password?(user, current),
      do: set_password(user, new),
      else: {:error, :wrong_password}
  end

  @doc "The user if it exists and is not locked (sessions of locked users are ignored, F2)."
  def get_active_user(id) do
    case get_user(id) do
      %User{} = user -> if User.locked?(user), do: nil, else: user
      nil -> nil
    end
  end

  @doc "Changes the display name."
  def change_display_name(%User{} = user, name) do
    user |> User.display_name_changeset(%{display_name: name}) |> Repo.update()
  end

  @doc "The player's \"Không nhận lời mời\" setting (G9): `accept?` false turns invites off."
  def set_accept_invites(%User{} = user, accept?) when is_boolean(accept?) do
    user |> Ecto.Changeset.change(accept_invites: accept?) |> Repo.update()
  end

  @doc "Of `ids`, those whose owners do not accept invites (G9)."
  def invites_off(ids) do
    Repo.all(from u in User, where: u.id in ^ids and not u.accept_invites, select: u.id)
  end

  # P3: a fixed set of avatars (no uploads)
  @avatars ~w(🐯 🐉 🦊 🐼 🐸 🐙 🦁 🐵 🐧 🐢 🦄 🐝 🐬 🦉 🐺 🐨 🐮 🐷 🐰 🐻)

  @doc "Avatars a player can choose (P3)."
  def avatars, do: @avatars

  @doc "Sets the player's avatar; only one of `avatars/0`."
  def set_avatar(%User{} = user, avatar) do
    if avatar in @avatars,
      do: user |> Ecto.Changeset.change(avatar: avatar) |> Repo.update(),
      else: {:error, :invalid_avatar}
  end

  @doc "A user by username (case-insensitive), or `nil`."
  def get_by_username(username) when is_binary(username),
    do: Repo.get_by(User, username: String.downcase(String.trim(username)))

  def get_by_username(_), do: nil

  @doc "Unlocked users whose username or display name contains `q` (at most 10)."
  def search(q) when is_binary(q) do
    q = String.trim(q)

    if String.length(q) < 2 do
      []
    else
      like = "%" <> String.replace(q, ~r/[\\%_]/, &("\\" <> &1)) <> "%"

      Repo.all(
        from u in User,
          where:
            is_nil(u.locked_at) and (ilike(u.username, ^like) or ilike(u.display_name, ^like)),
          order_by: u.username,
          limit: 10
      )
    end
  end

  def search(_), do: []
end
