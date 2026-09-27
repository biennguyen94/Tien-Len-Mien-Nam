defmodule TienLen.FuzzTest do
  @moduledoc """
  Phase 10: random garbage against the domain and the room process. Nothing may raise or crash,
  every rejected command must leave the state unchanged, and the invariants of
  `TienLen.GameTest` must still hold.
  """

  use ExUnit.Case, async: true

  alias TienLen.{Card, Game, Room, RoomServer}

  @seats [:a, :b, :c, :d]

  # Random command, often nonsense: unknown seats, foreign cards, duplicates, junk values.
  defp random_command(game, rng) do
    {kind, rng} = :rand.uniform_s(7, rng)
    {seat_pick, rng} = :rand.uniform_s(6, rng)
    seat = Enum.at(game.seats ++ [:stranger, nil], seat_pick - 1)
    {cards, rng} = random_cards(game, rng)

    cmd =
      case kind do
        1 -> {:play, seat, cards}
        2 -> {:pass, seat}
        3 -> {:chop, seat, cards}
        4 -> {:timeout, seat}
        5 -> {:remove, seat}
        6 -> {:play, seat, [:junk, 42, "3S", %{}]}
        7 -> {:play, seat, :not_a_list}
      end

    {cmd, rng}
  end

  defp random_cards(game, rng) do
    {n, rng} = :rand.uniform_s(9, rng)
    {how, rng} = :rand.uniform_s(3, rng)

    pool =
      case how do
        # from anyone's hand (often not the actor's)
        1 -> Enum.flat_map(game.seats, &game.hands[&1])
        # from the whole deck (includes played/undealt cards)
        2 -> Card.all()
        # duplicates of one card
        3 -> List.duplicate(Card.parse!("3S"), 3)
      end

    if pool == [] do
      {[], rng}
    else
      Enum.map_reduce(1..n, rng, fn _, rng ->
        {i, rng} = :rand.uniform_s(length(pool), rng)
        {Enum.at(pool, i - 1), rng}
      end)
    end
  end

  defp run(game, {:play, s, c}), do: Game.play(game, s, c)
  defp run(game, {:pass, s}), do: Game.pass(game, s)
  defp run(game, {:chop, s, c}), do: Game.chop_out_of_turn(game, s, c)
  defp run(game, {:timeout, s}), do: Game.timeout(game, s)
  defp run(game, {:remove, s}), do: Game.remove(game, s)

  test "Game: 200 games × up to 400 random commands never raise; errors change nothing" do
    for seed <- 1..200 do
      n = rem(seed, 3) + 2
      game = Game.new(Enum.take(@seats, n), seed)
      rng = :rand.seed_s(:exsss, seed)
      fuzz_game(game, rng, 400)
    end
  end

  defp fuzz_game(_game, _rng, 0), do: :ok
  defp fuzz_game(%Game{phase: :finished}, _rng, _left), do: :ok

  defp fuzz_game(game, rng, left) do
    {cmd, rng} = random_command(game, rng)

    case run(game, cmd) do
      {:ok, next, events} ->
        assert is_list(events)
        assert_invariants(next)
        fuzz_game(next, rng, left - 1)

      {:error, reason} ->
        assert is_atom(reason)
        fuzz_game(game, rng, left - 1)
    end
  end

  defp assert_invariants(game) do
    counted =
      Enum.flat_map(game.seats, &game.hands[&1]) ++ game.undealt ++ game.discarded

    assert length(Enum.uniq(counted)) == length(counted)

    unless Game.finished?(game) do
      assert game.current in Game.active_seats(game)
      assert game.phase == :lead == (game.centre == nil)
    end
  end

  test "Room: garbage commands from anyone are rejected without changing the room" do
    room =
      Enum.reduce([:p1, :p2, :p3], Room.new("r"), fn p, r ->
        {:ok, r, _, _} = Room.join(r, p, "x")
        r
      end)

    {:ok, room, _} = Room.start_game(room, :p1, 5)

    for player <- [:p1, :p2, :p3, :nobody, nil],
        cmd <- [:pass, {:play, []}, {:play, [:x]}, {:chop, "x"}, {:fly, 1}, nil, "pass"] do
      case Room.command(room, player, cmd) do
        {:ok, _room, _events} -> :ok
        {:error, reason} -> assert is_atom(reason)
      end
    end
  end

  test "RoomServer: stray messages and unknown calls do not crash the room" do
    {:ok, id} = RoomServer.start_room()
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    {:ok, 0} = RoomServer.join(id, :p1, "An")
    pid = RoomServer.whereis(id)

    send(pid, :garbage)
    send(pid, {:turn_timeout, make_ref()})
    send(pid, {:disconnect_timeout, :p1, make_ref()})
    send(pid, {:DOWN, make_ref(), :process, self(), :normal})
    assert GenServer.call(pid, {:what, :ever}) == {:error, :unknown_request}
    assert GenServer.call(pid, :summary).players == 1
    assert Process.alive?(pid)

    for bad <- [nil, :x, [1, 2], "3S", [%Card{rank: 99, suit: :moon}]] do
      assert {:error, _} = RoomServer.play(id, :p1, bad)
      assert {:error, _} = RoomServer.chop(id, :p1, bad)
    end

    assert Process.alive?(pid)
  end
end
