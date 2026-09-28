defmodule TienLen.BotTest do
  @moduledoc "Hints (H1) and bots (B1–B6): pure behaviour and bots in rooms."
  use ExUnit.Case, async: true

  alias TienLen.{Bot, Card, Combination, Game, Hint, Room, RoomServer}

  defp cards(codes), do: Card.parse_many!(codes)
  defp hands(map), do: Map.new(map, fn {seat, codes} -> {seat, cards(codes)} end)

  describe "hints (H1)" do
    test "candidates include sets, straights and runs of pairs; never a straight with a 2" do
      c = Hint.candidates(cards("3S 3C 4S 4D 5H 5C 6D 2H"))
      assert cards("3S 3C") in Enum.map(c, &Card.sort/1)
      assert Enum.any?(c, &(Combination.classify!(&1).type == :straight and length(&1) == 4))
      assert Enum.any?(c, &(Combination.classify!(&1).type == :three_pair))

      refute Enum.any?(
               c,
               &(Combination.classify!(&1).type == :straight and
                   Enum.any?(&1, fn x -> x.rank == 15 end))
             )
    end

    test "every hint is legal; on the first lead they all hold the opening card (300 deals)" do
      for seed <- 1..300 do
        game = Game.new([0, 1, 2, 3], seed)

        if game.phase != :finished do
          moves = Hint.moves(game, game.current)
          assert moves != []
          for m <- moves, do: assert(Game.check_play(game, game.current, m) == :ok)
          if game.opening_card, do: assert(Enum.all?(moves, &(game.opening_card in &1)))
          assert Hint.moves(game, rem(game.current + 1, 4)) == []
        end
      end
    end

    test "answers: weakest first, and an empty list means no single card beats either" do
      game = Game.start([0, 1], hands(%{0 => "3S 9H", 1 => "4C 8D 10S 2S"}), [], leader: 0)
      {:ok, game, _} = Game.play(game, 0, cards("9H"))
      assert [first | _] = Hint.moves(game, 1)
      assert first == cards("10S")
      assert cards("2S") in Hint.moves(game, 1)

      game = Game.start([0, 1], hands(%{0 => "3S 2H", 1 => "4C 8D"}), [], leader: 0)
      {:ok, game, _} = Game.play(game, 0, cards("2H"))
      assert Hint.moves(game, 1) == []
    end

    test "out-of-turn four-pair chops of a 2" do
      h = hands(%{0 => "2H 9C 9D", 1 => "3S 8H", 2 => "4S 4C 5S 5C 6S 6C 7S 7C KD"})
      game = Game.start([0, 1, 2], h, [], leader: 0)
      {:ok, game, _} = Game.play(game, 0, cards("2H"))
      assert [chop] = Hint.chops(game, 2)
      assert Game.check_chop_out_of_turn(game, 2, chop) == :ok
      assert Hint.chops(game, 1) == []
    end
  end

  describe "bot decisions" do
    test "easy leads its lowest single" do
      game = Game.start([0, 1], hands(%{0 => "5S 5C 9H KD", 1 => "3S 4H"}), [], leader: 0)
      assert Bot.decide(game, 0, :easy) == {:play, cards("5S")}
    end

    test "normal leads the biggest group holding its lowest card" do
      game = Game.start([0, 1], hands(%{0 => "5S 6C 7H 9D KD", 1 => "3S 4H"}), [], leader: 0)
      assert Bot.decide(game, 0, :normal) == {:play, cards("5S 6C 7H")}
      game = Game.start([0, 1], hands(%{0 => "5S 5C 9D KD", 1 => "3S 4H"}), [], leader: 0)
      assert Bot.decide(game, 0, :normal) == {:play, cards("5S 5C")}
    end

    test "normal keeps its 2s unless pressed; plays out its last cards" do
      h = %{0 => "3S 3H 5H 6H 8H 9D JC QC", 1 => "2D 2H 4C 7D 9S KD"}
      game = Game.start([0, 1], hands(h), [], leader: 0)
      {:ok, game, _} = Game.play(game, 0, cards("3S 3H"))
      assert Bot.decide(game, 1, :normal) == :pass

      h = %{0 => "3S 3H 5H 6H 8H", 1 => "2D 2H 4C 7D 9S KD"}
      game = Game.start([0, 1], hands(h), [], leader: 0)
      {:ok, game, _} = Game.play(game, 0, cards("3S 3H"))
      assert Bot.decide(game, 1, :normal) == {:play, cards("2D 2H")}

      game = Game.start([0, 1], hands(%{0 => "3S 9H", 1 => "10C 10D"}), [], leader: 0)
      {:ok, game, _} = Game.play(game, 0, cards("3S"))
      assert {:play, [_]} = Bot.decide(game, 1, :normal)
    end

    test "normal does not break a pair when a single will do" do
      game = Game.start([0, 1], hands(%{0 => "3S 9H 10H", 1 => "8C 8D JS QD 4C"}), [], leader: 0)
      {:ok, game, _} = Game.play(game, 0, cards("3S"))
      assert Bot.decide(game, 1, :normal) == {:play, cards("4C")}
    end

    test "normal chops a 2 out of turn; easy never does" do
      h = hands(%{0 => "2H 9C 9D", 1 => "3S 8H", 2 => "4S 4C 5S 5C 6S 6C 7S 7C KD"})
      game = Game.start([0, 1, 2], h, [], leader: 0)
      {:ok, game, _} = Game.play(game, 0, cards("2H"))
      assert Bot.chop(game, 2, :normal) == cards("4S 4C 5S 5C 6S 6C 7S 7C")
      assert Bot.chop(game, 2, :easy) == nil
    end

    test "bots alone finish 200 games with only legal commands" do
      for seed <- 1..200 do
        n = rem(seed, 3) + 2
        seats = Enum.to_list(0..(n - 1))
        levels = Map.new(seats, &{&1, if(rem(&1 + seed, 2) == 0, do: :normal, else: :easy)})
        game = Game.new(seats, seed)
        assert %Game{phase: :finished} = play_out(game, levels, 1_000)
      end
    end
  end

  defp play_out(%Game{phase: :finished} = game, _levels, _left), do: game

  defp play_out(game, levels, left) when left > 0 do
    chop =
      Enum.find_value(Game.active_seats(game), fn seat ->
        cards = seat != game.current && Bot.chop(game, seat, levels[seat])
        if cards, do: {seat, cards}
      end)

    result =
      case chop do
        {seat, cards} ->
          Game.chop_out_of_turn(game, seat, cards)

        nil ->
          case Bot.decide(game, game.current, levels[game.current]) do
            {:play, cards} -> Game.play(game, game.current, cards)
            :pass -> Game.pass(game, game.current)
          end
      end

    assert {:ok, game, _events} = result
    play_out(game, levels, left - 1)
  end

  describe "bots in rooms (B1–B5)" do
    defp room!(opts \\ []) do
      {:ok, id} = RoomServer.start_room(opts)
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      id
    end

    test "host only, waiting only, stake 0 only, up to 4 seats; removable" do
      id = room!()
      {:ok, 0} = RoomServer.join(id, :host, "Host")
      {:ok, 1} = RoomServer.join(id, :guest, "Guest")
      assert RoomServer.add_bot(id, :guest, :easy) == {:error, :not_host}
      assert RoomServer.add_bot(id, :host, :genius) == {:error, :unknown_command}
      assert :ok = RoomServer.add_bot(id, :host, :easy)
      assert :ok = RoomServer.add_bot(id, :host, :normal)
      assert RoomServer.add_bot(id, :host, :easy) == {:error, :room_full}

      view = RoomServer.view(id, :host)

      assert [
               %{bot: nil},
               %{bot: nil},
               %{bot: :easy, name: "Máy 1 (dễ)"},
               %{bot: :normal, name: "Máy 2 (thường)"}
             ] =
               view.players

      assert RoomServer.set_stake(id, :host, 100) == {:error, :bots_need_free_room}
      assert RoomServer.remove_bot(id, :guest, 2) == {:error, :not_host}
      assert RoomServer.remove_bot(id, :host, 1) == {:error, :not_found}
      assert :ok = RoomServer.remove_bot(id, :host, 2)
      assert length(RoomServer.view(id, :host).players) == 3

      id2 = room!(stake: 100)
      {:ok, _} = RoomServer.join(id2, :host, "Host")
      assert RoomServer.add_bot(id2, :host, :easy) == {:error, :bots_need_free_room}
    end

    test "a human against 3 bots: the bots play, the game ends, nothing is recorded" do
      id = room!(turn_timeout: 30)
      {:ok, _} = RoomServer.join(id, :me, "Me")
      for level <- [:easy, :normal, :normal], do: :ok = RoomServer.add_bot(id, :me, level)
      RoomServer.subscribe(id)
      :ok = RoomServer.start_game(id, :me)
      # the first update may already end the game (instant win)
      assert wait_game_over(id, 10_000)

      state = :sys.get_state(RoomServer.whereis(id))
      assert Room.result(state.room) == nil
      assert state.room.last_winner != nil or Game.instant_win?(state.room.game)
    end

    test "hints for the current player are legal" do
      id = room!(turn_timeout: 60_000, bot_delay: 60_000)
      {:ok, _} = RoomServer.join(id, :a, "A")
      {:ok, _} = RoomServer.join(id, :b, "B")
      :ok = RoomServer.start_game(id, :a)
      room = :sys.get_state(RoomServer.whereis(id)).room

      if room.status == :playing do
        current = if room.seats[room.game.current].player_id == :a, do: :a, else: :b
        hints = RoomServer.hints(id, current)
        assert hints != []
        for h <- hints, do: assert(RoomServer.check(id, current, {:play, h}) == :ok)
      end
    end

    test "bots never become host; the room closes when only bots are left" do
      id = room!()
      {:ok, _} = RoomServer.join(id, :host, "Host")
      :ok = RoomServer.add_bot(id, :host, :easy)
      {:ok, _} = RoomServer.join(id, :guest, "Guest")
      :ok = RoomServer.leave(id, :host)
      assert %{host: host, players: players} = RoomServer.view(id, :guest)
      assert Enum.find(players, &(&1.seat == host)).name == "Guest"

      ref = Process.monitor(RoomServer.whereis(id))
      :ok = RoomServer.leave(id, :guest)
      assert_receive {:DOWN, ^ref, :process, _, :normal}, 1_000
    end
  end

  defp wait_game_over(id, timeout) do
    receive do
      {:room_updated, ^id, _, events} ->
        if Enum.any?(events, &(elem(&1, 0) == :game_over)),
          do: true,
          else: wait_game_over(id, timeout)
    after
      timeout -> false
    end
  end
end
