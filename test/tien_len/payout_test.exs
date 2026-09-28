defmodule TienLen.PayoutTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Game, Payout}

  defp cards(codes), do: Card.parse_many!(codes)

  defp start(hands, opts) do
    seats = Keyword.get(opts, :seats, Enum.map(hands, &elem(&1, 0)))

    Game.start(
      seats,
      Map.new(hands, fn {s, c} -> {s, cards(c)} end),
      [],
      Keyword.delete(opts, :seats)
    )
  end

  defp step({:ok, game, events}, acc), do: {game, acc ++ events}

  defp run(game, cmds) do
    Enum.reduce(cmds, {game, []}, fn
      {:play, seat, codes}, {g, acc} -> step(Game.play(g, seat, cards(codes)), acc)
      {:pass, seat}, {g, acc} -> step(Game.pass(g, seat), acc)
      {:chop, seat, codes}, {g, acc} -> step(Game.chop_out_of_turn(g, seat, cards(codes)), acc)
    end)
  end

  defp chains(events), do: for({:chop_chain, c} <- events, do: c)

  describe "chop chains in Game (E3, T23)" do
    test "the E3 example: 2♥ chopped by B, then B's chop by C → B pays C 2 × 2 units" do
      g =
        start(
          [a: "2H 3D", b: "4S 4C 5S 5C 6S 6C 9D", c: "7S 7C 8S 8C 9S 9C 10D"],
          leader: :a
        )

      {_g, events} =
        run(g, [
          {:play, :a, "2H"},
          {:play, :b, "4S 4C 5S 5C 6S 6C"},
          {:play, :c, "7S 7C 8S 8C 9S 9C"},
          {:pass, :a},
          {:pass, :b}
        ])

      assert [%{payer: :b, payee: :c, units: 4, chops: 2}] = chains(events)
      # the chain event comes before the round end
      assert Enum.find_index(events, &match?({:chop_chain, _}, &1)) <
               Enum.find_index(events, &match?({:round_ended, _}, &1))
    end

    test "a single chop of a black 2: 1 unit; a pair 2♠2♥: 3 units" do
      g = start([a: "2S 3D", b: "5S 5C 5D 5H 9D", c: "9C 9H"], leader: :a)

      {_g, events} =
        run(g, [{:play, :a, "2S"}, {:play, :b, "5S 5C 5D 5H"}, {:pass, :c}, {:pass, :a}])

      assert [%{payer: :a, payee: :b, units: 1, chops: 1}] = chains(events)

      g = start([a: "2S 2H 3D", b: "5S 5C 5D 5H 9D", c: "9C 9H"], leader: :a)

      {_g, events} =
        run(g, [{:play, :a, "2S 2H"}, {:play, :b, "5S 5C 5D 5H"}, {:pass, :c}, {:pass, :a}])

      assert [%{payer: :a, payee: :b, units: 3}] = chains(events)
    end

    test "a higher 2 over a 2 is not a chop" do
      g = start([a: "2S 3D", b: "2H 9D", c: "9C 9H"], leader: :a)
      {_g, events} = run(g, [{:play, :a, "2S"}, {:play, :b, "2H"}, {:pass, :c}, {:pass, :a}])
      assert chains(events) == []
    end

    test "an out-of-turn four-pair adds a chop to the chain" do
      g =
        start(
          [
            a: "2D 3D",
            b: "4S 4C 5S 5C 6S 6C KD",
            c: "7S 7C 8S 8C 9S 9C 10S 10C QD"
          ],
          leader: :a
        )

      {_g, events} =
        run(g, [
          {:play, :a, "2D"},
          {:play, :b, "4S 4C 5S 5C 6S 6C"},
          {:chop, :c, "7S 7C 8S 8C 9S 9C 10S 10C"},
          {:pass, :a},
          {:pass, :b}
        ])

      assert [%{payer: :b, payee: :c, units: 4, chops: 2}] = chains(events)
    end

    test "a chain is closed when the game ends in the middle of it" do
      g = start([a: "2H 3D", b: "4S 4C 5S 5C 6S 6C"], leader: :a)
      {g, events} = run(g, [{:play, :a, "2H"}, {:play, :b, "4S 4C 5S 5C 6S 6C"}])
      assert Game.finished?(g)
      assert [%{payer: :a, payee: :b, units: 2}] = chains(events)

      assert Enum.find_index(events, &match?({:chop_chain, _}, &1)) <
               Enum.find_index(events, &match?({:game_over, _}, &1))
    end
  end

  describe "places (T21, C4, E1)" do
    test "the owner's examples with stake 500" do
      assert Payout.places([[:n1], [:n2], [:n3], [:n4]], 500) == [
               %{from: :n4, to: :n1, amount: 500, reason: "place"},
               %{from: :n3, to: :n2, amount: 250, reason: "place"}
             ]

      assert Payout.places([[:n1], [:n2], [:n3]], 500) == [
               %{from: :n3, to: :n1, amount: 500, reason: "place"}
             ]

      assert Payout.places([[:n1], [:n2]], 500) == [
               %{from: :n2, to: :n1, amount: 500, reason: "place"}
             ]
    end

    test "Nhì's half is rounded down (E1)" do
      assert [_, %{amount: 7}] = Payout.places([[1], [2], [3], [4]], 15)
    end

    test "every set of place payments sums to zero" do
      for n <- 2..4, stake <- [10, 11, 500, 999] do
        debts = Payout.places(Enum.map(1..n, &[&1]), stake)

        net =
          Enum.reduce(debts, %{}, fn d, acc ->
            acc
            |> Map.update(d.from, -d.amount, &(&1 - d.amount))
            |> Map.update(d.to, d.amount, &(&1 + d.amount))
          end)

        assert Enum.sum(Map.values(net)) == 0
      end
    end
  end

  describe "game_over/2" do
    @six_pairs "3C 3D 5S 5D 7S 7C 9S 9C JC JD 2S 2D KH"
    @four_threes "3S 3C 3D 3H 5C 7D 9H JS KC 4D 6H 8S 10C"
    @plain "4S 4C 6S 8C 10S QS AS 5H 7H 9D JH KS 2H"
    @plain2 "4D 4H 6C 8D 10H QC AC 5S 7S 9S JS KD 2C"

    test "instant win: every loser pays 2×S to every winner (T22, E2)" do
      g =
        Game.start([:a, :b, :c, :d], %{
          a: cards(@plain),
          b: cards(@six_pairs),
          c: cards(@plain2),
          d: cards(@four_threes)
        })

      assert g.instant_winners == [{:b, :six_pairs}, {:d, :four_threes}]

      debts = Payout.game_over(g, 100)
      assert length(debts) == 4
      assert Enum.all?(debts, &(&1.amount == 200 and &1.reason == "instant_win"))

      assert Enum.sort(Enum.map(debts, &{&1.from, &1.to})) == [
               {:a, :b},
               {:a, :d},
               {:c, :b},
               {:c, :d}
             ]
    end

    test "thối heo: the last player holding cards pays for their 2s to the player just above (T24)" do
      g = start([a: "3S", b: "4S 2S 2H", c: "5S 9C"], leader: :a)
      # a finishes with 3S; b passes; c beats with 5S and, b having passed, the round ends;
      # c leads 9C and finishes; b is last, still holding 4S 2S 2H
      {g, _} = run(g, [{:play, :a, "3S"}, {:pass, :b}, {:play, :c, "5S"}, {:play, :c, "9C"}])
      assert g.ranking == [[:a], [:c], [:b]]

      assert Payout.game_over(g, 100) == [
               %{from: :b, to: :a, amount: 100, reason: "place"},
               %{from: :b, to: :c, amount: 300, reason: "thoi"}
             ]
    end

    test "removed players never pay thối (E4)" do
      g = start([a: "3S", b: "4S 9H", c: "2S 2H 9C"], leader: :a)
      {g, _} = run(g, [{:play, :a, "3S"}])
      {:ok, g, _} = Game.remove(g, :c)
      # b is the last player holding cards: ranking a, b, c(removed)
      assert g.ranking == [[:a], [:b], [:c]]
      assert Payout.thoi(g, 100) == []
      assert Payout.game_over(g, 100) == [%{from: :c, to: :a, amount: 100, reason: "place"}]
    end

    test "stake 0 pays nothing" do
      g = start([a: "3S", b: "2S 2H"], leader: :a)
      {g, _} = run(g, [{:play, :a, "3S"}])
      assert Payout.game_over(g, 0) == []
      assert Payout.chop_chain(%{payer: :a, payee: :b, units: 4}, 0) == []
    end

    test "chopping your own combination (X5) pays nothing" do
      assert Payout.chop_chain(%{payer: :a, payee: :a, units: 4}, 100) == []

      assert Payout.chop_chain(%{payer: :a, payee: :b, units: 4}, 100) == [
               %{from: :a, to: :b, amount: 400, reason: "chop"}
             ]
    end
  end
end
