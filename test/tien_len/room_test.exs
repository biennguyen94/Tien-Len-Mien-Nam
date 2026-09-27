defmodule TienLen.RoomTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Game, Room}

  defp cards(codes), do: Card.parse_many!(codes)
  defp ok!({:ok, room, _events}), do: room
  defp ok!({:ok, room, _seat, _events}), do: room
  defp ok!(other), do: flunk("expected :ok, got #{inspect(other)}")

  defp room_with(players) do
    Enum.reduce(players, Room.new("r"), fn p, room -> ok!(Room.join(room, p, "name-#{p}")) end)
  end

  defp hands(map), do: {:hands, Map.new(map, fn {seat, codes} -> {seat, cards(codes)} end)}
  defp three_hands, do: hands(%{0 => "3S 9H", 1 => "4S 9C", 2 => "5S 9D"})

  describe "join (R6)" do
    test "fills seats 0..3; the first player is host; a fifth is refused" do
      room = room_with([:p1, :p2, :p3, :p4])
      assert Map.keys(room.seats) |> Enum.sort() == [0, 1, 2, 3]
      assert room.host == 0
      assert Room.join(room, :p5, "x") == {:error, :room_full}
    end

    test "joining again is a reconnect to the same seat" do
      room = room_with([:p1, :p2]) |> Room.disconnect(:p2) |> ok!()
      refute room.seats[1].connected
      assert {:ok, room, 1, [{:connected, 1}]} = Room.join(room, :p2, "again")
      assert room.seats[1].connected
    end

    test "nobody new joins during a game, but seated players can reconnect" do
      room = room_with([:p1, :p2]) |> Room.start_game(:p1, 1) |> ok!()
      assert Room.join(room, :p3, "late") == {:error, :game_in_progress}
      assert {:ok, _room, 0, _} = Room.join(room, :p1, "again")
    end

    test "a freed seat is reused" do
      room = room_with([:p1, :p2, :p3]) |> Room.leave(:p2) |> ok!()
      assert {:ok, _room, 1, _} = Room.join(room, :p4, "new")
    end
  end

  describe "start_game (R6, X6)" do
    test "only the host, only with at least 2 connected players, only when waiting" do
      room = room_with([:p1])
      assert Room.start_game(room, :p1, 1) == {:error, :not_enough_players}

      room = room_with([:p1, :p2])
      assert Room.start_game(room, :p2, 1) == {:error, :not_host}
      assert Room.start_game(room, :stranger, 1) == {:error, :not_in_room}

      {:ok, room, [{:game_started, [0, 1]}]} = Room.start_game(room, :p1, 1)
      assert room.status == :playing
      assert Room.start_game(room, :p1, 1) == {:error, :game_in_progress}
    end

    test "disconnected players are not dealt in (X6)" do
      room = room_with([:p1, :p2, :p3]) |> Room.disconnect(:p2) |> ok!()
      {:ok, room, _} = Room.start_game(room, :p1, 7)
      assert room.game.seats == [0, 2]
    end

    test "the first game is card-led" do
      {:ok, room, _} = room_with([:p1, :p2, :p3, :p4]) |> Room.start_game(:p1, 3)
      assert room.game.mode == :card_led or Game.instant_win?(room.game)
    end
  end

  describe "commands and game end (D8, R1, R4, I5)" do
    setup do
      room = room_with([:p1, :p2, :p3, :p4])
      %{room: room}
    end

    test "commands go to the player's seat; errors pass through", %{room: room} do
      assert Room.command(room, :p1, :pass) == {:error, :no_game}

      room =
        room
        |> Room.start_game(:p1, hands(%{0 => "3S 9H", 1 => "4S", 2 => "5S", 3 => "6S"}))
        |> ok!()

      assert room.game.current == 0
      assert Room.command(room, :p2, {:play, cards("4S")}) == {:error, :not_your_turn}
      assert Room.command(room, :p1, {:play, cards("9H")}) == {:error, :must_include_card}
      assert Room.command(room, :p1, :bogus) == {:error, :unknown_command}
      assert Room.command(room, :stranger, :pass) == {:error, :not_in_room}
      assert {:ok, _room, [{:played, 0, _}]} = Room.command(room, :p1, {:play, cards("3S")})
    end

    test "after a game the winner leads the next one (R1)", %{room: room} do
      room =
        room
        |> Room.start_game(:p1, hands(%{0 => "3S", 1 => "4S 9C", 2 => "5S 9D", 3 => "6S 9H"}))
        |> ok!()

      steps = [
        {:p1, {:play, "3S"}},
        {:p2, {:play, "4S"}},
        {:p3, {:play, "5S"}},
        {:p4, {:play, "6S"}},
        {:p2, :pass},
        # round ends: p4 (seat 3) owns it and leads
        {:p3, :pass},
        {:p4, {:play, "9H"}},
        {:p2, :pass},
        # round ends: owner p4 has finished, next active seat (p2) leads
        {:p3, :pass},
        {:p2, {:play, "9C"}}
      ]

      room =
        Enum.reduce(steps, room, fn
          {p, {:play, codes}}, room -> ok!(Room.command(room, p, {:play, cards(codes)}))
          {p, :pass}, room -> ok!(Room.command(room, p, :pass))
        end)

      assert room.status == :waiting
      assert room.game.ranking == [[0], [3], [1], [2]]
      assert room.games_played == 1
      assert room.last_winner == :p1

      {:ok, room, _} = Room.start_game(room, :p1, 5)
      assert room.game.mode == :winner_led or Game.instant_win?(room.game)
      if room.game.mode == :winner_led, do: assert(room.game.current == 0)
    end

    test "an instant win ends the game at once and the next game is card-led", %{room: room} do
      six_pairs = "3C 3D 5S 5D 7S 7C 9S 9C JC JD 2S 2D KH"

      deal =
        hands(%{
          0 => "4S 4C 6S 8C 10S QS AS 5H 7H 9D JH KS 2H",
          1 => six_pairs,
          2 => "4D 4H 6C 8D 10H QC AC 5C 7D 9H JS KD 2C",
          3 => "3S 3H 6D 6H 8S 8H 10C 10D QD QH AD AH KC"
        })

      {:ok, room, _} = Room.start_game(room, :p1, deal)
      assert room.status == :waiting
      assert room.game.instant_winners != []
      assert room.last_winner == nil
      {:ok, room, _} = Room.start_game(room, :p1, 11)
      assert room.game.mode == :card_led or Game.instant_win?(room.game)
    end

    test "if the previous winner left, the next game is card-led", %{room: room} do
      room = %{room | last_winner: :p3, games_played: 1} |> Room.leave(:p3) |> ok!()
      {:ok, room, _} = Room.start_game(room, :p1, 5)
      assert room.game.mode == :card_led or Game.instant_win?(room.game)
    end
  end

  describe "leaving and disconnects (S5, S6, X3)" do
    test "leaving during a game removes the player from it and frees the seat; host passes on" do
      room = room_with([:p1, :p2, :p3]) |> Room.start_game(:p1, three_hands()) |> ok!()
      {:ok, room, events} = Room.leave(room, :p1)
      assert {:removed, 0} in events
      assert {:left, 0} in events
      assert {:host_changed, 1} in events
      refute Map.has_key?(room.seats, 0)
      assert room.game.removed == [0]
      assert room.status == :playing
    end

    test "disconnect keeps the seat; the timeout removes from the game and moves host" do
      room = room_with([:p1, :p2, :p3]) |> Room.start_game(:p1, three_hands()) |> ok!()
      room = room |> Room.disconnect(:p1) |> ok!()
      assert room.host == 0
      {:ok, room, events} = Room.disconnect_timeout(room, :p1)
      assert {:removed, 0} in events
      assert {:host_changed, 1} in events
      assert Map.has_key?(room.seats, 0)
      assert room.game.removed == [0]
    end

    test "removals that leave one player end the game" do
      room =
        room_with([:p1, :p2]) |> Room.start_game(:p1, hands(%{0 => "3S 9H", 1 => "4S"})) |> ok!()

      {:ok, room, events} = Room.leave(room, :p2)
      assert {:game_over, [[0], [1]]} in events
      assert room.status == :waiting
      assert room.last_winner == :p1
    end

    test "a timeout after reconnecting does nothing" do
      room = room_with([:p1, :p2]) |> Room.disconnect(:p2) |> ok!()
      room = ok!(Room.join(room, :p2, "back"))
      assert Room.disconnect_timeout(room, :p2) == {:ok, room, []}
    end

    test "host transfer prefers connected players, in seat order after the old host" do
      room = room_with([:p1, :p2, :p3, :p4])
      room = room |> Room.disconnect(:p2) |> ok!() |> Room.disconnect(:p1) |> ok!()
      {:ok, room, events} = Room.disconnect_timeout(room, :p1)
      assert {:host_changed, 2} in events
      assert room.host == 2
    end

    test "the last player leaving empties the room" do
      room = room_with([:p1]) |> Room.leave(:p1) |> ok!()
      assert room.seats == %{}
      assert room.host == nil
    end
  end

  describe "view/2" do
    test "public players plus the player's own game view" do
      room =
        room_with([:p1, :p2])
        |> Room.start_game(:p1, hands(%{0 => "3S 9H", 1 => "4S 4C"}))
        |> ok!()

      v = Room.view(room, :p2)
      assert v.me == 1
      assert [%{seat: 0, host: true, connected: true}, %{seat: 1, host: false}] = v.players
      assert v.game.hand == cards("4S 4C")
      assert v.game.card_counts == %{0 => 2, 1 => 2}
      assert Room.view(room, :stranger).game.hand == []
    end
  end
end
