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
  - Stops (`:normal`) when the last player leaves, when nobody has been connected for the
    disconnect timeout, or when nobody joins within that time after creation (X9).
  - Tells the lobby (`TienLen.Lobby.topic/0`) when its summary may have changed
    (`{:lobby_updated, id}`) and when it closes (`{:room_closed, id}`).
  - `view/2` answers only seated players; spectators use `watch/1` and `spectator_view/1` (V1).
  - After every change the commentator (`TienLen.Commentary`, BL1) may post lines in the room
    chat; players can throw items at each other (`throw/4`, TH1).

  Options for `start_room/1`: `:id`, `:turn_timeout` and `:disconnect_timeout` (ms), `:deals` (a
  list of `TienLen.Room.deal()` used for successive games, for tests; otherwise a fresh
  `TienLen.Deck.new_seed/0` per game).
  """

  use GenServer, restart: :temporary

  require Logger

  alias TienLen.{Bot, Deck, Room}

  @turn_timeout 20_000
  @disconnect_timeout 20_000
  # events after which the (possibly same) current player gets a fresh turn timer
  @turn_events [:played, :chopped, :passed, :timed_out, :round_ended, :lead_moved, :game_started]
  # events that change the lobby summary (player count, status, host)
  @lobby_events [
    :joined,
    :left,
    :host_changed,
    :game_started,
    :game_over,
    :stake_changed,
    :private_changed
  ]
  # room chat kept in memory (G1)
  @chat_keep 50
  # V4
  @max_spectators 20

  # -- API ----------------------------------------------------------------------

  @doc """
  Starts a room under `TienLen.RoomSupervisor`. Returns `{:ok, room_id}`, or
  `{:error, :too_many_rooms}` when `max_rooms/0` rooms are already open (a cheap guard against
  room-creation spam; every room is a process).
  """
  @spec start_room(keyword()) :: {:ok, String.t()} | {:error, term()}
  def start_room(opts \\ []) do
    if DynamicSupervisor.count_children(TienLen.RoomSupervisor).active >= max_rooms(),
      do: {:error, :too_many_rooms},
      else: do_start_room(opts)
  end

  @doc "Maximum number of open rooms (admin setting `max_rooms`, default from config, F7)."
  def max_rooms, do: TienLen.Settings.int("max_rooms")

  defp do_start_room(opts) do
    if Room.valid_stake?(Keyword.get(opts, :stake, 0)),
      do: start_child(opts),
      else: {:error, :invalid_stake}
  end

  defp start_child(opts) do
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

  @doc "Seats (or reconnects) `player_id` and monitors the calling process. `looks`: see `TienLen.Room.join/5`."
  def join(room_id, player_id, name, avatar \\ nil, looks \\ %{}),
    do: call(room_id, {:join, player_id, name, avatar, looks})

  @doc "A seated player shows an emoji on their seat (R1); broadcasts `{:reaction, room_id, seat, emoji}`."
  def react(room_id, player_id, emoji), do: call(room_id, {:react, player_id, emoji})

  @doc """
  A seated player throws `item_id` (`TienLen.Throws`) at another occupied seat (TH1–TH3): at
  most one throw per #{3} s, the price is spent first. Broadcasts
  `{:thrown, room_id, from_seat, to_seat, item_id}`.
  """
  def throw(room_id, player_id, to_seat, item_id),
    do: call(room_id, {:throw, player_id, to_seat, item_id})

  @doc """
  TB1: a seated player blows on the cards while waiting for a game; everyone sees a puff.
  Once per 3 s. It changes nothing (TB3): the next deal is the usual shuffle.
  Broadcasts `{:blow, room_id, seat}`.
  """
  def blow(room_id, player_id), do: call(room_id, {:blow, player_id})

  def leave(room_id, player_id), do: call(room_id, {:leave, player_id})
  def start_game(room_id, player_id), do: call(room_id, {:start_game, player_id})
  def play(room_id, player_id, cards), do: call(room_id, {:command, player_id, {:play, cards}})
  def pass(room_id, player_id), do: call(room_id, {:command, player_id, :pass})
  def chop(room_id, player_id, cards), do: call(room_id, {:command, player_id, {:chop, cards}})

  @doc "Admin watch view with every hand (AD7, F6). Only for TienLen.Admin."
  def admin_view(room_id), do: call(room_id, :admin_view)

  @doc "Admin closes the room; a running game is cancelled without coins or stats (AD6, F5)."
  def admin_close(room_id), do: call(room_id, :admin_close)

  @doc "Admin removes a player from the room; they cannot come back (AD6)."
  def kick(room_id, player_id), do: call(room_id, {:kick, player_id})

  @doc "The host changes the room's stake between games (E7)."
  def set_stake(room_id, player_id, stake), do: call(room_id, {:set_stake, player_id, stake})

  @doc "The host adds a bot (`:easy` / `:normal`) to a free seat (B1, B2)."
  def add_bot(room_id, player_id, level), do: call(room_id, {:add_bot, player_id, level})

  @doc "The host removes the bot in `seat`."
  def remove_bot(room_id, player_id, seat), do: call(room_id, {:remove_bot, player_id, seat})

  @doc "Legal plays for the player right now (H1): on their turn, else out-of-turn chops."
  def hints(room_id, player_id), do: call(room_id, {:hints, player_id})

  @doc "The host makes the room private (hidden from the lobby) or public (G11)."
  def set_private(room_id, player_id, private?),
    do: call(room_id, {:set_private, player_id, private?})

  @doc """
  Watches the room as a spectator (V1–V4): monitors the caller and returns the public view.
  At most #{20} spectators. `{:ok, view}` or `{:error, reason}`.
  """
  def watch(room_id), do: call(room_id, :watch)

  @doc "The public view for spectators: no hand, no chat (V2, V3)."
  def spectator_view(room_id), do: call(room_id, :spectator_view)

  @doc "True if `player_id` is seated in the room."
  def seated?(room_id, player_id), do: call(room_id, {:seated?, player_id})

  @doc """
  Adds a prepared chat message (`TienLen.Chat.prepare/2`) from the seated `player_id` (G4).
  Broadcasts `{:room_chat, room_id, msg}` on the room topic.
  """
  def chat(room_id, player_id, msg), do: call(room_id, {:chat, player_id, msg})

  @doc "The room chat, oldest first, for a seated player."
  def chat_history(room_id, player_id), do: call(room_id, {:chat_history, player_id})

  @doc "Removes a chat message (admin, G12). Broadcasts `{:room_chat_deleted, room_id, id}`."
  def delete_chat(room_id, msg_id), do: call(room_id, {:delete_chat, msg_id})

  @doc "Dry run of a command (`{:play, cards}`, `:pass`, `{:chop, cards}`) for UI labels."
  def check(room_id, player_id, cmd), do: call(room_id, {:check, player_id, cmd})

  @doc """
  The room as seen by a seated `player_id`, plus `turn_ms_left` for the current turn.
  Anyone not seated gets `{:error, :not_in_room}` (no spectators, #17).
  """
  def view(room_id, player_id), do: call(room_id, {:view, player_id})

  @doc "Public summary for the lobby list (no player ids, no cards)."
  def summary(room_id), do: call(room_id, :summary)

  # Any exit of the room process during a call (gone, stopped, crashed, killed, timed out)
  # becomes {:error, :room_not_found}: a dying room must never take down the caller (e.g. the
  # lobby listing every room, found by a flaky test).
  defp call(room_id, msg) do
    GenServer.call(via(room_id), msg)
  catch
    :exit, _reason -> {:error, :room_not_found}
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
       room: %{
         Room.new(id, Keyword.get(opts, :stake, 0))
         | private: Keyword.get(opts, :private, false)
       },
       # newest first, at most @chat_keep
       chat: [],
       version: 0,
       turn_timeout: Keyword.get(opts, :turn_timeout, @turn_timeout),
       disconnect_timeout: Keyword.get(opts, :disconnect_timeout, @disconnect_timeout),
       deals: Keyword.get(opts, :deals, []),
       # module with record/1 called at game over (TienLen.Stats in dev/prod, off in tests)
       recorder:
         Keyword.get_lazy(opts, :recorder, fn ->
           Application.get_env(:tien_len, :results_recorder, TienLen.Stats)
         end),
       # module with balances/1 and settle/3 (TienLen.Economy in dev/prod, off in tests)
       economy:
         Keyword.get_lazy(opts, :economy, fn ->
           Application.get_env(:tien_len, :economy, TienLen.Economy)
         end),
       # coins moved in the current / last game: seat => net amount, and chains settled
       coin_deltas: %{},
       chain_no: 0,
       # V1: spectator pid => monitor ref
       spectators: %{},
       # V5: replay of the running game (dealt hands + public events), stored at game over
       replay: nil,
       # %{ref, seat, deadline} of the running turn timer
       turn: nil,
       # B5: pending bot action (ref) and the delay before a bot acts
       bot_ref: nil,
       bot_delay:
         Keyword.get_lazy(opts, :bot_delay, fn ->
           Application.get_env(:tien_len, :bot_delay, 1_000)
         end),
       # BP3: random source of the bots' lines (fixed in tests)
       talk_rng: Keyword.get_lazy(opts, :talk_rng, &TienLen.BotTalk.random/0),
       # player_id => timer ref
       disconnect_timers: %{},
       # monitored pid => {player_id, monitor ref}
       pids: %{}
     }
     |> tap(fn state -> Process.send_after(self(), :idle_check, state.disconnect_timeout) end)}
  end

  @impl true
  def terminate(_reason, state) do
    Phoenix.PubSub.broadcast(TienLen.PubSub, TienLen.Lobby.topic(), {:room_closed, state.id})
  end

  @impl true
  def handle_call({:join, player_id, name}, from, state),
    do: handle_call({:join, player_id, name, nil, %{}}, from, state)

  def handle_call({:join, player_id, name, avatar}, from, state),
    do: handle_call({:join, player_id, name, avatar, %{}}, from, state)

  def handle_call({:join, player_id, name, avatar, looks}, {pid, _tag}, state)
      when is_map(looks) do
    case Room.join(state.room, player_id, name, avatar, looks) do
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

    balances = state.economy && player_balances(state)

    case Room.start_game(state.room, player_id, deal, balances) do
      {:ok, room, events} ->
        state = %{state | deals: deals, coin_deltas: %{}, chain_no: 0}
        {:reply, :ok, changed(state, room, events)}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call(:admin_view, _from, state) do
    view =
      state.room
      |> Room.admin_view()
      |> Map.put(:turn_ms_left, turn_ms_left(state))
      |> Map.put(:coin_deltas, state.coin_deltas)
      |> Map.put(:balances, seat_balances(state))
      |> Map.put(:chat, Enum.reverse(state.chat))

    {:reply, view, state}
  end

  # F5: no game_over event is emitted, so nothing is recorded or settled for the running game.
  def handle_call(:admin_close, _from, state) do
    Phoenix.PubSub.broadcast(
      TienLen.PubSub,
      topic(state.id),
      {:room_updated, state.id, state.version + 1, [{:closed_by_admin}]}
    )

    {:stop, :normal, :ok, state}
  end

  def handle_call({:kick, player_id}, _from, state) do
    reply_change(state, Room.kick(state.room, player_id), fn state ->
      state |> untrack_player(player_id) |> cancel_disconnect_timer(player_id)
    end)
  end

  def handle_call({:set_private, player_id, private?}, _from, state) do
    reply_change(state, Room.set_private(state.room, player_id, private?))
  end

  def handle_call({:add_bot, player_id, level}, _from, state) do
    reply_change(state, Room.add_bot(state.room, player_id, level))
  end

  def handle_call({:remove_bot, player_id, seat}, _from, state) do
    reply_change(state, Room.remove_bot(state.room, player_id, seat))
  end

  def handle_call({:hints, player_id}, _from, state) do
    room = state.room

    hints =
      with :playing <- room.status,
           seat when seat != nil <- Room.seat_of(room, player_id) do
        if room.game.current == seat,
          do: TienLen.Hint.moves(room.game, seat),
          else: TienLen.Hint.chops(room.game, seat)
      else
        _ -> []
      end

    {:reply, hints, state}
  end

  def handle_call({:react, player_id, emoji}, _from, state) do
    case Room.seat_of(state.room, player_id) do
      nil ->
        {:reply, {:error, :not_in_room}, state}

      seat ->
        if emoji in TienLen.Chat.reactions() do
          Phoenix.PubSub.broadcast(
            TienLen.PubSub,
            topic(state.id),
            {:reaction, state.id, seat, emoji}
          )

          {:reply, :ok, state}
        else
          {:reply, {:error, :unknown_command}, state}
        end
    end
  end

  def handle_call({:throw, player_id, to_seat, item_id}, _from, state) do
    from_seat = Room.seat_of(state.room, player_id)
    item = TienLen.Throws.item(item_id)

    with :ok <- if(from_seat, do: :ok, else: {:error, :not_in_room}),
         :ok <- if(item, do: :ok, else: {:error, :unknown_command}),
         :ok <-
           if(to_seat != from_seat and Map.has_key?(state.room.seats, to_seat),
             do: :ok,
             else: {:error, :invalid_target}
           ),
         :ok <- throw_rate(player_id),
         :ok <- pay_throw(state, player_id, item) do
      Phoenix.PubSub.broadcast(
        TienLen.PubSub,
        topic(state.id),
        {:thrown, state.id, from_seat, to_seat, item.id}
      )

      {:reply, :ok, state}
    else
      error -> {:reply, error, state}
    end
  end

  def handle_call({:blow, player_id}, _from, state) do
    seat = Room.seat_of(state.room, player_id)

    with :ok <- if(seat, do: :ok, else: {:error, :not_in_room}),
         :ok <- if(state.room.status == :waiting, do: :ok, else: {:error, :game_in_progress}),
         :ok <- TienLen.RateLimit.hit({:blow, player_id}, 1, 3_000) do
      Phoenix.PubSub.broadcast(TienLen.PubSub, topic(state.id), {:blow, state.id, seat})
      {:reply, :ok, state}
    else
      {:error, :rate_limited} -> {:reply, {:error, :blow_too_fast}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call(:watch, {pid, _tag}, state) do
    cond do
      Map.has_key?(state.spectators, pid) ->
        {:reply, {:ok, public_view(state)}, state}

      map_size(state.spectators) >= @max_spectators ->
        {:reply, {:error, :too_many_spectators}, state}

      true ->
        state = %{state | spectators: Map.put(state.spectators, pid, Process.monitor(pid))}
        {:reply, {:ok, public_view(state)}, spectators_changed(state)}
    end
  end

  def handle_call(:spectator_view, _from, state), do: {:reply, public_view(state), state}

  def handle_call({:seated?, player_id}, _from, state),
    do: {:reply, Room.seat_of(state.room, player_id) != nil, state}

  def handle_call({:chat, player_id, msg}, _from, state) do
    if Room.seat_of(state.room, player_id) == nil do
      {:reply, {:error, :not_in_room}, state}
    else
      Phoenix.PubSub.broadcast(TienLen.PubSub, topic(state.id), {:room_chat, state.id, msg})
      {:reply, :ok, %{state | chat: Enum.take([msg | state.chat], @chat_keep)}}
    end
  end

  def handle_call({:chat_history, player_id}, _from, state) do
    if Room.seat_of(state.room, player_id) == nil,
      do: {:reply, {:error, :not_in_room}, state},
      else: {:reply, {:ok, Enum.reverse(state.chat)}, state}
  end

  def handle_call({:delete_chat, msg_id}, _from, state) do
    case Enum.find(state.chat, &(&1.id == msg_id)) do
      nil ->
        {:reply, {:error, :not_found}, state}

      msg ->
        Phoenix.PubSub.broadcast(
          TienLen.PubSub,
          topic(state.id),
          {:room_chat_deleted, state.id, msg_id}
        )

        {:reply, {:ok, msg}, %{state | chat: Enum.reject(state.chat, &(&1.id == msg_id))}}
    end
  end

  def handle_call({:set_stake, player_id, stake}, _from, state) do
    reply_change(state, Room.set_stake(state.room, player_id, stake))
  end

  def handle_call({:command, player_id, cmd}, _from, state) do
    reply_change(state, Room.command(state.room, player_id, cmd))
  end

  def handle_call({:check, player_id, cmd}, _from, state) do
    {:reply, Room.check(state.room, player_id, cmd), state}
  end

  def handle_call({:view, player_id}, _from, state) do
    if Room.seat_of(state.room, player_id) == nil do
      {:reply, {:error, :not_in_room}, state}
    else
      view =
        state.room
        |> Room.view(player_id)
        |> Map.put(:turn_ms_left, turn_ms_left(state))
        |> Map.put(:coin_deltas, state.coin_deltas)
        |> Map.put(:balances, seat_balances(state))
        |> Map.put(:spectators, map_size(state.spectators))

      {:reply, view, state}
    end
  end

  def handle_call(:summary, _from, state) do
    room = state.room
    host = room.host && room.seats[room.host]

    summary = %{
      id: state.id,
      players: map_size(room.seats),
      max_players: 4,
      status: room.status,
      host_name: host && host.name,
      joinable: room.status == :waiting and map_size(room.seats) < 4,
      stake: room.stake,
      private: room.private
    }

    {:reply, summary, state}
  end

  # Unknown requests are answered with an error instead of crashing the room.
  def handle_call(_unexpected, _from, state), do: {:reply, {:error, :unknown_request}, state}

  @impl true
  def handle_info(:idle_check, state) do
    if Room.humans(state.room) == [], do: {:stop, :normal, state}, else: {:noreply, state}
  end

  # B5: a bot acts (an out-of-turn chop first, else its own turn). The command goes through
  # the normal rules; if it is refused anyway the bot's turn is handled like a timeout.
  def handle_info({:bot_act, ref}, %{bot_ref: ref} = state) do
    state = %{state | bot_ref: nil}
    room = state.room

    result =
      case room.status == :playing && bot_command(room) do
        {bot_id, cmd} ->
          case Room.command(room, bot_id, cmd) do
            {:ok, _, _} = ok ->
              ok

            {:error, _} when is_tuple(cmd) and elem(cmd, 0) == :chop ->
              {:error, :skip}

            {:error, _} ->
              Room.turn_timeout(room)
          end

        _ ->
          {:error, :no_bot}
      end

    case result do
      {:ok, room, events} -> {:noreply, changed(state, room, events)}
      {:error, _} -> {:noreply, state}
    end
  end

  def handle_info({:bot_act, _stale}, state), do: {:noreply, state}

  def handle_info({:DOWN, mref, :process, pid, _reason}, %{spectators: specs} = state)
      when is_map_key(specs, pid) and :erlang.map_get(pid, specs) == mref do
    {:noreply, spectators_changed(%{state | spectators: Map.delete(specs, pid)})}
  end

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

  # Anything else (stray or malformed messages) is ignored instead of crashing the room.
  def handle_info(_unexpected, state), do: {:noreply, state}

  # -- helpers ------------------------------------------------------------------

  defp reply_change(state, result, before \\ & &1)

  defp reply_change(state, {:ok, room, events}, before) do
    state = changed(before.(state), room, events)

    # the room closes when no human is left (bots alone never keep it open, B4)
    if Room.humans(room) == [],
      do: {:stop, :normal, :ok, state},
      else: {:reply, :ok, state}
  end

  defp reply_change(state, {:error, _} = error, _before), do: {:reply, error, state}

  defp maybe_stop(state) do
    if Enum.any?(state.room.seats, fn {_seat, p} ->
         p.connected and not Room.bot_id?(p.player_id)
       end),
       do: {:noreply, state},
       else: {:stop, :normal, state}
  end

  # Applies a new room, reschedules the turn timer and broadcasts the public events.
  defp changed(state, room, events) do
    old_room = state.room

    state =
      %{state | room: room, version: state.version + 1}
      |> reschedule_turn(events)
      |> schedule_bot()

    # coins first, so the recorded game carries each player's net coins (P2)
    {state, events} = settle_coins(state, events)
    state = track_replay(state, events)
    if Enum.any?(events, &(elem(&1, 0) == :game_over)), do: record_result(state)

    Phoenix.PubSub.broadcast(
      TienLen.PubSub,
      topic(state.id),
      {:room_updated, state.id, state.version, events}
    )

    if Enum.any?(events, &(elem(&1, 0) in @lobby_events)) do
      Phoenix.PubSub.broadcast(TienLen.PubSub, TienLen.Lobby.topic(), {:lobby_updated, state.id})
    end

    case TienLen.Commentary.effects(old_room, events) do
      [] ->
        :ok

      kinds ->
        Phoenix.PubSub.broadcast(TienLen.PubSub, topic(state.id), {:effects, state.id, kinds})
    end

    state |> comment(old_room, events) |> give_lixi(events) |> bot_talk(old_room, events)
  end

  # BP3: bots of the room say something (as themselves, with their seat for a speech bubble)
  defp bot_talk(state, old_room, events) do
    old_room
    |> TienLen.BotTalk.lines(state.room, events, state.talk_rng)
    |> Enum.reduce(state, fn {seat, text}, st ->
      msg = %{
        id: System.unique_integer([:positive, :monotonic]),
        user_id: nil,
        name: st.room.seats[seat].name,
        text: text,
        at: DateTime.utc_now(:second),
        bot: true,
        seat: seat
      }

      Phoenix.PubSub.broadcast(TienLen.PubSub, topic(st.id), {:room_chat, st.id, msg})
      %{st | chat: Enum.take([msg | st.chat], @chat_keep)}
    end)
  rescue
    error ->
      Logger.error("room #{state.id}: bot talk failed: #{Exception.message(error)}")
      state
  end

  # BL1: the commentator's lines go to the room chat like any message (no user id)
  defp comment(state, old_room, events) do
    old_room
    |> TienLen.Commentary.lines(state.room, events)
    |> Enum.reduce(state, &post_system(&2, &1))
  rescue
    error ->
      Logger.error("room #{state.id}: commentary failed: #{Exception.message(error)}")
      state
  end

  defp post_system(state, text) do
    msg = %{
      id: System.unique_integer([:positive, :monotonic]),
      user_id: nil,
      name: TienLen.Commentary.name(),
      text: text,
      at: DateTime.utc_now(:second),
      system: true
    }

    Phoenix.PubSub.broadcast(TienLen.PubSub, topic(state.id), {:room_chat, state.id, msg})
    %{state | chat: Enum.take([msg | state.chat], @chat_keep)}
  end

  # EV2: during Tết every 1st place of a recorded game gets a lì xì (announced in the chat)
  defp give_lixi(%{economy: economy, recorder: recorder} = state, events)
       when economy != nil and recorder != nil do
    with true <- Enum.any?(events, &match?({:game_over, _}, &1)),
         "tet" <- TienLen.Events.current(),
         %{} = result <- Room.result(state.room) do
      Enum.reduce(result.players, state, fn
        %{place: 1, user_id: user_id, seat: seat}, st when is_integer(user_id) ->
          case TienLen.Events.lixi(user_id, result.ref) do
            {:ok, amount} ->
              name = (st.room.seats[seat] || %{name: "Người thắng"}).name
              post_system(st, "🧧 #{name} được lì xì #{amount} coin! Chúc mừng năm mới!")

            _ ->
              st
          end

        _player, st ->
          st
      end)
    else
      _ -> state
    end
  rescue
    error ->
      Logger.error("room #{state.id}: lì xì failed: #{Exception.message(error)}")
      state
  end

  defp give_lixi(state, _events), do: state

  # -- coins (T20–T25, E6) ----------------------------------------------------------

  # Chop chains are settled when they end (round end or game over); places, thối and
  # instant-win payments at game over. Each settlement has a unique key, so a retry never
  # pays twice. The actual transfers are appended as a {:coins, transfers} event (seats).
  defp settle_coins(%{economy: nil} = state, events), do: {state, events}
  defp settle_coins(%{room: %{stake: 0}} = state, events), do: {state, events}

  defp settle_coins(state, events) do
    room = state.room

    {state, transfers} =
      Enum.reduce(events, {state, []}, fn
        {:chop_chain, chain}, {st, acc} ->
          no = st.chain_no + 1
          key = "room:#{st.id}:game:#{room.game_no}:chain:#{no}"

          {%{st | chain_no: no},
           acc ++ settle(st, key, TienLen.Payout.chop_chain(chain, room.stake))}

        {:game_over, _ranking}, {st, acc} ->
          key = "room:#{st.id}:game:#{room.game_no}:end"
          {st, acc ++ settle(st, key, TienLen.Payout.game_over(room.game, room.stake))}

        _event, acc ->
          acc
      end)

    if transfers == [] do
      {state, events}
    else
      deltas =
        Enum.reduce(transfers, state.coin_deltas, fn t, acc ->
          acc
          |> Map.update(t.from, -t.amount, &(&1 - t.amount))
          |> Map.update(t.to, t.amount, &(&1 + t.amount))
        end)

      {%{state | coin_deltas: deltas}, events ++ [{:coins, transfers}]}
    end
  end

  # seat debts → account debts → Economy.settle → paid transfers back in seats
  defp settle(state, key, seat_debts) do
    players = state.room.game_players
    seat_of = Map.new(players, fn {seat, pid} -> {pid, seat} end)

    debts =
      for d <- seat_debts, from = players[d.from], to = players[d.to] do
        %{d | from: from, to: to}
      end

    case debts != [] && state.economy.settle(key, debts, key) do
      {:ok, paid} when is_list(paid) ->
        Enum.map(paid, fn t -> %{t | from: seat_of[t.from], to: seat_of[t.to]} end)

      {:ok, :already_applied} ->
        []

      false ->
        []

      other ->
        Logger.error("room #{state.id}: coin settlement #{key} failed: #{inspect(other)}")
        []
    end
  rescue
    error ->
      Logger.error("room #{state.id}: coin settlement #{key} failed: #{Exception.message(error)}")
      []
  end

  defp player_balances(state) do
    state.room.seats
    |> Map.values()
    |> Enum.map(& &1.player_id)
    |> Enum.filter(&is_integer/1)
    |> state.economy.balances()
  rescue
    _ -> %{}
  end

  defp seat_balances(%{economy: nil}), do: %{}

  defp seat_balances(state) do
    balances = player_balances(state)
    Map.new(state.room.seats, fn {seat, p} -> {seat, Map.get(balances, p.player_id)} end)
  end

  # Y6: a failing write is logged and never interrupts play.
  defp record_result(%{recorder: nil}), do: :ok

  defp record_result(%{recorder: recorder, room: room, id: id, coin_deltas: deltas} = state) do
    case Room.result(room) do
      nil ->
        :ok

      result ->
        players = Enum.map(result.players, &Map.put(&1, :coins, Map.get(deltas, &1.seat, 0)))
        recorder.record(result |> Map.put(:players, players) |> Map.put(:replay, state.replay))
    end
  rescue
    error ->
      Logger.error("room #{id}: could not record the game result: #{Exception.message(error)}")
  catch
    kind, reason ->
      Logger.error("room #{id}: could not record the game result: #{inspect({kind, reason})}")
  end

  # -- throwing items (TH1–TH4) ---------------------------------------------------------

  defp throw_rate(player_id) do
    case TienLen.RateLimit.hit({:throw, player_id}, 1, TienLen.Throws.cooldown()) do
      :ok -> :ok
      {:error, :rate_limited} -> {:error, :throw_too_fast}
    end
  end

  # no economy (tests): throws are free
  defp pay_throw(%{economy: nil}, _player_id, _item), do: :ok

  defp pay_throw(state, player_id, item) do
    case state.economy.spend(player_id, item.price, "throw", "#{item.emoji} phòng #{state.id}") do
      {:ok, _balance} -> :ok
      {:error, :insufficient_coins} -> {:error, :cannot_afford}
      {:error, _} = error -> error
    end
  rescue
    error ->
      Logger.error("room #{state.id}: throw payment failed: #{Exception.message(error)}")
      {:error, :unknown_request}
  end

  # -- spectators (V1–V4) -------------------------------------------------------------

  defp public_view(state) do
    state.room
    |> Room.view(nil)
    |> Map.put(:turn_ms_left, turn_ms_left(state))
    |> Map.put(:coin_deltas, state.coin_deltas)
    |> Map.put(:balances, seat_balances(state))
    |> Map.put(:spectators, map_size(state.spectators))
  end

  # the count is public; views are re-read by subscribers on any update
  defp spectators_changed(state) do
    state = %{state | version: state.version + 1}

    Phoenix.PubSub.broadcast(
      TienLen.PubSub,
      topic(state.id),
      {:room_updated, state.id, state.version, [{:spectators, map_size(state.spectators)}]}
    )

    state
  end

  # -- replay (V5) ---------------------------------------------------------------------

  # A new game starts a replay with the dealt hands; public game events are appended. It is
  # only stored with the recorded result at game over (never shown while the game runs).
  defp track_replay(state, events) do
    replay =
      case Enum.find(events, &(elem(&1, 0) == :game_started)) do
        {:game_started, seats} ->
          game = state.room.game

          %{
            "seats" => Enum.map(seats, &%{"seat" => &1, "name" => state.room.seats[&1].name}),
            "hands" => Map.new(seats, &{to_string(&1), codes(game.hands[&1])}),
            "events" => []
          }

        nil ->
          state.replay
      end

    case replay do
      nil ->
        %{state | replay: nil}

      replay ->
        new = Enum.flat_map(events, &replay_event/1)
        %{state | replay: Map.update!(replay, "events", &(&1 ++ new))}
    end
  end

  defp codes(cards), do: cards |> TienLen.Card.sort() |> Enum.map(&TienLen.Card.to_code/1)

  defp replay_event({t, seat, combo}) when t in [:played, :chopped],
    do: [
      %{"t" => to_string(t), "s" => seat, "c" => codes(combo.cards), "k" => to_string(combo.type)}
    ]

  defp replay_event({t, seat})
       when t in [:passed, :timed_out, :removed, :round_ended, :lead_moved],
       do: [%{"t" => to_string(t), "s" => seat}]

  defp replay_event({:finished, seat, pos}), do: [%{"t" => "finished", "s" => seat, "p" => pos}]
  defp replay_event({:game_over, ranking}), do: [%{"t" => "game_over", "r" => ranking}]

  defp replay_event({:instant_win, winners}),
    do: [
      %{"t" => "instant_win", "w" => Enum.map(winners, fn {s, type} -> [s, to_string(type)] end)}
    ]

  defp replay_event({:coins, transfers}),
    do: [
      %{
        "t" => "coins",
        "x" => Enum.map(transfers, &%{"from" => &1.from, "to" => &1.to, "amount" => &1.amount})
      }
    ]

  defp replay_event(_event), do: []

  # -- bots (B5) ----------------------------------------------------------------------

  # After every change: if a bot has something to do, it acts after `bot_delay` ms. A newer
  # change replaces the pending action (its ref goes stale).
  defp schedule_bot(state) do
    with :playing <- state.room.status,
         {bot_id, _cmd} <- bot_command(state.room) do
      ref = make_ref()
      # BP2: the personality sets the speed
      factor = TienLen.BotTalk.speed(state.room, Room.seat_of(state.room, bot_id))
      Process.send_after(self(), {:bot_act, ref}, round(state.bot_delay * factor))
      %{state | bot_ref: ref}
    else
      _ -> %{state | bot_ref: nil}
    end
  end

  # {bot_id, command} for the next bot action, or nil
  defp bot_command(room) do
    game = room.game

    chop =
      Enum.find_value(room.seats, fn {seat, p} ->
        level = Map.get(p, :bot)
        cards = level && seat != game.current && Bot.chop(game, seat, level)
        if cards, do: {p.player_id, {:chop, cards}}
      end)

    chop || turn_command(room, game)
  end

  defp turn_command(room, %{current: seat} = game) when seat != nil do
    case room.seats[seat] do
      %{bot: level, player_id: id} -> {id, Bot.decide(game, seat, level)}
      _ -> nil
    end
  end

  defp turn_command(_room, _game), do: nil

  defp turn_ms_left(%{turn: %{deadline: deadline}}), do: max(deadline - now(), 0)
  defp turn_ms_left(_state), do: nil

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
