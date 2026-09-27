defmodule TienLen.InstantWinTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Deck, InstantWin}

  defp hand(codes) do
    cards = Card.parse_many!(codes)
    assert length(cards) == 13 and length(Enum.uniq(cards)) == 13, "bad fixture: #{codes}"
    cards
  end

  describe "hand types (RULES §10)" do
    test "four 2's" do
      h = hand("2S 2C 2D 2H 3S 5C 7D 9H JS KC 4D 6H 8S")
      assert InstantWin.detect(h, :winner_led) == :four_twos
    end

    test "six pairs, including pairs of 2s and a four of a kind counted as two pairs" do
      assert InstantWin.detect(hand("3S 3C 5S 5C 7S 7C 9S 9C JS JC 2S 2C KH"), :winner_led) ==
               :six_pairs

      assert InstantWin.detect(hand("7S 7C 7D 7H 4S 4C 9S 9C QS QC AS AC 3H"), :winner_led) ==
               :six_pairs

      # five pairs + a triple also splits into six pairs + one card
      assert InstantWin.detect(hand("3S 3C 5S 5C 7S 7C 9S 9C JS JC KS KC KD"), :winner_led) ==
               :six_pairs
    end

    test "dragon: every rank 3 → A plus any 13th card (a 2 or a duplicate rank)" do
      assert InstantWin.detect(hand("3S 4C 5D 6H 7S 8C 9D 10H JS QC KD AH 2S"), :winner_led) ==
               :dragon

      assert InstantWin.detect(hand("3S 4C 5D 6H 7S 8C 9D 10H JS QC KD AH 7D"), :winner_led) ==
               :dragon
    end

    test "four 3's only in card-led games (I6)" do
      h = hand("3S 3C 3D 3H 5C 7D 9H JS KC 4D 6H 8S 10C")
      assert InstantWin.detect(h, :card_led) == :four_threes
      assert InstantWin.detect(h, :winner_led) == nil
    end
  end

  describe "near misses" do
    test "five pairs and three singles" do
      assert InstantWin.detect(hand("3S 3C 5S 5C 7S 7C 9S 9C JS JC KH AD 2C"), :card_led) == nil
    end

    test "three 2s" do
      assert InstantWin.detect(hand("2S 2C 2D 3S 5C 7D 9H JS KC 4D 6H 8S 10C"), :card_led) == nil
    end

    test "a 3 → K run plus two others is not a dragon" do
      assert InstantWin.detect(hand("3S 4C 5D 6H 7S 8C 9D 10H JS QC KD 2H 2D"), :card_led) == nil
    end

    test "four triples is not an instant win" do
      assert InstantWin.detect(hand("3S 3C 3D 5S 5C 5D 7S 7C 7D 9S 9C 9D JH"), :card_led) == nil
    end
  end

  describe "several qualifications" do
    test "matches/2 lists all types in priority order; detect/2 returns the first" do
      # four 2s + four 3s + two more pairs + one card: four 2's, six pairs, four 3's
      h = hand("2S 2C 2D 2H 3S 3C 3D 3H 5S 5C 7S 7C 9H")
      assert InstantWin.matches(h, :card_led) == [:four_twos, :six_pairs, :four_threes]
      assert InstantWin.matches(h, :winner_led) == [:four_twos, :six_pairs]
      assert InstantWin.detect(h, :card_led) == :four_twos
    end
  end

  describe "winners/2" do
    test "returns instant winners in seat order for a list of hands" do
      # no A, one pair: not a dragon, not six pairs
      normal = hand("3S 3H 5C 7D 9H JS KC 4D 6H 8S 10C QD 2C")
      six_pairs = hand("3C 3D 5S 5D 7S 7C 9S 9C JC JD 2S 2D KH")
      three_twos = hand("2H 2S 2D 4S 6C 8D 10D QS AC 4H 6D 8H KD")
      assert InstantWin.detect(normal, :card_led) == nil
      assert InstantWin.detect(three_twos, :card_led) == nil

      assert InstantWin.winners([normal, six_pairs, three_twos], :winner_led) == [{1, :six_pairs}]
    end

    test "accepts {seat, hand} pairs and keeps their order" do
      six_pairs = hand("3C 3D 5S 5D 7S 7C 9S 9C JC JD 2S 2D KH")
      dragon = hand("3S 4C 5C 6H 7D 8C 9D 10H JS QC KD AH 2H")
      normal = hand("3H 5H 7H 9D JH KS 4H 6S 8D 10S QH QD 2C")
      assert InstantWin.detect(normal, :card_led) == nil

      assert InstantWin.winners([{"c", normal}, {"a", dragon}, {"b", six_pairs}], :card_led) ==
               [{"a", :dragon}, {"b", :six_pairs}]
    end

    test "returns [] when nobody qualifies" do
      assert InstantWin.winners([], :card_led) == []
    end

    test "rejects hands that are not 13 cards" do
      assert_raise FunctionClauseError, fn ->
        InstantWin.detect(Card.parse_many!("2S 2C 2D 2H"), :card_led)
      end
    end
  end

  describe "cross-check on real deals" do
    test "detect/2 agrees with a brute-force reference on 20,000 dealt hands" do
      for seed <- 1..5000, h <- Deck.deal(4, seed).hands, mode <- [:card_led, :winner_led] do
        assert InstantWin.detect(h, mode) == reference(h, mode),
               "seed #{seed}: #{Enum.map_join(h, " ", &Card.to_code/1)}"
      end
    end
  end

  # Brute force: try to remove pairs greedily per rank, check runs by listing ranks.
  defp reference(h, mode) do
    ranks = Enum.map(h, & &1.rank)
    twos = Enum.count(ranks, &(&1 == 15))
    threes = Enum.count(ranks, &(&1 == 3))
    pairs = ranks |> Enum.frequencies() |> Enum.reduce(0, fn {_r, n}, acc -> acc + div(n, 2) end)
    dragon = Enum.all?(3..14, &(&1 in ranks))

    cond do
      twos == 4 -> :four_twos
      dragon -> :dragon
      pairs >= 6 -> :six_pairs
      mode == :card_led and threes == 4 -> :four_threes
      true -> nil
    end
  end
end
