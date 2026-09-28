defmodule TienLen.Accounts.User do
  @moduledoc """
  A player account (decisions A2, A3; interpretation Y1).

  - `username`: 3–20 characters `a–z 0–9 _ .`, stored lowercase, unique.
  - `display_name`: shown at the table; same rules as before (`TienLen.Lobby.normalize_name/1`).
  - `password`: 8–72 bytes (bcrypt's limit), stored only as a bcrypt hash.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :username, :string
    field :display_name, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    # coins (C1–C10): changed only by TienLen.Economy, never cast from user input
    field :coins, :integer, default: 0
    field :daily_bonus_on, :date
    field :relief_on, :date
    # admin (AD1, F2): changed only by TienLen.Admin, never cast from user input
    field :role, :string, default: "player"
    field :locked_at, :utc_datetime
    # G9: the player's own setting; G12: set only by TienLen.Admin
    field :accept_invites, :boolean, default: true
    field :muted_until, :utc_datetime
    # P3: one of TienLen.Accounts.avatars/0, chosen by the player
    field :avatar, :string

    timestamps type: :utc_datetime
  end

  @username ~r/^[a-z0-9_.]{3,20}$/

  @doc "Changeset for registration: validates all three fields and hashes the password."
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name, :username, :password])
    |> validate_display_name()
    |> validate_username()
    |> validate_password()
    |> hash_password()
  end

  @doc "Changeset for a new password (reset by an admin or changed by the player, F3)."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_password()
    |> hash_password()
  end

  @doc "True if the account is locked (F2)."
  def locked?(%__MODULE__{locked_at: nil}), do: false
  def locked?(%__MODULE__{}), do: true

  @doc "True while an admin mute is running (G12)."
  def muted?(user, now \\ DateTime.utc_now())
  def muted?(%__MODULE__{muted_until: nil}, _now), do: false
  def muted?(%__MODULE__{muted_until: until}, now), do: DateTime.compare(until, now) == :gt

  @doc "True for an unlocked admin (AD1)."
  def admin?(%__MODULE__{role: "admin"} = user), do: not locked?(user)
  def admin?(_), do: false

  @doc "Changeset for changing the display name."
  def display_name_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name])
    |> validate_display_name()
  end

  @doc "Checks a password against the stored hash (constant-time)."
  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and is_binary(password) and byte_size(password) > 0,
      do: Bcrypt.verify_pass(password, hash)

  def valid_password?(_user, _password) do
    Bcrypt.no_user_verify()
    false
  end

  defp validate_display_name(changeset) do
    changeset
    |> validate_required([:display_name], message: "Hãy nhập tên hiển thị")
    |> then(fn cs ->
      case get_change(cs, :display_name) do
        nil ->
          cs

        name ->
          case TienLen.Lobby.normalize_name(name) do
            {:ok, name} -> put_change(cs, :display_name, name)
            {:error, _} -> add_error(cs, :display_name, "Tên hiển thị phải có 1–20 ký tự")
          end
      end
    end)
  end

  defp validate_username(changeset) do
    changeset
    |> update_change(:username, &(&1 |> String.trim() |> String.downcase()))
    |> validate_required([:username], message: "Hãy nhập tên tài khoản")
    |> validate_format(:username, @username,
      message: "Tài khoản gồm 3–20 ký tự: chữ a–z, số, dấu _ hoặc ."
    )
    |> unsafe_validate_unique(:username, TienLen.Repo, message: "Tài khoản này đã có người dùng")
    |> unique_constraint(:username, message: "Tài khoản này đã có người dùng")
  end

  defp validate_password(changeset) do
    changeset
    |> validate_required([:password], message: "Hãy nhập mật khẩu")
    |> validate_length(:password, min: 8, message: "Mật khẩu phải có ít nhất 8 ký tự")
    |> validate_length(:password,
      max: 72,
      count: :bytes,
      message: "Mật khẩu quá dài (tối đa 72 byte)"
    )
  end

  defp hash_password(changeset) do
    password = get_change(changeset, :password)

    if changeset.valid? and password do
      changeset
      |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(password))
      |> delete_change(:password)
    else
      changeset
    end
  end
end
