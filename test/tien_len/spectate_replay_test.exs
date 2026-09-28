defmodule TienLen.SpectateReplayTest do
  @moduledoc "Spectators (V1–V4) and replays (V5, V6) in the domain."
  use TienLenWeb.ConnCase, async: true

  alias TienLen.{Admin, Card, Replay, RoomServer, Stats}

  defp cards(codes), do: Card.parse_many!(codes)
  defp deal(map), do: {:hands, Map.new(map, fn {s, c} -> {s, cards(c)} end)}

  defp room!(opts) do
    {:ok, id} = RoomServer.start_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  # the room handles the watcher's :DOWN asynchronously
  defp eventually(fun, tries \\ 100) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(10) && eventually(fun, tries - 1)
    end
  end

  describe "spectators" do
    test "the public view never carries a hand; the count is shown to players" do
      id = room!(deals: [deal(%{0 => "3S 9H 2D", 1 => "4S 9C 5D"})])
      {:ok, _} = RoomServer.join(id, :a, "A")
      {:ok, _} = RoomServer.join(id, :b, "B")
      :ok = RoomServer.start_game(id, :a)

      watcher =
        Task.async(fn ->
          {:ok, view} = RoomServer.watch(id)
          send(self(), :hold)
          view
        end)

      view = Task.await(watcher)
      assert view.me == nil
      assert view.game.hand == []
      assert view.game.card_counts == %{0 => 3, 1 => 3}
      refute Map.has_key?(view, :chat)
      refute inspect(view) =~ "9H"
      refute inspect(view) =~ "9C"

      # the task ended: its monitor removes it
      assert eventually(fn -> RoomServer.spectator_view(id).spectators == 0 end)

      parent = self()

      pid =
        spawn(fn ->
          send(parent, RoomServer.watch(id))
          Process.sleep(:infinity)
        end)

      assert_receive {:ok, _}
      assert RoomServer.view(id, :a).spectators == 1
      Process.exit(pid, :kill)
      assert eventually(fn -> RoomServer.view(id, :a).spectators == 0 end)
    end

    test "at most 20 spectators" do
      id = room!([])
      {:ok, _} = RoomServer.join(id, :a, "A")
      parent = self()

      pids =
        for _ <- 1..21 do
          spawn(fn ->
            send(parent, {:watch, RoomServer.watch(id)})
            Process.sleep(:infinity)
          end)
        end

      results = for _ <- 1..21, do: receive(do: ({:watch, r} -> r))
      assert Enum.count(results, &match?({:ok, _}, &1)) == 20
      assert {:error, :too_many_spectators} in results
      Enum.each(pids, &Process.exit(&1, :kill))
    end
  end

  describe "replays" do
    defmodule Sink do
      @moduledoc false
      def record(result), do: send(:replay_test_sink, {:recorded, result})
    end

    test "a finished game carries dealt hands and public events; frames rebuild it" do
      Process.register(self(), :replay_test_sink)
      hands = %{0 => "3S 2H 9C", 1 => "4S 4C 5S 5C 6S 6C 9D"}
      id = room!(deals: [deal(hands)], recorder: Sink)
      {:ok, _} = RoomServer.join(id, 1, "An")
      {:ok, _} = RoomServer.join(id, 2, "Binh")
      :ok = RoomServer.start_game(id, 1)
      :ok = RoomServer.play(id, 1, cards("3S"))
      :ok = RoomServer.pass(id, 2)
      :ok = RoomServer.play(id, 1, cards("2H"))
      :ok = RoomServer.play(id, 2, cards("4S 4C 5S 5C 6S 6C"))
      :ok = RoomServer.pass(id, 1)
      :ok = RoomServer.play(id, 2, cards("9D"))

      assert_receive {:recorded, %{replay: replay, players: players}}
      assert Enum.find(players, &(&1.seat == 1)).chops == 1
      assert replay["hands"] == %{"0" => ~w(3S 9C 2H), "1" => ~w(4S 4C 5S 5C 6S 6C 9D)}
      assert [%{"seat" => 0, "name" => "An"}, %{"seat" => 1, "name" => "Binh"}] = replay["seats"]
      types = Enum.map(replay["events"], & &1["t"])
      assert "played" in types and "passed" in types and "round_ended" in types
      assert List.last(types) == "game_over"

      # stored as JSON and back
      replay = replay |> Jason.encode!() |> Jason.decode!()
      frames = Replay.frames(replay)
      assert hd(frames).hands[0] == cards("3S 9C 2H")
      last = List.last(frames)
      assert last.hands[1] == []
      assert last.hands[0] == cards("9C")
      chop = Enum.find(frames, &(&1.centre && &1.centre.type == :three_pair))
      assert chop.centre.seat == 1
      assert Replay.names(replay) == %{0 => "An", 1 => "Binh"}
    end

    test "only players of the game and admins may open it; older games have none" do
      _ = login_conn("An")
      _ = login_conn("Binh")
      _ = login_conn("Other")
      _ = login_conn("Boss")
      {:ok, _} = Admin.promote(test_user("Boss").username)
      replay = %{"seats" => [], "hands" => %{}, "events" => []}

      {:ok, game} =
        Stats.record(%{
          room_id: "r",
          ref: "room:r:game:1",
          player_count: 2,
          instant_win: false,
          replay: replay,
          players: [
            %{user_id: test_user("An").id, seat: 0, place: 1, won: true, removed: false},
            %{user_id: test_user("Binh").id, seat: 1, place: 2, won: false, removed: false}
          ]
        })

      assert {:ok, %{replay: ^replay}} = Stats.replay(game.id, test_user("An"))
      assert {:ok, _} = Stats.replay(game.id, TienLen.Accounts.get_user(test_user("Boss").id))
      assert Stats.replay(game.id, test_user("Other")) == {:error, :forbidden}
      assert Stats.replay(-1, test_user("An")) == {:error, :not_found}

      {:ok, old} =
        Stats.record(%{
          room_id: "r",
          player_count: 2,
          instant_win: false,
          players: [%{user_id: test_user("An").id, seat: 0, place: 1, won: true, removed: false}]
        })

      assert Stats.replay(old.id, test_user("An")) == {:error, :no_replay}
      assert [%{has_replay: false}, %{has_replay: true}] = Stats.history(test_user("An").id)
    end
  end
end
