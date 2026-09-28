defmodule TienLen.Lobby do
  @moduledoc """
  Rooms as seen from the lobby (RULES T13, #17; decisions R6, O3).

  A thin context over `TienLen.RoomServer`: create, list, join, leave and start rooms, and
  validate display names. Players are identified by an opaque `player_id` (a random id kept
  in the signed session, see `TienLenWeb.PlayerIdentity`).

  Joining monitors the **calling process** (the player's LiveView), so call `join_room/3` and
  `create_room/2` from the process that represents the player.

  Lobby updates are broadcast on `topic/0` as `{:lobby_updated, room_id}` and
  `{:room_closed, room_id}`.
  """

  alias TienLen.RoomServer

  @max_name 20

  @type summary :: %{
          id: String.t(),
          players: non_neg_integer(),
          max_players: 4,
          status: :waiting | :playing,
          host_name: String.t() | nil,
          joinable: boolean()
        }

  @doc "PubSub topic for lobby-wide updates."
  def topic, do: "lobby"

  @doc "Subscribes the caller to lobby updates."
  def subscribe, do: Phoenix.PubSub.subscribe(TienLen.PubSub, topic())

  @doc """
  Normalises a display name: trims, collapses whitespace, 1–#{@max_name} characters, no control
  characters.
  """
  @spec normalize_name(term()) :: {:ok, String.t()} | {:error, :invalid_name}
  def normalize_name(name) when is_binary(name) do
    # check UTF-8 first: String.trim/1 and the regexes raise on invalid binaries
    if String.valid?(name), do: normalize_valid(name), else: {:error, :invalid_name}
  end

  def normalize_name(_), do: {:error, :invalid_name}

  defp normalize_valid(name) do
    name = name |> String.trim() |> String.replace(~r/\s+/u, " ")

    cond do
      name == "" -> {:error, :invalid_name}
      String.length(name) > @max_name -> {:error, :invalid_name}
      String.match?(name, ~r/[[:cntrl:]]/u) -> {:error, :invalid_name}
      true -> {:ok, name}
    end
  end

  @doc """
  Creates a room and seats the creator in it (seat 0, host). Returns `{:ok, room_id, seat}`.
  """
  @spec create_room(term(), String.t(), keyword()) :: {:ok, String.t(), 0..3} | {:error, atom()}
  def create_room(player_id, name, opts \\ []) do
    with {:ok, name} <- normalize_name(name),
         {:ok, room_id} <- RoomServer.start_room(opts),
         {:ok, seat} <- RoomServer.join(room_id, player_id, name) do
      {:ok, room_id, seat}
    end
  end

  @doc """
  Opens an empty room without seating anyone; the first player to join becomes host. Used by
  the web lobby, which then navigates the creator to the room page where they join from their
  own LiveView process. An empty room closes after the disconnect timeout.
  """
  @spec open_room(keyword()) :: {:ok, String.t()} | {:error, term()}
  def open_room(opts \\ []), do: RoomServer.start_room(opts)

  @doc """
  Seats `player_id` in a room, or reconnects them to their seat. Refused when the room is full
  or a game is running (R6), unless the player is already seated there.
  """
  @spec join_room(String.t(), term(), String.t()) :: {:ok, 0..3} | {:error, atom()}
  def join_room(room_id, player_id, name, avatar \\ nil) do
    with {:ok, name} <- normalize_name(name),
         do: RoomServer.join(room_id, player_id, name, avatar)
  end

  @doc "Leaves a room for good (frees the seat)."
  def leave_room(room_id, player_id), do: RoomServer.leave(room_id, player_id)

  @doc "Starts the next game (host only, at least 2 connected players)."
  def start_game(room_id, player_id), do: RoomServer.start_game(room_id, player_id)

  @doc """
  The room as seen by a seated player. There are no spectators (#17): anyone else gets
  `{:error, :not_in_room}`.
  """
  def room_view(room_id, player_id), do: RoomServer.view(room_id, player_id)

  @doc "Rooms shown in the lobby list: private rooms are hidden (G11)."
  def public_rooms, do: Enum.reject(list_rooms(), & &1.private)

  @doc "Summaries of all running rooms, private ones included: joinable first, then by id."
  @spec list_rooms() :: [summary()]
  def list_rooms do
    TienLen.RoomRegistry
    |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
    |> Enum.flat_map(fn room_id ->
      case RoomServer.summary(room_id) do
        {:error, _} -> []
        summary -> [summary]
      end
    end)
    |> Enum.sort_by(&{not &1.joinable, &1.id})
  end
end
