defmodule TienLen.DeckTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Deck}

  defp c(code), do: Card.parse!(code)

  describe "new/0" do
    test "is the 52 cards in ascending order" do
      assert Deck.new() == Card.all()
    end
  end

  describe "shuffle/2" do
    test "is a permutation of the input" do
      shuffled = Deck.shuffle(Deck.new(), 42)
      assert length(shuffled) == 52
      assert Card.sort(shuffled) == Deck.new()
    end

    test "is deterministic for a seed (integer or 3-tuple)" do
      assert Deck.shuffle(Deck.new(), 42) == Deck.shuffle(Deck.new(), 42)
      assert Deck.shuffle(Deck.new(), {1, 2, 3}) == Deck.shuffle(Deck.new(), {1, 2, 3})
    end

    test "different seeds give different orders" do
      orders = for seed <- 1..50, do: Deck.shuffle(Deck.new(), seed)
      assert length(Enum.uniq(orders)) == 50
      refute Deck.shuffle(Deck.new(), 1) == Deck.new()
    end

    test "does not touch the process's global :rand state" do
      :rand.seed(:exsss, {7, 7, 7})
      before = :rand.export_seed()
      Deck.shuffle(Deck.new(), 99)
      assert :rand.export_seed() == before
    end

    test "every card reaches every position (coarse uniformity over fixed seeds)" do
      # 5200 fixed seeds: each card should land first about 100 times.
      counts =
        Enum.reduce(1..5200, %{}, fn seed, acc ->
          first = hd(Deck.shuffle(Deck.new(), seed))
          Map.update(acc, first, 1, &(&1 + 1))
        end)

      assert map_size(counts) == 52
      assert counts |> Map.values() |> Enum.min() > 50
      assert counts |> Map.values() |> Enum.max() < 150
    end

    test "handles tiny lists" do
      assert Deck.shuffle([], 1) == []
      assert Deck.shuffle([c("3S")], 1) == [c("3S")]
    end
  end

  describe "new_seed/0" do
    test "returns distinct 3-integer seeds usable by shuffle/2" do
      {a, b, c} = seed = Deck.new_seed()
      assert Enum.all?([a, b, c], &is_integer/1)
      refute Deck.new_seed() == seed
      assert length(Deck.shuffle(Deck.new(), seed)) == 52
    end
  end

  describe "deal/2 (RULES T1)" do
    for {n, undealt} <- [{2, 26}, {3, 13}, {4, 0}] do
      test "#{n} players: 13 cards each, #{undealt} undealt, 52 distinct in total" do
        %{hands: hands, undealt: rest} = Deck.deal(unquote(n), 7)

        assert length(hands) == unquote(n)
        assert Enum.all?(hands, &(length(&1) == 13))
        assert length(rest) == unquote(undealt)

        all = Enum.concat([rest | hands])
        assert length(Enum.uniq(all)) == 52
        assert Card.sort(all) == Deck.new()
      end
    end

    test "hands and undealt cards are sorted ascending" do
      %{hands: hands, undealt: rest} = Deck.deal(3, 11)
      for hand <- [rest | hands], do: assert(hand == Card.sort(hand))
    end

    test "is deterministic for a seed and differs across seeds" do
      assert Deck.deal(4, 123) == Deck.deal(4, 123)
      refute Deck.deal(4, 123) == Deck.deal(4, 124)
    end

    test "deals round-robin from the shuffled deck" do
      shuffled = Deck.shuffle(Deck.new(), 5)
      %{hands: [h0, h1, h2], undealt: rest} = Deck.deal(3, 5)

      assert h0 == shuffled |> Enum.take(39) |> Enum.take_every(3) |> Card.sort()
      assert h1 == shuffled |> Enum.take(39) |> Enum.drop(1) |> Enum.take_every(3) |> Card.sort()
      assert h2 == shuffled |> Enum.take(39) |> Enum.drop(2) |> Enum.take_every(3) |> Card.sort()
      assert rest == shuffled |> Enum.drop(39) |> Card.sort()
    end

    test "rejects fewer than 2 or more than 4 players" do
      assert_raise FunctionClauseError, fn -> Deck.deal(1, 1) end
      assert_raise FunctionClauseError, fn -> Deck.deal(5, 1) end
    end
  end

  describe "lowest_holder/1 (RULES T2, card-led opening)" do
    test "finds the holder of 3♠" do
      hands = %{
        "a" => Card.parse_many!("5S 2H"),
        "b" => Card.parse_many!("3S KD"),
        "c" => [c("3H")]
      }

      assert Deck.lowest_holder(hands) == {"b", c("3S")}
    end

    test "falls back to 3♣, 3♦, 3♥, 4♠ … when lower cards are undealt" do
      assert Deck.lowest_holder(%{1 => [c("3H")], 2 => [c("3C"), c("AS")]}) == {2, c("3C")}
      assert Deck.lowest_holder(%{1 => [c("3H")], 2 => [c("3D")]}) == {2, c("3D")}
      assert Deck.lowest_holder(%{1 => [c("4S")], 2 => [c("3H")]}) == {2, c("3H")}
      assert Deck.lowest_holder(%{1 => [c("4S"), c("2H")], 2 => [c("4C")]}) == {1, c("4S")}
    end

    test "accepts a list of hands, using the index as the seat" do
      assert Deck.lowest_holder([[c("5S")], [c("4H")], [c("9C")]]) == {1, c("4H")}
    end

    test "only considers the hands it is given (players taking part)" do
      hands = %{1 => [c("3S")], 2 => [c("3C")]}
      assert Deck.lowest_holder(Map.delete(hands, 1)) == {2, c("3C")}
    end

    test "returns nil when nobody holds a card" do
      assert Deck.lowest_holder(%{}) == nil
      assert Deck.lowest_holder(%{1 => []}) == nil
    end

    test "on real deals it returns the holder of the lowest dealt card" do
      for n <- 2..4, seed <- 1..200 do
        %{hands: hands, undealt: undealt} = Deck.deal(n, seed)
        {seat, card} = Deck.lowest_holder(hands)

        assert card in Enum.at(hands, seat)
        assert card == hands |> Enum.concat() |> Card.lowest()
        # every card below the chosen one must be among the undealt cards
        lower = Enum.take_while(Card.all(), &(Card.compare(&1, card) == :lt))
        assert Enum.all?(lower, &(&1 in undealt))
        if n == 4, do: assert(card == c("3S"))
      end
    end
  end
end
