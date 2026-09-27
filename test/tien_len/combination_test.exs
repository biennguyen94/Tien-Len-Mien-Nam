defmodule TienLen.CombinationTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Combination, Deck}

  doctest TienLen.Combination

  defp cards(codes), do: Card.parse_many!(codes)
  defp classify(codes), do: Combination.classify(cards(codes))

  defp type(codes) do
    case classify(codes) do
      {:ok, combo} -> combo.type
      {:error, reason} -> reason
    end
  end

  describe "single / pair / triple / four of a kind" do
    test "any single card, including a 2" do
      assert type("3S") == :single
      assert type("2H") == :single
    end

    test "pairs of the same rank, including 2s" do
      assert type("5S 5D") == :pair
      assert type("2S 2H") == :pair
      assert type("5S 6S") == :invalid_combination
    end

    test "triples of the same rank, including 2s" do
      assert type("8S 8D 8H") == :triple
      assert type("2S 2C 2H") == :triple
      assert type("8S 8D 9H") == :invalid_combination
    end

    test "four of a kind, including four 2s and four 3s" do
      assert type("5S 5C 5D 5H") == :four_of_a_kind
      assert type("2S 2C 2D 2H") == :four_of_a_kind
      assert type("3S 3C 3D 3H") == :four_of_a_kind
    end
  end

  describe "straights" do
    test "three or more consecutive ranks, any suits, any input order" do
      assert type("3S 4S 5S") == :straight
      assert type("5H 3C 4D") == :straight
      assert type("9S 10H JD QD") == :straight
      assert type("QS KS AS") == :straight
    end

    test "the longest straight is 3 → A (12 cards)" do
      combo = Combination.classify!(cards("3S 4C 5D 6H 7S 8C 9D 10H JS QC KD AH"))
      assert combo.type == :straight
      assert combo.length == 12
    end

    test "no 2 in a straight and no wrap-around" do
      assert type("KS AS 2S") == :invalid_combination
      assert type("AS 2S 3S") == :invalid_combination
      assert type("2S 3S 4S") == :invalid_combination
      assert type("JS QS KS AS 2S") == :invalid_combination
      assert type("3S 4C 5D 6H 7S 8C 9D 10H JS QC KD AH 2H") == :invalid_combination
    end

    test "gaps and repeated ranks are invalid" do
      assert type("3S 4S 6S") == :invalid_combination
      assert type("3S 4S 4C 5S") == :invalid_combination
      assert type("7S 9D 10H") == :invalid_combination
    end

    test "two cards are never a straight" do
      assert type("3S 4S") == :invalid_combination
    end
  end

  describe "consecutive pairs (đôi thông)" do
    test "three-pair: three consecutive pairs" do
      assert type("3S 3C 4S 4C 5S 5C") == :three_pair
      assert type("9C 9S 10H 10D 8S 8D") == :three_pair
      assert type("QS QC KS KC AS AC") == :three_pair
    end

    test "four-pair: four consecutive pairs" do
      assert type("7S 7H 8S 8D 9S 9C 10H 10D") == :four_pair
      assert type("JS JC QS QC KS KC AS AC") == :four_pair
    end

    test "no 2s in consecutive pairs (D5)" do
      assert type("KS KC AS AC 2S 2C") == :invalid_combination
      assert type("QS QC KS KC AS AC 2S 2C") == :invalid_combination
      assert type("AS AC 2S 2C") == :invalid_combination
    end

    test "five or more consecutive pairs are invalid (Q7)" do
      assert type("3S 3C 4S 4C 5S 5C 6S 6C 7S 7C") == :invalid_combination
      assert type("3S 3C 4S 4C 5S 5C 6S 6C 7S 7C 8S 8C") == :invalid_combination
    end

    test "two pairs, gaps, triples or mixed groups are invalid" do
      assert type("3S 3C 4S 4C") == :invalid_combination
      assert type("3S 3C 5S 5C 6S 6C") == :invalid_combination
      assert type("3S 3C 3D 4S 4C 4D") == :invalid_combination
      assert type("5S 5C 5D 5H 6S 6C") == :invalid_combination
      assert type("9C 9S 10H 10D 9H 8D") == :invalid_combination
    end
  end

  describe "result fields" do
    test "cards are sorted ascending, top is the highest card, length is the count" do
      {:ok, combo} = classify("7H 7S")
      assert combo.cards == cards("7S 7H")
      assert combo.top == Card.parse!("7H")
      assert combo.length == 2

      {:ok, combo} = classify("10H 8S 9D")
      assert combo.cards == cards("8S 9D 10H")
      assert combo.top == Card.parse!("10H")
    end

    test "bomb?/1 is true only for three-pair, four of a kind and four-pair" do
      bombs = ["3S 3C 4S 4C 5S 5C", "5S 5C 5D 5H", "7S 7H 8S 8D 9S 9C 10H 10D"]
      others = ["2H", "2S 2H", "2S 2C 2H", "3S 4S 5S"]

      for codes <- bombs, do: assert(Combination.bomb?(Combination.classify!(cards(codes))))
      for codes <- others, do: refute(Combination.bomb?(Combination.classify!(cards(codes))))
    end
  end

  describe "errors" do
    test "empty input" do
      assert Combination.classify([]) == {:error, :empty}
    end

    test "the same card twice" do
      assert classify("3S 3S") == {:error, :duplicate_cards}
      assert classify("3S 4S 5S 5S") == {:error, :duplicate_cards}
    end

    test "classify!/1 raises on invalid input" do
      assert_raise ArgumentError, fn -> Combination.classify!(cards("3S 5S")) end
    end
  end

  describe "cases from the original repo's compareCards.test.js (with D5 applied)" do
    test "valid" do
      assert type("9C") == :single
      assert type("9C 9D") == :pair
      assert type("9C 9D 9H") == :triple
      assert type("9C 10D 8D") == :straight
      assert type("5D 4S 3C") == :straight
      assert type("9C 9S 10H 10D 8S 8D") == :three_pair
      assert type("9C 9D 9S 9H") == :four_of_a_kind
      assert type("9C 9S 10H 10D 8S 8D 7S 7H") == :four_pair
    end

    test "invalid" do
      assert type("2H KD AD") == :invalid_combination
      assert type("9C 10D") == :invalid_combination
      assert type("9D 10C 10H") == :invalid_combination
      assert type("9D 7S 10H") == :invalid_combination
      assert type("9C 9S 10H 10D 9H 8D") == :invalid_combination
      assert type("9C 9S 10H 10D 7S 7H") == :invalid_combination
      assert type("3C 3S 4S 2C 4H 2H") == :invalid_combination
    end
  end

  describe "exhaustive and cross-checked" do
    test "every 1-, 2- and 3-card set matches the rules" do
      all = Card.all()

      for a <- all, do: assert(Combination.classify([a]) |> ok_type() == :single)

      for {a, i} <- Enum.with_index(all), b <- Enum.drop(all, i + 1) do
        expected = if a.rank == b.rank, do: :pair, else: nil
        assert ok_type(Combination.classify([a, b])) == expected
      end

      indexed = Enum.with_index(all)

      for {a, i} <- indexed, {b, j} <- Enum.drop(indexed, i + 1), c <- Enum.drop(all, j + 1) do
        ranks = Enum.sort([a.rank, b.rank, c.rank])

        expected =
          cond do
            Enum.uniq(ranks) |> length() == 1 ->
              :triple

            ranks == Enum.to_list(hd(ranks)..(hd(ranks) + 2)) and List.last(ranks) != 15 ->
              :straight

            true ->
              nil
          end

        assert ok_type(Combination.classify([a, b, c])) == expected
      end
    end

    test "random sets of 1–13 cards agree with an independent reference classifier" do
      for seed <- 1..3000 do
        deck = Deck.shuffle(Deck.new(), seed)
        size = rem(seed, 13) + 1
        hand = Enum.take(deck, size)

        assert ok_type(Combination.classify(hand)) == reference_type(hand),
               "seed #{seed}: #{Enum.map_join(hand, " ", &Card.to_code/1)}"
      end
    end

    test "random consecutive-pair and straight candidates agree with the reference" do
      # Build near-valid candidates so the long types are exercised, not just random junk.
      for seed <- 1..2000 do
        state = :rand.seed_s(:exsss, seed)
        {start, state} = :rand.uniform_s(12, state)
        {len, state} = :rand.uniform_s(6, state)
        {per_rank, _state} = :rand.uniform_s(2, state)
        start = start + 2

        hand =
          for rank <- start..(start + len - 1)//1,
              rank <= 15,
              suit <- Enum.take(Card.suits(), per_rank),
              do: Card.new(rank, suit)

        if hand != [] do
          assert ok_type(Combination.classify(hand)) == reference_type(hand),
                 "seed #{seed}: #{Enum.map_join(hand, " ", &Card.to_code/1)}"
        end
      end
    end
  end

  defp ok_type({:ok, combo}), do: combo.type
  defp ok_type({:error, _}), do: nil

  # Independent reference: counts per rank, written differently from the implementation.
  defp reference_type(hand) do
    by_rank = Enum.group_by(hand, & &1.rank)
    ranks = by_rank |> Map.keys() |> Enum.sort()
    sizes = ranks |> Enum.map(&length(by_rank[&1]))
    n = length(hand)
    run? = ranks == Enum.to_list(hd(ranks)..List.last(ranks)) and 15 not in ranks

    cond do
      n == 1 -> :single
      sizes == [2] -> :pair
      sizes == [3] -> :triple
      sizes == [4] -> :four_of_a_kind
      n >= 3 and run? and Enum.all?(sizes, &(&1 == 1)) -> :straight
      n == 6 and run? and sizes == [2, 2, 2] -> :three_pair
      n == 8 and run? and sizes == [2, 2, 2, 2] -> :four_pair
      true -> nil
    end
  end
end
