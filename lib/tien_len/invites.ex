defmodule TienLen.Invites do
  @moduledoc """
  Invites to a room (decisions IV1, IV3; interpretation G8, G9). In memory only.

  - Any player seated in a **waiting** room may invite an **online** player who is not in a
    room and accepts invites (`users.accept_invites`, G9).
  - At most **one pending invite per target**, **10 invites per minute per inviter**; an
    invite expires after **60 s**.
  - The target gets `{:invite, invite}` on their user topic (every open page shows the popup)
    and `{:invite_gone, id}` when it is answered or expires. The inviter gets
    `{:invite_answer, :accepted | :declined | :expired, target_name}`.
  - `accept/2` re-checks the room (still waiting, a free seat) and the target's coins; the seat
    itself is taken by the room page, which re-checks everything again (kicked, full…).
  """

  use GenServer

  alias TienLen.{Accounts, Economy, Presence, RateLimit, Room, RoomServer}

  @ttl 60_000
  @per_minute 10

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Invites `to_id` to `room_id` on behalf of the seated player `from_id`."
  def invite(from_id, to_id, room_id) do
    with :ok <- if(from_id == to_id, do: {:error, :not_found}, else: :ok),
         {:ok, from} <- active(from_id),
         {:ok, to} <- target(to_id),
         {:ok, summary} <- room(room_id, from_id),
         :ok <- rate(from_id) do
      GenServer.call(__MODULE__, {:invite, from, to, summary})
    end
  end

  @doc "The pending invite of a player, or `nil`."
  def pending(to_id), do: GenServer.call(__MODULE__, {:pending, to_id})

  @doc "Accepts: `{:ok, room_id}` after re-checking the room and the coins."
  def accept(to_id, invite_id) do
    with {:ok, invite} <- GenServer.call(__MODULE__, {:take, to_id, invite_id, :accepted}) do
      case recheck(to_id, invite.room_id) do
        :ok -> {:ok, invite.room_id}
        error -> error
      end
    end
  end

  @doc "Declines the pending invite."
  def decline(to_id, invite_id) do
    with {:ok, _} <- GenServer.call(__MODULE__, {:take, to_id, invite_id, :declined}), do: :ok
  end

  @doc """
  Players the seated `user_id` could invite: `[%{id, name, avatar, invites_off, friend}]` (G9),
  friends first (FR4).
  """
  def candidates(user_id) do
    users =
      Enum.filter(
        Presence.online_users(),
        &(&1.id != user_id and &1.place in ["lobby", "other", "watching"])
      )

    off = users |> Enum.map(& &1.id) |> Accounts.invites_off() |> MapSet.new()
    friends = TienLen.Friends.friend_ids(user_id)

    users
    |> Enum.map(
      &%{
        id: &1.id,
        name: &1.name,
        avatar: &1.avatar,
        invites_off: MapSet.member?(off, &1.id),
        friend: MapSet.member?(friends, &1.id)
      }
    )
    |> Enum.sort_by(&(not &1.friend))
  end

  # -- checks -------------------------------------------------------------------------

  defp active(id) do
    case Accounts.get_active_user(id) do
      nil -> {:error, :forbidden}
      user -> {:ok, user}
    end
  end

  defp target(id) do
    with {:ok, user} <- active(id) do
      case Presence.get_user(id) do
        nil -> {:error, :not_online}
        %{place: place} when place in ["room", "playing"] -> {:error, :target_busy}
        _ -> if user.accept_invites, do: {:ok, user}, else: {:error, :invites_off}
      end
    end
  end

  defp room(room_id, from_id) do
    case RoomServer.seated?(room_id, from_id) do
      true ->
        case RoomServer.summary(room_id) do
          %{status: :waiting, players: n} = s when n < 4 -> {:ok, s}
          %{status: :playing} -> {:error, :game_in_progress}
          %{} -> {:error, :room_full}
          error -> error
        end

      false ->
        {:error, :not_in_room}

      error ->
        error
    end
  end

  defp rate(from_id) do
    case RateLimit.hit({:invite, from_id}, @per_minute, 60_000) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :invite_too_fast}
    end
  end

  defp recheck(to_id, room_id) do
    case RoomServer.summary(room_id) do
      %{status: :playing} ->
        {:error, :game_in_progress}

      %{players: n} when n >= 4 ->
        {:error, :room_full}

      %{stake: stake} ->
        if Economy.balance(to_id) >= Room.min_balance(%Room{stake: stake}),
          do: :ok,
          else: {:error, :not_enough_coins_to_join}

      error ->
        error
    end
  end

  # -- server -------------------------------------------------------------------------

  @impl true
  def init(opts), do: {:ok, %{by_target: %{}, ttl: Keyword.get(opts, :ttl, @ttl)}}

  @impl true
  def handle_call({:invite, from, to, summary}, _from, state) do
    if Map.has_key?(state.by_target, to.id) do
      {:reply, {:error, :invite_pending}, state}
    else
      invite = %{
        id: System.unique_integer([:positive]),
        from_id: from.id,
        from_name: from.display_name,
        to_id: to.id,
        to_name: to.display_name,
        room_id: summary.id,
        stake: summary.stake,
        private: Map.get(summary, :private, false)
      }

      Process.send_after(self(), {:expire, to.id, invite.id}, state.ttl)
      notify(to.id, {:invite, invite})
      {:reply, {:ok, invite}, %{state | by_target: Map.put(state.by_target, to.id, invite)}}
    end
  end

  def handle_call({:pending, to_id}, _from, state),
    do: {:reply, Map.get(state.by_target, to_id), state}

  def handle_call({:take, to_id, invite_id, answer}, _from, state) do
    case state.by_target do
      %{^to_id => %{id: ^invite_id} = invite} ->
        answered(invite, answer)
        {:reply, {:ok, invite}, %{state | by_target: Map.delete(state.by_target, to_id)}}

      _ ->
        {:reply, {:error, :invite_expired}, state}
    end
  end

  @impl true
  def handle_info({:expire, to_id, invite_id}, state) do
    case state.by_target do
      %{^to_id => %{id: ^invite_id} = invite} ->
        answered(invite, :expired)
        {:noreply, %{state | by_target: Map.delete(state.by_target, to_id)}}

      _ ->
        {:noreply, state}
    end
  end

  defp answered(invite, answer) do
    notify(invite.to_id, {:invite_gone, invite.id})
    notify(invite.from_id, {:invite_answer, answer, invite.to_name})
  end

  defp notify(user_id, msg),
    do: Phoenix.PubSub.broadcast(TienLen.PubSub, TienLen.Admin.user_topic(user_id), msg)
end
