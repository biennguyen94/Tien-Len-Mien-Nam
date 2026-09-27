defmodule TienLen.Room do
  @moduledoc """
  A room: up to 4 seats, a host, and a sequence of games (RULES T2, T13, T15; D8, R1, R4, R6,
  I5, S5, S6).

  Pure: `TienLen.RoomServer` owns timers and connections and calls these functions.

  ## Seats and players

  Seats are integers `0..3`; ascending seat order is the turn order (counter-clockwise), and
  seat numbers are what `TienLen.Game` sees. A *player id* is an opaque term that identifies
  a person (a signed token in Phase 7); `join/3` with the same id again is a reconnect.

  ## Next game's leader (T2)

  `last_winner` holds the player id of the previous game's 1st place, or `nil` when the
  previous game ended by instant win (I5) or none was played. If that player takes part in the
  next game, they lead it (winner-led, R1); otherwise the game is card-led (R4).

  ## Participants

  A game is dealt to the **connected** seated players only (interpretation X6). A disconnected
  player keeps their seat and plays again from the next game after reconnecting (S5).
  """

  alias TienLen.{Deck, Game}

  @max_seats 4

  defstruct id: nil,
            seats: %{},
            host: nil,
            status: :waiting,
            game: nil,
            games_played: 0,
            last_winner: nil

  @type player_id :: term()
  @type seat :: 0..3
  @type player :: %{player_id: player_id(), name: String.t(), connected: boolean()}
  @type t :: %__MODULE__{
          id: term(),
          seats: %{seat() => player()},
          host: seat() | nil,
          status: :waiting | :playing,
          game: Game.t() | nil,
          games_played: non_neg_integer(),
          last_winner: player_id() | nil
        }

  @typedoc "How to deal a game: a seed, or given hands (tests/replays)."
  @type deal :: Deck.seed() | {:hands, %{seat() => [TienLen.Card.t()]}}

  @type event :: Game.event() | tuple()
  @type result :: {:ok, t(), [event()]} | {:error, atom()}

  @spec new(term()) :: t()
  def new(id), do: %__MODULE__{id: id}

  # -- membership ---------------------------------------------------------------

  @doc """
  Seats a player (first free seat) or reconnects an already seated one. New players cannot join
  during a game (R6) or when the 4 seats are taken. The first player becomes host.
  """
  @spec join(t(), player_id(), String.t()) :: {:ok, t(), seat(), [event()]} | {:error, atom()}
  def join(room, player_id, name) do
    case seat_of(room, player_id) do
      nil ->
        cond do
          room.status == :playing -> {:error, :game_in_progress}
          map_size(room.seats) >= @max_seats -> {:error, :room_full}
          true -> seat_new_player(room, player_id, name)
        end

      seat ->
        room = update_player(room, seat, &%{&1 | connected: true})
        {:ok, room, seat, [{:connected, seat}]}
    end
  end

  defp seat_new_player(room, player_id, name) do
    seat = Enum.find(0..(@max_seats - 1), &(not Map.has_key?(room.seats, &1)))
    player = %{player_id: player_id, name: name, connected: true}
    room = %{room | seats: Map.put(room.seats, seat, player), host: room.host || seat}
    {:ok, room, seat, [{:joined, seat}]}
  end

  @doc """
  A player leaves the room for good: their seat is freed. During a game they are removed from
  it (as after a disconnect timeout, S5). Host rights pass on at once (S6).
  """
  @spec leave(t(), player_id()) :: result()
  def leave(room, player_id) do
    with {:ok, seat} <- fetch_seat(room, player_id) do
      {room, events} = remove_from_game(room, seat)
      room = %{room | seats: Map.delete(room.seats, seat)}
      {room, host_events} = transfer_host_if(room, seat)
      {:ok, room, events ++ [{:left, seat}] ++ host_events}
    end
  end

  @doc "Marks a seated player as disconnected (their seat is kept)."
  @spec disconnect(t(), player_id()) :: result()
  def disconnect(room, player_id) do
    with {:ok, seat} <- fetch_seat(room, player_id) do
      {:ok, update_player(room, seat, &%{&1 | connected: false}), [{:disconnected, seat}]}
    end
  end

  @doc """
  The disconnect timeout of a still-disconnected player expired (T15, R5, S5, S6, X3): they are
  removed from the current game and, if host, host rights pass on. They keep their seat.
  """
  @spec disconnect_timeout(t(), player_id()) :: result()
  def disconnect_timeout(room, player_id) do
    with {:ok, seat} <- fetch_seat(room, player_id) do
      if room.seats[seat].connected do
        {:ok, room, []}
      else
        {room, events} = remove_from_game(room, seat)
        {room, host_events} = transfer_host_if(room, seat)
        {:ok, room, events ++ host_events}
      end
    end
  end

  # -- games --------------------------------------------------------------------

  @doc """
  The host starts a game with the connected seated players (at least 2, R6).
  """
  @spec start_game(t(), player_id(), deal()) :: result()
  def start_game(room, player_id, deal) do
    participants =
      room.seats
      |> Enum.filter(fn {_seat, p} -> p.connected end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.sort()

    with {:ok, seat} <- fetch_seat(room, player_id),
         :ok <- if(seat == room.host, do: :ok, else: {:error, :not_host}),
         :ok <- if(room.status == :waiting, do: :ok, else: {:error, :game_in_progress}),
         :ok <- if(length(participants) >= 2, do: :ok, else: {:error, :not_enough_players}) do
      opts =
        case room.last_winner && seat_of(room, room.last_winner) do
          leader when is_integer(leader) ->
            if leader in participants, do: [leader: leader], else: []

          _ ->
            []
        end

      game =
        case deal do
          {:hands, hands} -> Game.start(participants, hands, [], opts)
          seed -> Game.new(participants, seed, opts)
        end

      room = %{room | status: :playing, game: game}
      maybe_finish(room, [{:game_started, participants}])
    end
  end

  @doc """
  A game command from a player: `{:play, cards}`, `:pass` or `{:chop, cards}` (out-of-turn
  four-pair).
  """
  @spec command(t(), player_id(), {:play, list()} | :pass | {:chop, list()}) :: result()
  def command(room, player_id, cmd) do
    with {:ok, seat} <- fetch_seat(room, player_id),
         :ok <- if(room.status == :playing, do: :ok, else: {:error, :no_game}),
         {:ok, game, events} <- run(room.game, seat, cmd) do
      maybe_finish(%{room | game: game}, events)
    end
  end

  defp run(game, seat, {:play, cards}), do: Game.play(game, seat, cards)
  defp run(game, seat, :pass), do: Game.pass(game, seat)
  defp run(game, seat, {:chop, cards}), do: Game.chop_out_of_turn(game, seat, cards)
  defp run(_game, _seat, _cmd), do: {:error, :unknown_command}

  @doc "The current player's turn timer expired (T16)."
  @spec turn_timeout(t()) :: result()
  def turn_timeout(%__MODULE__{status: :playing, game: game} = room) do
    with {:ok, game, events} <- Game.timeout(game, game.current) do
      maybe_finish(%{room | game: game}, events)
    end
  end

  def turn_timeout(_room), do: {:error, :no_game}

  # -- queries ------------------------------------------------------------------

  @spec seat_of(t(), player_id()) :: seat() | nil
  def seat_of(room, player_id) do
    Enum.find_value(room.seats, fn {seat, p} -> if p.player_id == player_id, do: seat end)
  end

  @doc "The seat whose turn it is, or `nil`."
  @spec current_seat(t()) :: seat() | nil
  def current_seat(%__MODULE__{status: :playing, game: %Game{current: seat}}), do: seat
  def current_seat(_room), do: nil

  @doc "What `player_id` may see: public room info plus the game view for their seat."
  @spec view(t(), player_id()) :: map()
  def view(room, player_id) do
    me = seat_of(room, player_id)

    %{
      id: room.id,
      me: me,
      host: room.host,
      status: room.status,
      games_played: room.games_played,
      players:
        room.seats
        |> Enum.sort()
        |> Enum.map(fn {seat, p} ->
          %{seat: seat, name: p.name, connected: p.connected, host: seat == room.host}
        end),
      game: room.game && Game.view(room.game, me)
    }
  end

  # -- internals ----------------------------------------------------------------

  defp fetch_seat(room, player_id) do
    case seat_of(room, player_id) do
      nil -> {:error, :not_in_room}
      seat -> {:ok, seat}
    end
  end

  defp update_player(room, seat, fun), do: %{room | seats: Map.update!(room.seats, seat, fun)}

  defp remove_from_game(%__MODULE__{status: :playing, game: game} = room, seat) do
    if seat in Game.active_seats(game) do
      {:ok, game, events} = Game.remove(game, seat)
      {:ok, room, events} = maybe_finish(%{room | game: game}, events)
      {room, events}
    else
      {room, []}
    end
  end

  defp remove_from_game(room, _seat), do: {room, []}

  # Host passes to the next remaining seat in seat order (S6).
  defp transfer_host_if(%__MODULE__{host: seat} = room, seat) do
    seats = room.seats |> Map.keys() |> Enum.sort()
    connected = Enum.filter(seats, &room.seats[&1].connected)
    pool = if connected != [], do: connected, else: seats
    new_host = Enum.find(pool, &(&1 > seat)) || List.first(pool)
    {%{room | host: new_host}, [{:host_changed, new_host}]}
  end

  defp transfer_host_if(room, _seat), do: {room, []}

  defp maybe_finish(%__MODULE__{game: game} = room, events) do
    if room.status == :playing and Game.finished?(game) do
      last_winner =
        if Game.instant_win?(game),
          do: nil,
          else: room.seats[Game.winner(game)] && room.seats[Game.winner(game)].player_id

      room = %{
        room
        | status: :waiting,
          games_played: room.games_played + 1,
          last_winner: last_winner
      }

      {:ok, room, events}
    else
      {:ok, room, events}
    end
  end
end
