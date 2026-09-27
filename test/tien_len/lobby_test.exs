defmodule TienLen.LobbyTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Lobby, RoomServer}

  defp summary(id), do: Enum.find(Lobby.list_rooms(), &(&1.id == id))

  defp create!(player, name \\ "Host", opts \\ []) do
    {:ok, id, 0} = Lobby.create_room(player, name, opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  # a player process that joins and stays until killed
  defp spawn_join(id, player, name) do
    test = self()

    spawn(fn ->
      send(test, {:join, player, Lobby.join_room(id, player, name)})
      Process.sleep(:infinity)
    end)

    assert_receive {:join, ^player, result}
    result
  end

  describe "names" do
    test "are trimmed, whitespace-collapsed, 1–20 characters, Unicode allowed" do
      assert Lobby.normalize_name("  Bình   An ") == {:ok, "Bình An"}
      assert Lobby.normalize_name("Nguyễn Thị Minh Khai") == {:ok, "Nguyễn Thị Minh Khai"}
      assert Lobby.normalize_name(String.duplicate("ạ", 20)) == {:ok, String.duplicate("ạ", 20)}
    end

    test "rejects empty, too long, control characters and non-strings" do
      for bad <- ["", "   ", String.duplicate("a", 21), "a\u0000b", "a\u0007", <<0xFF>>, nil, 42] do
        assert Lobby.normalize_name(bad) == {:error, :invalid_name}, inspect(bad)
      end
    end

    test "an invalid name is refused before anything is created or joined" do
      assert Lobby.create_room(:p1, "  ") == {:error, :invalid_name}
      id = create!(:p1)
      assert Lobby.join_room(id, :p2, "") == {:error, :invalid_name}
    end
  end

  describe "rooms" do
    test "the creator is seated as host; the room is listed as joinable" do
      id = create!(:p1, "An")

      assert %{players: 1, status: :waiting, host_name: "An", joinable: true, max_players: 4} =
               summary(id)
    end

    test "a full room is not joinable and refuses a fifth player (R6)" do
      id = create!(:p1)
      for p <- [:p2, :p3, :p4], do: assert({:ok, _} = spawn_join(id, p, "x"))
      assert %{players: 4, joinable: false} = summary(id)
      assert spawn_join(id, :p5, "late") == {:error, :room_full}
    end

    test "during a game nobody new joins; seated players reconnect; non-hosts cannot start" do
      deal = {:hands, %{0 => Card.parse_many!("3S 9H"), 1 => Card.parse_many!("4S 9C")}}
      id = create!(:p1, "Host", deals: [deal])
      {:ok, 1} = spawn_join(id, :p2, "B")
      assert Lobby.start_game(id, :p2) == {:error, :not_host}
      assert Lobby.start_game(id, :p1) == :ok

      assert %{status: :playing, joinable: false} = summary(id)
      assert spawn_join(id, :p3, "C") == {:error, :game_in_progress}
      assert Lobby.join_room(id, :p2, "B") == {:ok, 1}
    end

    test "a room with a single player cannot start" do
      id = create!(:p1)
      assert Lobby.start_game(id, :p1) == {:error, :not_enough_players}
    end

    test "joining an unknown room" do
      assert Lobby.join_room("no-such-room", :p1, "A") == {:error, :room_not_found}
    end

    test "joinable rooms are listed first" do
      full = create!(:f1)
      for p <- [:f2, :f3, :f4], do: {:ok, _} = spawn_join(full, p, "x")
      open = create!(:o1)

      ids = Lobby.list_rooms() |> Enum.map(& &1.id) |> Enum.filter(&(&1 in [full, open]))
      assert ids == [open, full]
    end

    test "summaries carry no player ids or cards" do
      id = create!(:secret_player_id, "An")
      s = summary(id)

      assert Map.keys(s) |> Enum.sort() == [
               :host_name,
               :id,
               :joinable,
               :max_players,
               :players,
               :status
             ]

      refute inspect(s) =~ "secret_player_id"
      refute inspect(s) =~ inspect(Card)
    end
  end

  describe "no spectators (#17)" do
    test "only seated players get a room view" do
      id = create!(:p1)
      assert %{me: 0} = Lobby.room_view(id, :p1)
      assert Lobby.room_view(id, :outsider) == {:error, :not_in_room}
    end
  end

  describe "lobby broadcasts" do
    test "joins, leaves, starts and closing are announced" do
      Lobby.subscribe()
      id = create!(:p1)
      assert_receive {:lobby_updated, ^id}

      {:ok, 1} = spawn_join(id, :p2, "B")
      assert_receive {:lobby_updated, ^id}

      :ok = Lobby.leave_room(id, :p2)
      assert_receive {:lobby_updated, ^id}

      :ok = Lobby.leave_room(id, :p1)
      assert_receive {:room_closed, ^id}
      assert summary(id) == nil
    end
  end

  describe "empty rooms" do
    test "a room nobody joins closes after the timeout" do
      Lobby.subscribe()
      {:ok, id} = RoomServer.start_room(disconnect_timeout: 20)
      assert_receive {:room_closed, ^id}, 1_000
    end
  end
end
