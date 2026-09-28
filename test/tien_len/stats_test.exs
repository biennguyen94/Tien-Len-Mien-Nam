defmodule TienLen.StatsTest do
  use TienLen.DataCase, async: true

  import ExUnit.CaptureLog

  alias TienLen.{Accounts, Card, Room, RoomServer, Stats}

  defp user!(name) do
    {:ok, u} =
      Accounts.register_user(%{
        display_name: name,
        username: String.downcase(name) <> "_#{System.unique_integer([:positive])}",
        password: "mat-khau-123"
      })

    u
  end

  # places: list of {user, place} in seat order; removed: users removed from the game
  defp game(placed, opts \\ []) do
    removed = Keyword.get(opts, :removed, [])

    %{
      room_id: "r1",
      player_count: length(placed),
      instant_win: Keyword.get(opts, :instant, false),
      players:
        for {{user, place}, seat} <- Enum.with_index(placed) do
          %{user_id: user.id, seat: seat, place: place, won: place == 1, removed: user in removed}
        end
    }
  end

  describe "record/1 and leaderboard/1 (A1, Y5)" do
    test "counts 1st places, games and win rate" do
      [a, b, c, d] = Enum.map(~w(An Binh Chi Dung), &user!/1)

      {:ok, _} = Stats.record(game([{a, 1}, {b, 2}, {c, 3}, {d, 4}]))
      {:ok, _} = Stats.record(game([{a, 2}, {b, 1}, {c, 3}]))
      {:ok, _} = Stats.record(game([{a, 1}, {b, 2}]))

      rows = Stats.leaderboard()
      mine = fn u -> Enum.find(rows, &(&1.user_id == u.id)) end

      assert %{wins: 2, games: 3, rank: 1} = mine.(a)
      assert %{wins: 1, games: 3, rank: 2} = mine.(b)
      assert %{wins: 0, games: 2} = mine.(c)
      assert %{wins: 0, games: 1} = mine.(d)
      assert_in_delta mine.(a).win_rate, 2 / 3, 1.0e-9
    end

    test "ties: win rate, then fewer games, then username" do
      [x, y, z, w] = Enum.map(~w(Xa Yen Zoe Wu), &user!/1)
      # x: 1 win / 1 game; y: 1 win / 2 games; z: 1 win / 2 games; w: 0 / 2
      {:ok, _} = Stats.record(game([{x, 1}, {w, 2}]))
      {:ok, _} = Stats.record(game([{y, 1}, {w, 2}]))
      {:ok, _} = Stats.record(game([{y, 2}, {z, 1}]))
      {:ok, _} = Stats.record(game([{z, 2}, {x, 3}, {y, 4}]))

      order =
        Stats.leaderboard()
        |> Enum.map(& &1.user_id)
        |> Enum.filter(&(&1 in [x.id, y.id, z.id, w.id]))

      # x: 1 win / 2 games (0.5), z: 1 / 2 (0.5), y: 1 / 3, w: 0 / 2.
      # x and z tie on wins, rate and games → username order ("xa_…" < "zoe_…").
      assert order == [x.id, z.id, y.id, w.id]
    end

    test "among players without a win, fewer games ranks higher" do
      [top, few, many] = Enum.map(~w(Top Few Many), &user!/1)
      {:ok, _} = Stats.record(game([{top, 1}, {few, 2}, {many, 3}]))
      {:ok, _} = Stats.record(game([{top, 1}, {many, 2}]))
      {:ok, _} = Stats.record(game([{top, 1}, {many, 2}]))

      order =
        Stats.leaderboard()
        |> Enum.map(& &1.user_id)
        |> Enum.filter(&(&1 in [top.id, few.id, many.id]))

      # few: 0 wins / 1 game, many: 0 wins / 3 games → both 0%, fewer games first
      assert order == [top.id, few.id, many.id]
    end

    test "instant win: every instant winner wins, others tie at place 2 (Y5)" do
      [a, b, c] = Enum.map(~w(An Binh Chi), &user!/1)
      {:ok, g} = Stats.record(game([{a, 1}, {b, 1}, {c, 2}], instant: true))
      assert g.instant_win

      rows = Stats.leaderboard()
      assert Enum.find(rows, &(&1.user_id == a.id)).wins == 1
      assert Enum.find(rows, &(&1.user_id == b.id)).wins == 1
      assert Enum.find(rows, &(&1.user_id == c.id)).wins == 0
    end

    test "a removed player's game counts as played" do
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      {:ok, _} = Stats.record(game([{a, 1}, {b, 2}], removed: [b]))
      assert %{games: 1, wins: 0} = Stats.user_standing(b.id)
      assert [%{removed: true}] = Stats.history(b.id)
    end

    test "non-account player ids are ignored; nothing to record is :skipped" do
      a = user!("An")

      result = %{
        room_id: "r",
        player_count: 2,
        instant_win: false,
        players: [
          %{user_id: a.id, seat: 0, place: 1, won: true, removed: false},
          %{user_id: :guest, seat: 1, place: 2, won: false, removed: false}
        ]
      }

      {:ok, _} = Stats.record(result)
      assert %{games: 1} = Stats.user_standing(a.id)

      assert Stats.record(%{
               result
               | players: [%{user_id: "x", seat: 0, place: 1, won: true, removed: false}]
             }) == :skipped
    end

    test "users without games are not listed; standing is nil" do
      u = user!("Lonely")
      refute Enum.any?(Stats.leaderboard(), &(&1.user_id == u.id))
      assert Stats.user_standing(u.id) == nil
    end

    test "a successful record broadcasts :stats_updated" do
      Stats.subscribe()
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      {:ok, _} = Stats.record(game([{a, 1}, {b, 2}]))
      assert_receive {:stats_updated}
    end

    test "deleting a user deletes their results" do
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      {:ok, _} = Stats.record(game([{a, 1}, {b, 2}]))
      Repo.delete!(a)
      refute Enum.any?(Stats.leaderboard(), &(&1.user_id == a.id))
      assert %{games: 1} = Stats.user_standing(b.id)
    end
  end

  describe "history/2" do
    test "newest first, with every player's place" do
      [a, b, c] = Enum.map(~w(An Binh Chi), &user!/1)
      {:ok, _} = Stats.record(game([{a, 2}, {b, 1}]))
      {:ok, _} = Stats.record(game([{a, 1}, {b, 3}, {c, 2}]))

      [latest, older] = Stats.history(a.id)
      assert latest.id > older.id
      assert %{won: true, place: 1, player_count: 3} = latest

      assert Enum.map(latest.players, &{&1.display_name, &1.place, &1.me}) ==
               [{"An", 1, true}, {"Chi", 2, false}, {"Binh", 3, false}]

      assert %{won: false, place: 2} = older
      assert Stats.history(a.id, 1) |> length() == 1
    end
  end

  describe "rooms record results (integration)" do
    defp cards(codes), do: Card.parse_many!(codes)

    defp room_with_recorder(recorder, hands) do
      deal = {:hands, Map.new(hands, fn {seat, codes} -> {seat, cards(codes)} end)}
      {:ok, id} = RoomServer.start_room(recorder: recorder, deals: [deal])
      pid = RoomServer.whereis(id)
      Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
      id
    end

    test "a game played to the end is stored with places" do
      [a, b, c] = Enum.map(~w(An Binh Chi), &user!/1)
      id = room_with_recorder(Stats, %{0 => "3S", 1 => "4S 9C", 2 => "5S 9D"})
      for u <- [a, b, c], do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
      :ok = RoomServer.start_game(id, a.id)

      :ok = RoomServer.play(id, a.id, cards("3S"))
      :ok = RoomServer.play(id, b.id, cards("4S"))
      :ok = RoomServer.play(id, c.id, cards("5S"))
      # round ends (a finished): owner c leads, b plays last card
      :ok = RoomServer.pass(id, b.id)
      :ok = RoomServer.play(id, c.id, cards("9D"))

      assert [%{place: 1, won: true, player_count: 3}] = Stats.history(a.id)
      assert [%{place: 2}] = Stats.history(c.id)
      assert [%{place: 3, won: false}] = Stats.history(b.id)
    end

    test "results use the players dealt in, even if one left the room mid-game" do
      [a, b, c] = Enum.map(~w(An Binh Chi), &user!/1)
      id = room_with_recorder(Stats, %{0 => "3S 9H", 1 => "4S 9C", 2 => "5S 9D"})
      for u <- [a, b, c], do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
      :ok = RoomServer.start_game(id, a.id)

      :ok = RoomServer.leave(id, c.id)
      :ok = RoomServer.leave(id, b.id)

      assert [%{place: 1, won: true}] = Stats.history(a.id)
      assert [%{removed: true, place: 2}] = Stats.history(c.id)
      assert [%{removed: true, place: 3}] = Stats.history(b.id)
    end

    defmodule Exploding do
      def record(_result), do: raise("database down")
    end

    test "a failing recorder is logged and does not stop the room (Y6)" do
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      id = room_with_recorder(Exploding, %{0 => "3S", 1 => "4S 9C"})
      for u <- [a, b], do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
      :ok = RoomServer.start_game(id, a.id)

      log = capture_log(fn -> assert :ok = RoomServer.play(id, a.id, cards("3S")) end)
      assert log =~ "could not record the game result"
      assert %{status: :waiting, games_played: 1} = RoomServer.view(id, a.id)
    end
  end

  describe "Room.result/1" do
    test "places follow the ranking groups; instant-win losers share place 2" do
      room = %Room{
        id: "r",
        game_players: %{0 => 10, 1 => 11, 2 => 12},
        game: %TienLen.Game{
          phase: :finished,
          seats: [0, 1, 2],
          ranking: [[1], [2, 0]],
          instant_winners: [{1, :six_pairs}],
          removed: []
        }
      }

      assert %{instant_win: true, player_count: 3, players: players} = Room.result(room)

      assert Enum.map(players, &{&1.user_id, &1.place, &1.won}) == [
               {11, 1, true},
               {12, 2, false},
               {10, 2, false}
             ]

      assert Room.result(%Room{}) == nil
    end
  end
end
