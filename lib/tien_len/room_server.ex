defmodule TienLen.RoomServer do
  @moduledoc """
  One process per room (RULES T13, T15, T16, T17).

  - **Serialises** every command for the room, so near-simultaneous commands (e.g. two
    out-of-turn four-pairs) are applied in arrival order and the first valid one wins.
  - **Turn timer** (default 20 s): restarted whenever the turn changes hands or the current
    player acts; on expiry the server acts for the player (`TienLen.Room.turn_timeout/1`).
  - **Connections**: `join/3` monitors the calling process (the player's LiveView). When the
    last process of a player goes down they are marked disconnected, and after the disconnect
    timeout (default 20 s) they are removed from the current game (`Room.disconnect_timeout/2`).
    Joining again with the same player id before that cancels the timer.
  - **Broadcasts** `{:room_updated, room_id, version, events}` on `topic(room_id)` after every
    change. Events are public facts only (plays, passes, joins…); subscribers fetch their own
    projection with `view/2`. Hands, undealt cards and seeds are never broadcast.
  - Stops (`:normal`) when the last player leaves, or when nobody has been connected for the
    disconnect timeout.

  Options for `start_room/1`: `:id`, `:turn_timeout` and `:disconnect_timeout` (ms), `:deals` (a
  list of `TienLen.Room.deal()` used for successive games, for tests; otherwise a fresh
  `TienLen.Deck.new_seed/0` per game).
  """

  use GenServer, restart: :temporary

  alias TienLen.{Deck, Room}

  @turn_timeout 20_000
  @disconnect_timeout 20_000
  # events after which the (possibly same) current player gets a fresh turn timer
  @turn_events [:played, :chopped, :passed, :timed_out, :round_ended, :lead_moved, :game_started]

  # -- API ----------------------------------------------------------------------

  @doc "Starts a room under `TienLen.RoomSupervisor`. Returns `{:ok, room_id}`."
  @spec start_room(keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_room(opts \\ []) do
    id = Keyword.get_lazy(opts, :id, &new_id/0)

    case DynamicSupervisor.start_child(
           TienLen.RoomSupervisor,
           {__MODULE__, Keyword.put(opts, :id, id)}
         ) do
      {:ok, _pid} -> {:ok, id}
      {:error, {:already_started, _pid}} -> {:error, :already_exists}
      error -> error
    end
  end

  @doc false
  def start_link(opts),
    do: GenServer.start_link(__MODULE__, opts, name: via(Keyword.fetch!(opts, :id)))

  @doc "PubSub topic of a room."
  @spec topic(String.t()) :: String.t()
  def topic(room_id), do: "room:" <> room_id

  @doc "Subscribes the caller to a room's updates."
  def subscribe(room_id), do: Phoenix.PubSub.subscribe(TienLen.PubSub, topic(room_id))

  @doc """
  The pid of a running room, or `nil`. The Registry drops a dead process asynchronously, so a
  pid that is no longer alive is treated as absent.
  """
  def whereis(room_id) do
    case Registry.lookup(TienLen.RoomRegistry, room_id) do
      [{pid, _}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  @doc "Seats (or reconnects) `player_id` and monitors the calling process."
  def join(room_id, player_id, name), do: call(room_id, {:join, player_id, name})

  def leave(room_id, player_id), do: call(room_id, {:leave, player_id})
  def start_game(room_id, player_id), do: call(room_id, {:start_game, player_id})
  def play(room_id, player_id, cards), do: call(room_id, {:command, player_id, {:play, cards}})
  def pass(room_id, player_id), do: call(room_id, {:command, player_id, :pass})
  def chop(room_id, player_id, cards), do: call(room_id, {:command, player_id, {:chop, cards}})

  @doc "The room as seen by `player_id`, plus `turn_ms_left` for the current turn."
  def view(room_id, player_id), do: call(room_id, {:view, player_id})

  defp call(room_id, msg) do
    GenServer.call(via(room_id), msg)
  catch
    :exit, {:noproc, _} -> {:error, :room_not_found}
    :exit, {:normal, _} -> {:error, :room_not_found}
  end

  defp via(room_id), do: {:via, Registry, {TienLen.RoomRegistry, room_id}}

  defp new_id, do: :crypto.strong_rand_bytes(5) |> Base.url_encode64(padding: false)

  # -- server -------------------------------------------------------------------

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)

    {:ok,
     %{
       id: id,
       room: Room.new(id),
       version: 0,
       turn_timeout: Keyword.get(opts, :turn_timeout, @turn_timeout),
       disconnect_timeout: Keyword.get(opts, :disconnect_timeout, @disconnect_timeout),
       deals: Keyword.get(opts, :deals, []),
       # %{ref, seat, deadline} of the running turn timer
       turn: nil,
       # player_id => timer ref
       disconnect_timers: %{},
       # monitored pid => {player_id, monitor ref}
       pids: %{}
     }}
  end

  @impl true
  def handle_call({:join, player_id, name}, {pid, _tag}, state) do
    case Room.join(state.room, player_id, name) do
      {:ok, room, seat, events} ->
        state = state |> track(pid, player_id) |> cancel_disconnect_timer(player_id)
        {:reply, {:ok, seat}, changed(state, room, events)}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:leave, player_id}, _from, state) do
    reply_change(state, Room.leave(state.room, player_id), fn state ->
      state |> untrack_player(player_id) |> cancel_disconnect_timer(player_id)
    end)
  end

  def handle_call({:start_game, player_id}, _from, state) do
    {deal, deals} =
      case state.deals do
        [deal | rest] -> {deal, rest}
        [] -> {Deck.new_seed(), []}
      end

    case Room.start_game(state.room, player_id, deal) do
      {:ok, room, events} -> {:reply, :ok, changed(%{state | deals: deals}, room, events)}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:command, player_id, cmd}, _from, state) do
    reply_change(state, Room.command(state.room, player_id, cmd))
  end

  def handle_call({:view, player_id}, _from, state) do
    left =
      case state.turn do
        %{deadline: deadline} -> max(deadline - now(), 0)
        nil -> nil
      end

    {:reply, Map.put(Room.view(state.room, player_id), :turn_ms_left, left), state}
  end

  @impl true
  def handle_info({:DOWN, mref, :process, pid, _reason}, state) do
    case state.pids do
      %{^pid => {player_id, ^mref}} ->
        state = %{state | pids: Map.delete(state.pids, pid)}

        if Enum.any?(state.pids, fn {_pid, {p, _}} -> p == player_id end) do
          {:noreply, state}
        else
          case Room.disconnect(state.room, player_id) do
            {:ok, room, events} ->
              state = start_disconnect_timer(state, player_id)
              {:noreply, changed(state, room, events)}

            {:error, _} ->
              {:noreply, state}
          end
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:disconnect_timeout, player_id, ref}, state) do
    case state.disconnect_timers do
      %{^player_id => ^ref} ->
        state = %{state | disconnect_timers: Map.delete(state.disconnect_timers, player_id)}

        case Room.disconnect_timeout(state.room, player_id) do
          {:ok, room, events} -> state |> changed(room, events) |> maybe_stop()
          {:error, _} -> {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:turn_timeout, ref}, %{turn: %{ref: ref}} = state) do
    state = %{state | turn: nil}

    case Room.turn_timeout(state.room) do
      {:ok, room, events} -> {:noreply, changed(state, room, events)}
      {:error, _} -> {:noreply, state}
    end
  end

  def handle_info({:turn_timeout, _stale}, state), do: {:noreply, state}

  # -- helpers ------------------------------------------------------------------

  defp reply_change(state, result, before \\ & &1)

  defp reply_change(state, {:ok, room, events}, before) do
    state = changed(before.(state), room, events)

    if map_size(room.seats) == 0,
      do: {:stop, :normal, :ok, state},
      else: {:reply, :ok, state}
  end

  defp reply_change(state, {:error, _} = error, _before), do: {:reply, error, state}

  defp maybe_stop(state) do
    if Enum.any?(state.room.seats, fn {_seat, p} -> p.connected end),
      do: {:noreply, state},
      else: {:stop, :normal, state}
  end

  # Applies a new room, reschedules the turn timer and broadcasts the public events.
  defp changed(state, room, events) do
    state = %{state | room: room, version: state.version + 1} |> reschedule_turn(events)

    Phoenix.PubSub.broadcast(
      TienLen.PubSub,
      topic(state.id),
      {:room_updated, state.id, state.version, events}
    )

    state
  end

  defp reschedule_turn(state, events) do
    current = Room.current_seat(state.room)
    running = state.turn && state.turn.seat
    new_turn? = Enum.any?(events, &(elem(&1, 0) in @turn_events))

    cond do
      current == nil ->
        cancel_turn(state)

      current != running or new_turn? ->
        state = cancel_turn(state)
        ref = make_ref()
        Process.send_after(self(), {:turn_timeout, ref}, state.turn_timeout)
        %{state | turn: %{ref: ref, seat: current, deadline: now() + state.turn_timeout}}

      true ->
        state
    end
  end

  # Timer messages carry a ref and are checked on arrival, so a cancelled timer that already
  # fired is ignored as stale.
  defp cancel_turn(state), do: %{state | turn: nil}

  defp start_disconnect_timer(state, player_id) do
    ref = make_ref()
    Process.send_after(self(), {:disconnect_timeout, player_id, ref}, state.disconnect_timeout)
    %{state | disconnect_timers: Map.put(state.disconnect_timers, player_id, ref)}
  end

  defp cancel_disconnect_timer(state, player_id),
    do: %{state | disconnect_timers: Map.delete(state.disconnect_timers, player_id)}

  defp track(state, pid, player_id) do
    if Map.has_key?(state.pids, pid) do
      state
    else
      %{state | pids: Map.put(state.pids, pid, {player_id, Process.monitor(pid)})}
    end
  end

  defp untrack_player(state, player_id) do
    {gone, kept} = Enum.split_with(state.pids, fn {_pid, {p, _}} -> p == player_id end)
    Enum.each(gone, fn {_pid, {_p, mref}} -> Process.demonitor(mref, [:flush]) end)
    %{state | pids: Map.new(kept)}
  end

  defp now, do: System.monotonic_time(:millisecond)
end
