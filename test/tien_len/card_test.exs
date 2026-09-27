defmodule TienLen.CardTest do
  use ExUnit.Case, async: true

  alias TienLen.Card

  doctest TienLen.Card

  defp c(code), do: Card.parse!(code)

  describe "order (RULES T4)" do
    test "all/0 lists 52 distinct cards from 3♠ to 2♥" do
      all = Card.all()
      assert length(all) == 52
      assert length(Enum.uniq(all)) == 52
      assert hd(all) == c("3S")
      assert List.last(all) == c("2H")
    end

    test "the full ascending order is ranks 3..A,2 with suits ♠ ♣ ♦ ♥ inside each rank" do
      expected =
        for r <- ~w(3 4 5 6 7 8 9 10 J Q K A 2), s <- ~w(S C D H), do: c(r <> s)

      assert Card.all() == expected
      assert Card.sort(Enum.reverse(expected)) == expected
    end

    test "key/1 is a bijection onto 0..51 that follows the order" do
      assert Enum.map(Card.all(), &Card.key/1) == Enum.to_list(0..51)
    end

    test "rank decides before suit" do
      assert Card.compare(c("4S"), c("3H")) == :gt
      assert Card.compare(c("AH"), c("2S")) == :lt
      assert Card.compare(c("KH"), c("AS")) == :lt
      assert Card.compare(c("10S"), c("9H")) == :gt
    end

    test "suit breaks ties: ♠ < ♣ < ♦ < ♥" do
      assert Card.compare(c("7S"), c("7C")) == :lt
      assert Card.compare(c("7C"), c("7D")) == :lt
      assert Card.compare(c("7D"), c("7H")) == :lt
      assert Card.compare(c("2H"), c("2D")) == :gt
      assert Card.compare(c("QD"), c("QD")) == :eq
    end

    test "works as an Enum.sort/2 module and with highest/lowest" do
      cards = Card.parse_many!("2S 3H 10C AD 3S")
      assert Enum.sort(cards, Card) == Card.parse_many!("3S 3H 10C AD 2S")
      assert Card.highest(cards) == c("2S")
      assert Card.lowest(cards) == c("3S")
    end
  end

  describe "new/2" do
    test "builds valid cards" do
      assert Card.new(15, :hearts) == %Card{rank: 15, suit: :hearts}
    end

    test "rejects invalid rank or suit" do
      assert_raise ArgumentError, fn -> Card.new(2, :hearts) end
      assert_raise ArgumentError, fn -> Card.new(16, :hearts) end
      assert_raise ArgumentError, fn -> Card.new(3, :stars) end
    end
  end

  describe "codes and labels" do
    test "to_code/1 and parse/1 round-trip for all 52 cards" do
      for card <- Card.all() do
        assert Card.parse(Card.to_code(card)) == {:ok, card}
      end
    end

    test "codes use 10, J, Q, K, A, 2 and suit letters" do
      assert Enum.map(Card.parse_many!("3S 10H JC QD KS AH 2D"), &Card.to_code/1) ==
               ~w(3S 10H JC QD KS AH 2D)
    end

    test "parse/1 accepts T for ten and lowercase" do
      assert Card.parse("th") == {:ok, %Card{rank: 10, suit: :hearts}}
      assert Card.parse("as") == {:ok, %Card{rank: 14, suit: :spades}}
    end

    test "parse/1 rejects invalid codes" do
      for bad <- ["", "S", "1S", "11S", "3X", "3", "AA", "10", "02H", " 3S", nil, 3] do
        assert Card.parse(bad) == :error, "expected #{inspect(bad)} to be rejected"
      end
    end

    test "parse!/1 raises on invalid codes" do
      assert_raise ArgumentError, fn -> Card.parse!("1S") end
    end

    test "display/1 and to_string/1 use suit symbols" do
      assert Card.display(c("3S")) == "3♠"
      assert to_string(c("10H")) == "10♥"
      assert Card.display(c("2D")) == "2♦"
      assert Card.display(c("QC")) == "Q♣"
    end
  end
end
