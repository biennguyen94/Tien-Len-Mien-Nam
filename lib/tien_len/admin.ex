defmodule TienLen.Admin do
  @moduledoc """
  Administration (decisions AD1–AD9, interpretations F1–F8).

  **Every function that changes something takes the acting admin's id and re-reads that user
  from the database first**: only an unlocked admin may act (`{:error, :forbidden}` otherwise),
  whatever the UI shows. Every change is written to the append-only audit log (AD2).

  The first admin is created with `promote/1`, a server-side command only (AD1):

      docker exec tien-len bin/tien_len rpc 'TienLen.Admin.promote("username")'
  """

  import Ecto.Query

  alias TienLen.{Accounts, Economy, Lobby, Repo, RoomServer, Settings, Stats}
  alias TienLen.Accounts.User
  alias TienLen.Admin.Action
  alias TienLen.Economy.CoinTransaction
  alias TienLen.Stats.GameRecord

  # -- authorization and audit ----------------------------------------------------

  @doc "Server command (AD1): makes `username` an admin. Audited with no acting admin."
  def promote(username) when is_binary(username) do
    case Repo.get_by(User, username: String.downcase(String.trim(username))) do
      nil ->
        {:error, :not_found}

      user ->
        {:ok, user} = user |> Ecto.Changeset.change(role: "admin") |> Repo.update()
        audit(nil, "promote_server", user.id, %{})
        {:ok, user}
    end
  end

  @doc "`{:ok, admin}` if `admin_id` is an unlocked admin right now, else `{:error, :forbidden}`."
  def authorize(admin_id) do
    case Accounts.get_user(admin_id) do
      %User{} = user -> if User.admin?(user), do: {:ok, user}, else: {:error, :forbidden}
      nil -> {:error, :forbidden}
    end
  end

  defp audit(admin_id, action, target_id, details, reason \\ nil) do
    Repo.insert!(%Action{
      admin_id: admin_id,
      action: action,
      target_user_id: target_id,
      details: details,
      reason: reason
    })
  end

  @doc "The audit log, newest first, with admin and target names."
  def actions(limit \\ 100) do
    from(a in Action,
      left_join: ad in assoc(a, :admin),
      left_join: t in assoc(a, :target_user),
      order_by: [desc: a.id],
      limit: ^limit,
      select: %{
        id: a.id,
        action: a.action,
        details: a.details,
        reason: a.reason,
        inserted_at: a.inserted_at,
        admin: ad.username,
        target: t.username
      }
    )
    |> Repo.all()
  end

  # -- roles (AD1, F1) --------------------------------------------------------------

  @doc "An admin gives or removes admin rights. Nobody removes their own; the last admin stays."
  def set_admin(admin_id, target_id, admin?) do
    with {:ok, admin} <- authorize(admin_id),
         {:ok, target} <- fetch(target_id),
         :ok <- check_role_change(admin, target, admin?) do
      role = if admin?, do: "admin", else: "player"
      {:ok, target} = target |> Ecto.Changeset.change(role: role) |> Repo.update()
      audit(admin.id, if(admin?, do: "set_admin", else: "remove_admin"), target.id, %{})
      notify(target.id, {:role_changed, role})
      {:ok, target}
    end
  end

  defp check_role_change(_admin, %User{role: "admin"}, true), do: {:error, :already_admin}
  defp check_role_change(_admin, %User{role: "player"}, false), do: {:error, :not_admin}
  defp check_role_change(%User{id: id}, %User{id: id}, false), do: {:error, :cannot_demote_self}

  defp check_role_change(_admin, _target, false) do
    if Repo.aggregate(from(u in User, where: u.role == "admin"), :count) <= 1,
      do: {:error, :last_admin},
      else: :ok
  end

  defp check_role_change(_admin, _target, true), do: :ok

  # -- users (AD4, F2–F4) ---------------------------------------------------------

  @doc "Search by username or display name (case-insensitive), newest first."
  def search_users(query, limit \\ 50) do
    q = "%" <> String.replace(String.trim(query || ""), ~w(% _ \\), &("\\" <> &1)) <> "%"

    from(u in User,
      where: ilike(u.username, ^q) or ilike(u.display_name, ^q),
      order_by: [desc: u.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc "A user with their standing, recent games and ledger."
  def user_detail(id) do
    case Accounts.get_user(id) do
      nil ->
        nil

      user ->
        %{
          user: user,
          standing: Stats.user_standing(user.id),
          games: Stats.history(user.id, 20),
          ledger: Economy.history(user.id, 50)
        }
    end
  end

  @doc "Locks an account (F2): no login, open pages logged out at once, removed from rooms."
  def lock(admin_id, target_id, reason \\ nil) do
    with {:ok, admin} <- authorize(admin_id),
         {:ok, target} <- fetch(target_id),
         :ok <- if(target.id == admin.id, do: {:error, :cannot_lock_self}, else: :ok),
         :ok <- if(target.role == "admin", do: {:error, :cannot_lock_admin}, else: :ok),
         :ok <- if(User.locked?(target), do: {:error, :already_locked}, else: :ok) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, target} = target |> Ecto.Changeset.change(locked_at: now) |> Repo.update()
      audit(admin.id, "lock", target.id, %{}, reason)
      notify(target.id, {:force_logout})
      kick_everywhere(target.id)
      {:ok, target}
    end
  end

  @doc "Unlocks an account."
  def unlock(admin_id, target_id) do
    with {:ok, admin} <- authorize(admin_id),
         {:ok, target} <- fetch(target_id),
         :ok <- if(User.locked?(target), do: :ok, else: {:error, :not_locked}) do
      {:ok, target} = target |> Ecto.Changeset.change(locked_at: nil) |> Repo.update()
      audit(admin.id, "unlock", target.id, %{})
      {:ok, target}
    end
  end

  @doc "Renames a user's display name (moderation)."
  def rename(admin_id, target_id, name) do
    with {:ok, admin} <- authorize(admin_id),
         {:ok, target} <- fetch(target_id),
         {:ok, renamed} <- Accounts.change_display_name(target, name) do
      audit(admin.id, "rename", target.id, %{from: target.display_name, to: renamed.display_name})
      {:ok, renamed}
    end
  end

  @doc """
  Resets a password (F3): returns `{:ok, temporary_password}`, to be shown once to the admin.
  The password itself is never stored in the audit log.
  """
  def reset_password(admin_id, target_id) do
    with {:ok, admin} <- authorize(admin_id),
         {:ok, target} <- fetch(target_id) do
      temporary = :crypto.strong_rand_bytes(9) |> Base.url_encode64(padding: false)
      {:ok, _} = Accounts.set_password(target, temporary)
      audit(admin.id, "reset_password", target.id, %{})
      {:ok, temporary}
    end
  end

  @doc "Adds or removes coins with a reason of 3–200 characters (AD5, F4)."
  def adjust_coins(admin_id, target_id, amount, reason) do
    reason = String.trim(to_string(reason || ""))

    with {:ok, admin} <- authorize(admin_id),
         {:ok, target} <- fetch(target_id),
         :ok <- if(is_integer(amount) and amount != 0, do: :ok, else: {:error, :invalid_amount}),
         :ok <- if(String.length(reason) in 3..200, do: :ok, else: {:error, :reason_required}),
         {:ok, balance} <- Economy.adjust(target.id, amount, reason, admin.id) do
      audit(admin.id, "adjust_coins", target.id, %{amount: amount, balance: balance}, reason)
      {:ok, balance}
    end
  end

  # -- rooms and games (AD3, AD6–AD8, F5, F6) --------------------------------------

  @doc "Dashboard numbers (AD3)."
  def dashboard(today \\ Economy.vn_today()) do
    {day_start, _} = vn_day_bounds(today)
    week_start = DateTime.add(day_start, -6 * 86_400, :second)
    rooms = Lobby.list_rooms()

    %{
      users: Repo.aggregate(User, :count),
      registrations_today:
        Repo.aggregate(from(u in User, where: u.inserted_at >= ^day_start), :count),
      locked: Repo.aggregate(from(u in User, where: not is_nil(u.locked_at)), :count),
      admins: Repo.aggregate(from(u in User, where: u.role == "admin"), :count),
      rooms: length(rooms),
      rooms_playing: Enum.count(rooms, &(&1.status == :playing)),
      players_in_rooms: Enum.sum_by(rooms, & &1.players),
      games_today:
        Repo.aggregate(from(g in GameRecord, where: g.finished_at >= ^day_start), :count),
      games_7_days:
        Repo.aggregate(from(g in GameRecord, where: g.finished_at >= ^week_start), :count),
      coins_in_circulation:
        Repo.one(from(u in User, select: type(coalesce(sum(u.coins), 0), :integer)))
    }
  end

  defp vn_day_bounds(date) do
    {:ok, start} = DateTime.new(date, ~T[00:00:00], "Etc/UTC")
    start = DateTime.add(start, -7 * 3600, :second)
    {start, DateTime.add(start, 86_400, :second)}
  end

  @doc "Open rooms with their summaries."
  def rooms, do: Lobby.list_rooms()

  @doc "The watch view of a room, with every hand (AD7). Admins only."
  def watch(admin_id, room_id) do
    with {:ok, _admin} <- authorize(admin_id) do
      case RoomServer.admin_view(room_id) do
        {:error, _} = error -> error
        view -> {:ok, view}
      end
    end
  end

  @doc "Closes a room; a running game is cancelled without coins or stats (AD6, F5)."
  def close_room(admin_id, room_id, reason \\ nil) do
    with {:ok, admin} <- authorize(admin_id),
         :ok <- RoomServer.admin_close(room_id) do
      audit(admin.id, "close_room", nil, %{room_id: room_id}, reason)
      :ok
    end
  end

  @doc "Removes a player from a room; they cannot come back to it (AD6)."
  def kick(admin_id, room_id, player_id, reason \\ nil) do
    with {:ok, admin} <- authorize(admin_id),
         :ok <- RoomServer.kick(room_id, player_id) do
      audit(
        admin.id,
        "kick",
        if(is_integer(player_id), do: player_id),
        %{room_id: room_id},
        reason
      )

      :ok
    end
  end

  defp kick_everywhere(player_id) do
    for %{id: room_id} <- Lobby.list_rooms(), do: RoomServer.kick(room_id, player_id)
    :ok
  end

  @doc """
  Recent games (AD8), newest first, with players and the coin transfers made for them (ledger
  lines whose ref starts with the game's ref).
  """
  def games(limit \\ 50) do
    games =
      from(g in GameRecord,
        order_by: [desc: g.id],
        limit: ^limit,
        preload: [players: [:user]]
      )
      |> Repo.all()

    refs = games |> Enum.map(& &1.ref) |> Enum.reject(&is_nil/1)

    transfers =
      if refs == [] do
        []
      else
        patterns = Enum.map(refs, &(&1 <> ":%"))

        from(t in CoinTransaction,
          join: u in assoc(t, :user),
          join: c in assoc(t, :counterparty),
          where: t.amount > 0 and fragment("? LIKE ANY(?)", t.ref, ^patterns),
          order_by: t.id,
          select: %{
            ref: t.ref,
            to: u.display_name,
            from: c.display_name,
            amount: t.amount,
            reason: t.reason
          }
        )
        |> Repo.all()
      end

    Enum.map(games, fn g ->
      %{
        game: g,
        players: Enum.sort_by(g.players, &{&1.place, &1.seat}),
        transfers: Enum.filter(transfers, &(g.ref && String.starts_with?(&1.ref, g.ref <> ":")))
      }
    end)
  end

  # -- settings (AD9, F7) -----------------------------------------------------------

  @doc "Saves economy settings: non-negative integers (`max_rooms` ≥ 1)."
  def update_settings(admin_id, params) do
    with {:ok, admin} <- authorize(admin_id),
         {:ok, values} <- validate_settings(params) do
      old = Map.new(values, fn {k, _} -> {k, Settings.int(k)} end)
      Enum.each(values, fn {k, v} -> Settings.put(k, v) end)
      audit(admin.id, "update_settings", nil, %{from: old, to: values})
      {:ok, values}
    end
  end

  defp validate_settings(params) do
    Settings.economy_defaults()
    |> Map.keys()
    |> Enum.reduce_while({:ok, %{}}, fn key, {:ok, acc} ->
      case params[key] do
        nil ->
          {:cont, {:ok, acc}}

        raw ->
          min = if key == "max_rooms", do: 1, else: 0

          case Integer.parse(String.trim(to_string(raw))) do
            {n, ""} when n >= min and n <= 1_000_000_000_000 ->
              {:cont, {:ok, Map.put(acc, key, n)}}

            _ ->
              {:halt, {:error, {:invalid_setting, key}}}
          end
      end
    end)
  end

  @doc "Sets (or clears, with an empty text) the lobby announcement, up to 300 characters."
  def announce(admin_id, text) do
    text = String.trim(to_string(text || ""))

    with {:ok, admin} <- authorize(admin_id),
         :ok <- if(String.length(text) <= 300, do: :ok, else: {:error, :announcement_too_long}) do
      if text == "", do: Settings.delete("announcement"), else: Settings.put("announcement", text)
      audit(admin.id, "announce", nil, %{text: text})
      :ok
    end
  end

  # -- helpers ----------------------------------------------------------------------

  defp fetch(id) do
    case Accounts.get_user(id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc "Topic of messages for one user's open pages (`{:force_logout}`, `{:role_changed, role}`)."
  def user_topic(user_id), do: "user:#{user_id}"

  defp notify(user_id, message),
    do: Phoenix.PubSub.broadcast(TienLen.PubSub, user_topic(user_id), message)
end
