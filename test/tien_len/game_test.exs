defmodule TienLen.GameTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Combination, Game}

  @seats [:a, :b, :c, :d]

  defp cards(codes), do: Card.parse_many!(codes)

  defp start(hands, opts \\ []) do
    seats = Keyword.get(opts, :seats, @seats)
    hands = Map.new(hands, fn {seat, codes} -> {seat, cards(codes)} end)
    Game.start(seats, hands, [], Keyword.delete(opts, :seats))
  end

  defp ok!({:ok, game, _events}), do: game
  defp ok!(other), do: flunk("expected {:ok, game, events}, got #{inspect(other)}")

  defp play!(game, seat, codes), do: ok!(Game.play(game, seat, cards(codes)))
  defp pass!(game, seat), do: ok!(Game.pass(game, seat))

  describe "starting a game (T2, T3)" do
    test "card-led: the holder of 3♠ leads and must include it" do
      g = start(a: "5S 9H", b: "3S 4D", c: "6C 7C", d: "8D QS")
      assert g.mode == :card_led
      assert {g.phase, g.current, g.opening_card} == {:lead, :b, Card.parse!("3S")}

      assert Game.play(g, :b, cards("4D")) == {:error, :must_include_card}
      assert Game.pass(g, :b) == {:error, :cannot_pass_on_lead}
      g = play!(g, :b, "3S")
      assert g.opening_card == nil
      assert {g.phase, g.current} == {:respond, :c}
    end

    test "example 9: 3♠ undealt, the lowest dealt card (3♦) selects the leader" do
      g = start([a: "5S", b: "3H 9C", c: "3D 4D"], seats: [:a, :b, :c])
      assert {g.current, g.opening_card} == {:c, Card.parse!("3D")}
      assert Game.play(g, :c, cards("4D")) == {:error, :must_include_card}
      assert {:ok, _, _} = Game.play(g, :c, cards("3D"))
    end

    test "winner-led: the given leader leads freely, no opening card" do
      g = start([a: "5S", b: "3S", c: "6C", d: "8D"], leader: :d)
      assert {g.mode, g.current, g.opening_card} == {:winner_led, :d, nil}
      assert {:ok, _, _} = Game.play(g, :d, cards("8D"))
    end

    test "new/3 deals from a seed and does not keep the seed" do
      g = Game.new(@seats, 77)
      assert g == Game.new(@seats, 77)
      assert Enum.all?(@seats, &(length(g.hands[&1]) == 13))
      refute Map.has_key?(Map.from_struct(g), :seed)
      holder = Enum.find(@seats, &(Card.parse!("3S") in g.hands[&1]))
      assert g.current == holder or Game.instant_win?(g)
    end

    test "2 and 3 players: 13 cards each, the rest undealt" do
      for {seats, undealt} <- [{[:a, :b], 26}, {[:a, :b, :c], 13}] do
        g = Game.new(seats, 5)
        assert length(g.undealt) == undealt
        assert Enum.all?(seats, &(length(g.hands[&1]) == 13))
      end
    end

    test "rejects bad seat lists and unknown leaders" do
      assert_raise ArgumentError, fn -> Game.new([:a], 1) end
      assert_raise ArgumentError, fn -> Game.new([:a, :b, :c, :d, :e], 1) end
      assert_raise ArgumentError, fn -> Game.new([:a, :a], 1) end
      assert_raise ArgumentError, fn -> Game.new([:a, :b], 1, leader: :z) end
    end
  end

  describe "turns and rounds (T7–T9, T12)" do
    test "example 1: after everyone else passes, the round owner leads a cleared table" do
      g = start([a: "6S 6C 3H", b: "9S 9C 4H", c: "5C", d: "5D"], leader: :a)
      g = play!(g, :a, "6S 6C")
      g = play!(g, :b, "9S 9C")
      g = pass!(g, :c)
      g = pass!(g, :d)
      assert g.current == :a
      assert {:ok, g, events} = Game.pass(g, :a)
      assert {:round_ended, :b} in events
      assert {g.phase, g.current, g.centre, MapSet.size(g.passed)} == {:lead, :b, nil, 0}
    end

    test "passed players are skipped until the round ends" do
      g = start([a: "3S JS KS", b: "6S 7S", c: "8S 9S", d: "10S QS"], leader: :a)
      g = play!(g, :a, "3S")
      g = pass!(g, :b)
      g = play!(g, :c, "8S")
      g = play!(g, :d, "10S")
      # b already passed: a is next, then c
      assert g.current == :a
      g = play!(g, :a, "JS")
      assert g.current == :c
      assert Game.play(g, :b, cards("6S")) == {:error, :not_your_turn}
    end

    test "example 2: no pass on a lead; a lead timeout plays the lowest single" do
      g = start([a: "KS 4D 9C", b: "5S", c: "6S", d: "7S"], leader: :a)
      assert Game.pass(g, :a) == {:error, :cannot_pass_on_lead}
      assert {:ok, g, events} = Game.timeout(g, :a)
      assert [{:timed_out, :a}, {:played, :a, %Combination{cards: [four_d]}} | _] = events
      assert four_d == Card.parse!("4D")
      assert g.current == :b
    end

    test "a response timeout is a pass" do
      g = start([a: "3S 9H", b: "5S", c: "6S", d: "7S"], leader: :a) |> play!(:a, "3S")
      assert {:ok, g, [{:timed_out, :b}, {:passed, :b}]} = Game.timeout(g, :b)
      assert MapSet.member?(g.passed, :b)
    end

    test "a card-led opening timeout plays the mandatory card" do
      g = start(a: "9H", b: "3S 3C 3D 4D", c: "6C", d: "8D")
      assert {:ok, g, _} = Game.timeout(g, :b)
      assert g.centre.combo.cards == cards("3S")
    end
  end

  describe "chops and chop context in a game" do
    test "example 3: chop chain keeps chop context; a four of a kind can follow a three-pair" do
      g =
        start(
          [a: "2S 9H", b: "4S 4C 5S 5C 6S 6C KH", c: "7S 7C 8S 8C 9S 9C KD", d: "5D 5H 6D 6H QS"],
          leader: :a
        )

      g = play!(g, :a, "2S")
      g = play!(g, :b, "4S 4C 5S 5C 6S 6C")
      assert g.centre.chop_context
      g = play!(g, :c, "7S 7C 8S 8C 9S 9C")
      assert g.centre.chop_context
      assert Game.play(g, :d, cards("5D 5H 6D 6H")) == {:error, :invalid_combination}
    end

    test "example 6: out-of-turn four-pair by a passed player resets passes; next is the seat after the chopper" do
      g =
        start(
          [a: "3S 9H", b: "2S KH", c: "4C QD", d: "5S 5C 6S 6C 7S 7C 8S 8C JD"],
          leader: :a
        )

      g = play!(g, :a, "3S")
      g = play!(g, :b, "2S")
      g = pass!(g, :c)
      g = pass!(g, :d)
      assert MapSet.equal?(g.passed, MapSet.new([:c, :d]))
      assert g.current == :a

      assert {:ok, g, [{:chopped, :d, %Combination{type: :four_pair}}]} =
               Game.chop_out_of_turn(g, :d, cards("5S 5C 6S 6C 7S 7C 8S 8C"))

      assert MapSet.size(g.passed) == 0
      assert {g.current, g.centre.owner, g.centre.chop_context} == {:a, :d, true}
    end

    test "out-of-turn chop needs a chop target and a four-pair" do
      g = start([a: "3S 9H", b: "5S 5C 6S 6C 7S 7C 8S 8C", c: "4C", d: "5D"], leader: :a)
      four_pair = cards("5S 5C 6S 6C 7S 7C 8S 8C")
      assert Game.chop_out_of_turn(g, :b, four_pair) == {:error, :no_chop_target}
      g = play!(g, :a, "3S")
      assert Game.chop_out_of_turn(g, :b, four_pair) == {:error, :no_chop_target}
      assert Game.chop_out_of_turn(g, :c, cards("4C")) == {:error, :not_four_pair}
    end
  end

  describe "finishing and ranking (T11)" do
    test "example 8: when a finisher's play is passed by all, the next seat with cards leads" do
      g = start([a: "KS", b: "3C 4C", c: "5C 6C", d: "7C 8C"], leader: :a)
      assert {:ok, g, events} = Game.play(g, :a, cards("KS"))
      assert {:finished, :a, 1} in events
      g = pass!(g, :b)
      g = pass!(g, :c)
      assert {:ok, g, events} = Game.pass(g, :d)
      assert {:round_ended, :b} in events
      assert {g.phase, g.current} == {:lead, :b}
    end

    test "a finisher's play can still be beaten; the finisher is skipped afterwards" do
      g = start([a: "KS", b: "AC 4C", c: "5C 6C", d: "7C 8C"], leader: :a)
      g = play!(g, :a, "KS")
      g = play!(g, :b, "AC")
      g = pass!(g, :c)
      g = pass!(g, :d)
      assert {g.phase, g.current} == {:lead, :b}
    end

    test "full small game reaches game over with a complete ranking" do
      g = start([a: "3S", b: "4S", c: "5S 9C", d: "6S 9D"], leader: :a)
      g = play!(g, :a, "3S")
      assert g.finished == [:a]
      g = play!(g, :b, "4S")
      assert g.finished == [:a, :b]
      g = play!(g, :c, "5S")
      g = play!(g, :d, "6S")
      g = pass!(g, :c)
      # round ends, d leads
      assert {:ok, g, events} = Game.play(g, :d, cards("9D"))
      assert {:game_over, [[:a], [:b], [:d], [:c]]} in events
      assert Game.finished?(g)
      assert Game.winner(g) == :a
      assert Game.play(g, :c, cards("9C")) == {:error, :game_over}
    end
  end

  describe "disconnect removal (T15, S5)" do
    test "removed players' cards are discarded and they rank after normal finishers" do
      g = start([a: "3S", b: "4S 9S", c: "5S 9C", d: "6S 9D"], leader: :a)
      g = play!(g, :a, "3S")
      assert {:ok, g, [{:removed, :c}]} = Game.remove(g, :c)
      assert g.discarded == cards("5S 9C")
      assert g.hands[:c] == []
      assert {:ok, g, events} = Game.remove(g, :d)
      assert {:game_over, [[:a], [:b], [:c], [:d]]} in events
      assert Game.winner(g) == :a
    end

    test "removing the current responder acts as a pass" do
      g = start([a: "3S 9H", b: "4S 9S", c: "5S 9C", d: "6S 9D"], leader: :a)
      g = play!(g, :a, "3S")
      assert g.current == :b
      assert {:ok, g, _} = Game.remove(g, :b)
      assert g.current == :c
    end

    test "removing the current leader moves the lead to the next active seat, without the opening card" do
      g = start(a: "5S 9H", b: "3S 4D", c: "6C 7C", d: "8D QS")
      assert g.current == :b
      assert {:ok, g, events} = Game.remove(g, :b)
      assert {:lead_moved, :c} in events
      assert {g.phase, g.current, g.opening_card} == {:lead, :c, nil}
    end

    test "if the round owner is removed and everyone passes, the next active seat leads" do
      g = start([a: "3S 9H", b: "4S 9S", c: "5S 9C", d: "6S 9D"], leader: :a)
      g = play!(g, :a, "3S")
      g = ok!(Game.remove(g, :a))
      g = pass!(g, :b)
      g = pass!(g, :c)
      assert {:ok, g, events} = Game.pass(g, :d)
      assert {:round_ended, :b} in events
      assert g.current == :b
    end
  end

  describe "instant win (T18)" do
    @six_pairs "3C 3D 5S 5D 7S 7C 9S 9C JC JD 2S 2D KH"
    @four_threes "3S 3C 3D 3H 5C 7D 9H JS KC 4D 6H 8S 10C"
    @plain "4S 4C 6S 8C 10S QS AS 5H 7H 9D JH KS 2H"
    @plain2 "4D 4H 6C 8D 10H QC AC 5S 7S 9S JS KD 2C"

    test "example 10: ends the game at once; winner 1st, others tied; hands revealed" do
      hands = %{a: cards(@plain), b: cards(@plain2), c: cards(@four_threes), d: cards(@six_pairs)}
      g = Game.start(@seats, hands, [], leader: :a)

      # winner-led: four 3's does not count; six pairs does
      assert Game.finished?(g)
      assert Game.instant_win?(g)
      assert g.instant_winners == [{:d, :six_pairs}]
      assert g.ranking == [[:d], [:a, :b, :c]]
      assert Game.winner(g) == :d

      view = Game.view(g, :a)

      assert view.instant_winners == [
               %{seat: :d, type: :six_pairs, hand: Card.sort(cards(@six_pairs))}
             ]

      assert view.hand == Card.sort(cards(@plain))
    end

    test "four 3's counts in a card-led game; several winners are ordered by seat" do
      hands = %{a: cards(@plain), b: cards(@six_pairs), c: cards(@plain2), d: cards(@four_threes)}
      g = Game.start(@seats, hands)
      assert g.instant_winners == [{:b, :six_pairs}, {:d, :four_threes}]
      assert g.ranking == [[:b, :d], [:a, :c]]
    end
  end

  describe "authority (T17)" do
    test "only the current seat plays; cards must be owned; unknown and inactive seats are rejected" do
      g = start([a: "3S 9H", b: "4S", c: "5S", d: "6S"], leader: :a)
      assert Game.play(g, :b, cards("4S")) == {:error, :not_your_turn}
      assert Game.play(g, :a, cards("4S")) == {:error, :not_your_cards}
      assert Game.play(g, :a, [:garbage]) == {:error, :not_your_cards}
      assert Game.play(g, :a, :garbage) == {:error, :not_your_cards}
      assert Game.play(g, :z, cards("3S")) == {:error, :not_in_game}
      assert Game.pass(g, :b) == {:error, :not_your_turn}
      assert Game.play(g, :a, []) == {:error, :empty}
      assert Game.play(g, :a, cards("3S 3S")) == {:error, :duplicate_cards}
    end

    test "check_* dry runs report errors without changing anything" do
      g = start([a: "3S 9H", b: "4S", c: "5S", d: "6S"], leader: :a)
      assert Game.check_play(g, :a, cards("3S")) == :ok
      assert Game.check_play(g, :a, cards("3S 9H")) == {:error, :invalid_combination}
      assert Game.check_pass(g, :a) == {:error, :cannot_pass_on_lead}
      assert Game.check_chop_out_of_turn(g, :b, cards("4S")) == {:error, :not_four_pair}
    end
  end

  describe "view/2 (T14)" do
    test "shows own hand, counts and public state only" do
      g = start([a: "3S 9H", b: "4S 4C", c: "5S", d: "6S"], leader: :a) |> play!(:a, "3S")
      v = Game.view(g, :b)
      assert v.hand == cards("4S 4C")
      assert v.card_counts == %{a: 1, b: 2, c: 1, d: 1}
      assert v.centre.cards == cards("3S")
      assert v.current == :b
      assert v.must_include == nil
      refute Map.has_key?(v, :hands)

      assert Game.view(g, :stranger).hand == []
    end

    test "the mandatory card is shown only to the leader" do
      g = start(a: "5S", b: "3S 4D", c: "6C", d: "8D")
      assert Game.view(g, :b).must_include == Card.parse!("3S")
      assert Game.view(g, :a).must_include == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Random simulations: a bot plays hundreds of full games with every command.
  # ---------------------------------------------------------------------------

  describe "random simulations" do
    test "invariants hold at every step and every game terminates" do
      kinds =
        for seed <- 1..600, reduce: %{} do
          acc ->
            n = rem(seed, 3) + 2
            seats = Enum.take(@seats, n)
            leader = if rem(seed, 2) == 0, do: Enum.at(seats, rem(seed, n))
            opts = if(leader, do: [leader: leader], else: [])

            game =
              if rem(seed, 3) != 0,
                do: rigged_game(seats, seed, opts),
                else: Game.new(seats, seed, opts)

            rng = :rand.seed_s(:exsss, seed)
            simulate(game, rng, [], 0, seed, acc)
        end

      # the bot must actually exercise every kind of event (out-of-turn chops: ~160 today)
      minimums = %{
        played: 1000,
        passed: 1000,
        round_ended: 500,
        finished: 100,
        game_over: 300,
        removed: 100,
        timed_out: 100,
        chopped: 50,
        lead_moved: 5
      }

      for {kind, min} <- minimums do
        assert Map.get(kinds, kind, 0) >= min,
               "only #{Map.get(kinds, kind, 0)} #{kind} events (want >= #{min}): #{inspect(kinds)}"
      end
    end
  end

  defp simulate(game, _rng, played, steps, seed, _kinds) when steps > 2000,
    do:
      flunk(
        "seed #{seed}: no termination (#{inspect(game.phase)}, #{length(played)} cards played)"
      )

  defp simulate(game, rng, played, steps, seed, kinds) do
    check_invariants(game, played, seed)

    if Game.finished?(game) do
      ranked = List.flatten(game.ranking)

      assert Enum.sort(ranked) == Enum.sort(game.seats),
             "seed #{seed}: ranking #{inspect(game.ranking)}"

      if not Game.instant_win?(game), do: assert(length(Game.active_seats(game)) <= 1)
      kinds
    else
      {action, rng} = pick_action(game, rng)
      {:ok, game2, events} = action.()

      new_played =
        Enum.flat_map(events, fn
          {kind, _seat, %Combination{cards: cards}} when kind in [:played, :chopped] -> cards
          _ -> []
        end)

      kinds = Enum.reduce(events, kinds, &Map.update(&2, elem(&1, 0), 1, fn n -> n + 1 end))
      simulate(game2, rng, played ++ new_played, steps + 1, seed, kinds)
    end
  end

  defp check_invariants(game, played, seed) do
    all =
      Enum.flat_map(game.seats, &game.hands[&1]) ++ played ++ game.undealt ++ game.discarded

    assert length(all) == 52 and length(Enum.uniq(all)) == 52, "seed #{seed}: card conservation"

    if not Game.finished?(game) do
      assert game.current in Game.active_seats(game), "seed #{seed}: current must be active"
      assert length(Game.active_seats(game)) >= 2
      assert game.phase == :lead == (game.centre == nil)
      refute MapSet.member?(game.passed, game.current)
    end

    for seat <- game.finished ++ game.removed, do: assert(game.hands[seat] == [])

    for seat <- game.seats do
      v = Game.view(game, seat)

      visible =
        v.hand ++
          ((v.centre && v.centre.cards) || []) ++ Enum.flat_map(v.instant_winners, & &1.hand)

      others =
        Enum.flat_map(game.seats -- [seat], &game.hands[&1]) ++ game.undealt ++ game.discarded

      revealed = Enum.flat_map(v.instant_winners, & &1.hand)
      leaked = Enum.filter(visible -- revealed, &(&1 in others))
      assert leaked == [], "seed #{seed}: view of #{inspect(seat)} leaks #{inspect(leaked)}"
    end
  end

  # Picks a random legal command (occasionally an illegal one is tried and must be rejected).
  defp pick_action(game, rng) do
    {r, rng} = :rand.uniform_s(100, rng)
    current = game.current
    hand = game.hands[current]
    others = Game.active_seats(game) -- [current]

    chopper =
      Enum.find_value(others, fn seat ->
        Enum.find(candidates(game.hands[seat]), fn cs ->
          Game.check_chop_out_of_turn(game, seat, cs) == :ok
        end)
        |> case do
          nil -> nil
          cs -> {seat, cs}
        end
      end)

    legal =
      hand
      |> candidates()
      |> keep_bombs(hand)
      |> Enum.filter(&(Game.check_play(game, current, &1) == :ok))

    cond do
      r <= 3 ->
        # any active seat, including the one whose turn it is
        active = Game.active_seats(game)
        victim = Enum.at(active, rem(r, length(active)))
        {fn -> Game.remove(game, victim) end, rng}

      r <= 6 ->
        {fn -> Game.timeout(game, current) end, rng}

      r <= 70 and chopper != nil ->
        {seat, cs} = chopper
        {fn -> Game.chop_out_of_turn(game, seat, cs) end, rng}

      r <= 55 and game.phase == :respond ->
        {fn -> Game.pass(game, current) end, rng}

      legal != [] ->
        {i, rng} = :rand.uniform_s(length(legal), rng)
        {fn -> Game.play(game, current, Enum.at(legal, i - 1)) end, rng}

      game.phase == :respond ->
        {fn -> Game.pass(game, current) end, rng}

      true ->
        {fn -> Game.timeout(game, current) end, rng}
    end
  end

  # A dealt game where seat 1 holds a four-pair, seat 0 two 2s and (with 3+ players) seat 2 a
  # three-pair, so out-of-turn chops and chop chains actually happen. Cards are swapped between
  # hands (and the undealt pile), so the deal still has 52 distinct cards.
  defp rigged_game(seats, seed, opts) do
    %{hands: hands, undealt: undealt} = TienLen.Deck.deal(length(seats), seed)
    piles = List.to_tuple(hands ++ [undealt])

    wanted = [
      {1, cards("5S 5C 6S 6C 7S 7C 8S 8C")},
      {0, cards("2S 2H")},
      {2, cards("9S 9C 10S 10C JS JC")}
    ]

    piles =
      Enum.reduce(wanted, piles, fn {target, want}, piles ->
        if target < length(seats), do: gather(piles, target, want), else: piles
      end)

    {hands, [undealt]} = piles |> Tuple.to_list() |> Enum.split(length(seats))
    Game.start(seats, seats |> Enum.zip(hands) |> Map.new(), undealt, opts)
  end

  # Moves each wanted card into pile `target`, giving back one of target's other cards.
  defp gather(piles, target, want) do
    Enum.reduce(want, piles, fn card, piles ->
      from = Enum.find(0..(tuple_size(piles) - 1), &(card in elem(piles, &1)))

      if from == target do
        piles
      else
        give = Enum.find(elem(piles, target), &(&1 not in want))

        piles
        |> put_elem(from, [give | List.delete(elem(piles, from), card)])
        |> put_elem(target, [card | List.delete(elem(piles, target), give)])
      end
    end)
  end

  # Bot heuristic: never break up a four-pair, so out-of-turn chops actually get a chance.
  defp keep_bombs(candidates, hand) do
    case Enum.find(candidates(hand), &(length(&1) == 8)) do
      nil ->
        candidates

      four_pair ->
        Enum.filter(
          candidates,
          &(&1 == four_pair or Enum.all?(&1, fn c -> c not in four_pair end))
        )
    end
  end

  # Candidate card sets from a hand: singles, same-rank groups, straights, consecutive pairs.
  defp candidates(hand) do
    by_rank = Enum.group_by(hand, & &1.rank)

    singles = Enum.map(hand, &[&1])

    groups =
      for {_rank, cs} <- by_rank, k <- 2..4, length(cs) >= k, do: Enum.take(cs, k)

    ranks = by_rank |> Map.keys() |> Enum.sort()

    straights =
      for start <- ranks,
          len <- 3..12,
          run = Enum.to_list(start..(start + len - 1)),
          Enum.all?(run, &Map.has_key?(by_rank, &1)),
          do: Enum.map(run, &List.last(by_rank[&1]))

    pairs =
      for start <- ranks,
          len <- [3, 4],
          run = Enum.to_list(start..(start + len - 1)),
          Enum.all?(run, &(length(Map.get(by_rank, &1, [])) >= 2)),
          do: Enum.flat_map(run, &Enum.take(by_rank[&1], 2))

    singles ++ groups ++ straights ++ pairs
  end
end
