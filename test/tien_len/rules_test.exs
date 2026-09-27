defmodule TienLen.RulesTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Combination, Deck, Rules}

  defp cards(codes), do: Card.parse_many!(codes)
  defp combo(codes), do: Combination.classify!(cards(codes))
  defp centre(codes, context \\ false), do: %{combo: combo(codes), chop_context: context}

  # Play `codes` on the player's own turn against `centre`.
  defp on(codes, centre) do
    case Rules.play(cards(codes), centre) do
      {:ok, _combo, context} -> {:ok, context}
      error -> error
    end
  end

  # Representative chop combinations (low ranks on purpose: cross-type chops ignore rank).
  @three_pair "3S 3C 4S 4C 5S 5C"
  @quad "3S 3C 3D 3H"
  @four_pair "4S 4C 5S 5C 6S 6C 7S 7C"

  describe "same type (RULES §5.1)" do
    test "higher top card wins, suit included" do
      assert on("7S 7H", centre("7C 7D")) == {:ok, false}
      assert on("7C 7D", centre("7S 7H")) == {:error, :too_low}
      assert on("2H", centre("2S")) == {:ok, false}
      assert on("AH", centre("2S")) == {:error, :too_low}
      assert on("8S 8C 8D", centre("7S 7C 7H")) == {:ok, false}
    end

    test "straights must have the same length" do
      assert on("4S 5S 6S 7H 8H", centre("3S 4C 5C 6C 7C")) == {:ok, false}
      assert on("4S 5S 6S 7H", centre("3S 4C 5C 6C 7C")) == {:error, :does_not_match}
      assert on("4S 5S 6S 7H 8H", centre("3S 4C 5C 6C")) == {:error, :does_not_match}
      assert on("3C 4C 5S", centre("3H 4H 5C")) == {:error, :too_low}
    end

    test "different ordinary types do not match" do
      assert on("9S 9C", centre("3S")) == {:error, :does_not_match}
      assert on("3S 4S 5S", centre("8S 8C 8D")) == {:error, :does_not_match}
    end
  end

  describe "chop matrix (RULES §5.2)" do
    test "single 2: higher 2, or any three-pair / four of a kind / four-pair" do
      c = centre("2S")
      assert on("2H", c) == {:ok, false}
      assert on(@three_pair, c) == {:ok, true}
      assert on(@quad, c) == {:ok, true}
      assert on(@four_pair, c) == {:ok, true}
      assert on("AH AD", c) == {:error, :does_not_match}
    end

    test "pair of 2s: higher pair of 2s, or any four of a kind / four-pair; not a three-pair" do
      c = centre("2S 2C")
      assert on("2D 2H", c) == {:ok, false}
      assert on(@quad, c) == {:ok, true}
      assert on(@four_pair, c) == {:ok, true}
      assert on(@three_pair, c) == {:error, :cannot_chop}
    end

    test "triple of 2s cannot be chopped" do
      c = centre("2S 2C 2D")

      for bomb <- [@three_pair, @quad, @four_pair],
          do: assert(on(bomb, c) == {:error, :cannot_chop})
    end

    test "three-pair in chop context: higher three-pair, any four of a kind, any four-pair" do
      c = centre("9S 9C 10S 10C JS JC", true)
      assert on("10D 10H JD JH QS QC", c) == {:ok, true}
      assert on(@three_pair, c) == {:error, :too_low}
      assert on(@quad, c) == {:ok, true}
      assert on(@four_pair, c) == {:ok, true}
    end

    test "three-pair played normally: only a higher three-pair (Q3, R2)" do
      c = centre("9S 9C 10S 10C JS JC")
      assert on("10D 10H JD JH QS QC", c) == {:ok, false}
      assert on(@quad, c) == {:error, :cannot_chop}
      assert on(@four_pair, c) == {:error, :cannot_chop}
    end

    test "four of a kind in chop context: higher four of a kind or any four-pair" do
      c = centre("KS KC KD KH", true)
      assert on("AS AC AD AH", c) == {:ok, true}
      assert on(@quad, c) == {:error, :too_low}
      assert on(@four_pair, c) == {:ok, true}
      assert on(@three_pair, c) == {:error, :cannot_chop}
    end

    test "four of a kind played normally: only a higher four of a kind (R2)" do
      c = centre("KS KC KD KH")
      assert on("AS AC AD AH", c) == {:ok, false}
      assert on(@four_pair, c) == {:error, :cannot_chop}
    end

    test "four 2s is a four of a kind: nothing beats it when played normally" do
      c = centre("2S 2C 2D 2H")
      assert on(@four_pair, c) == {:error, :cannot_chop}
      assert on("AS AC AD AH", c) == {:error, :too_low}
    end

    test "four-pair: only a higher four-pair (both contexts)" do
      for context <- [false, true] do
        c = centre(@four_pair, context)
        assert on("5D 5H 6D 6H 7D 7H 8S 8C", c) == {:ok, context}
        assert on("3S 3C 4D 4H 5D 5H 6D 6H", c) == {:error, :too_low}
        assert on("AS AC AD AH", c) == {:error, :cannot_chop}
      end
    end

    test "no bombs on ordinary cards (Q4)" do
      for ordinary <- ["AH", "AS AH", "KS KC KD", "3S 4S 5S 6S 7S"],
          bomb <- [@three_pair, @quad, @four_pair] do
        assert on(bomb, centre(ordinary)) == {:error, :cannot_chop},
               "#{bomb} on #{ordinary}"
      end
    end

    test "ordinary cards never beat a bomb" do
      for bomb <- [@three_pair, @quad, @four_pair], context <- [false, true] do
        assert on("2H", centre(bomb, context)) == {:error, :does_not_match}
        assert on("2D 2H", centre(bomb, context)) == {:error, :does_not_match}
      end
    end
  end

  describe "chop context persistence (S3) — RULES §16 example 3" do
    test "2 → three-pair → higher three-pair → four of a kind → four-pair" do
      assert {:ok, c1, true} = Rules.play(cards("4S 4C 5S 5C 6S 6C"), centre("2S"))

      assert {:ok, c2, true} =
               Rules.play(cards("7S 7C 8S 8C 9S 9C"), %{combo: c1, chop_context: true})

      assert {:ok, c3, true} = Rules.play(cards("5S 5C 5D 5H"), %{combo: c2, chop_context: true})

      assert {:ok, _c4, true} =
               Rules.play(cards("JS JC QS QC KS KC AS AC"), %{combo: c3, chop_context: true})
    end
  end

  describe "leading and the opening card (T3, T7)" do
    test "any valid combination leads an empty table" do
      assert {:ok, %Combination{type: :straight}, false} = Rules.play(cards("3S 4S 5S"), nil)
      assert {:ok, %Combination{type: :four_pair}, false} = Rules.play(cards(@four_pair), nil)
    end

    test "invalid combinations are rejected with the classifier's reason" do
      assert Rules.play([], nil) == {:error, :empty}
      assert Rules.play(cards("3S 5S"), nil) == {:error, :invalid_combination}
      assert Rules.play(cards("3S 3S"), centre("2S")) == {:error, :duplicate_cards}
    end

    test "a card-led opening must contain the mandatory card" do
      three_spades = Card.parse!("3S")
      assert {:ok, _, false} = Rules.play(cards("3S"), nil, three_spades)
      assert {:ok, _, false} = Rules.play(cards("3S 4D 5H"), nil, three_spades)
      assert {:ok, _, false} = Rules.play(cards("3S 3C 3D 3H"), nil, three_spades)
      assert Rules.play(cards("4S"), nil, three_spades) == {:error, :must_include_card}
      assert Rules.play(cards("3C 3D"), nil, three_spades) == {:error, :must_include_card}

      three_diamonds = Card.parse!("3D")
      assert {:ok, _, false} = Rules.play(cards("3D 3H"), nil, three_diamonds)
      assert Rules.play(cards("3H"), nil, three_diamonds) == {:error, :must_include_card}
    end

    test "the opening card is ignored when responding" do
      assert {:ok, _, false} = Rules.play(cards("5S"), centre("4S"), Card.parse!("3S"))
    end
  end

  describe "passing (D3, T8)" do
    test "not allowed on a lead, allowed when responding" do
      assert Rules.pass(nil) == {:error, :cannot_pass_on_lead}
      assert Rules.pass(centre("4S")) == :ok
    end
  end

  describe "out-of-turn four-pair (T10, R3, S4)" do
    test "chops a single 2, a pair of 2s, or anything in chop context" do
      for c <- [centre("2S"), centre("2S 2C"), centre(@three_pair, true), centre(@quad, true)] do
        assert {:ok, %Combination{type: :four_pair}, true} =
                 Rules.play_out_of_turn(cards(@four_pair), c)
      end
    end

    test "a higher four-pair chops a lower one in chop context only (S4)" do
      higher = cards("5D 5H 6D 6H 7D 7H 8S 8C")
      assert {:ok, _, true} = Rules.play_out_of_turn(higher, centre(@four_pair, true))
      assert Rules.play_out_of_turn(higher, centre(@four_pair)) == {:error, :no_chop_target}

      lower = cards("3S 3C 4D 4H 5D 5H 6D 6H")
      assert Rules.play_out_of_turn(lower, centre(@four_pair, true)) == {:error, :too_low}
    end

    test "only a four-pair can be played out of turn" do
      for other <- [@quad, @three_pair, "2H"] do
        assert Rules.play_out_of_turn(cards(other), centre("2S")) == {:error, :not_four_pair}
      end
    end

    test "needs a chop target" do
      for c <- [
            nil,
            centre("AH"),
            centre("AS AH"),
            centre(@three_pair),
            centre(@quad),
            centre("2S 2C 2D")
          ] do
        assert Rules.play_out_of_turn(cards(@four_pair), c) == {:error, :no_chop_target}
      end
    end

    test "invalid cards are rejected first" do
      assert Rules.play_out_of_turn(cards("3S 5S"), centre("2S")) ==
               {:error, :invalid_combination}
    end

    test "chop_target?/1" do
      assert Rules.chop_target?(centre("2S"))
      assert Rules.chop_target?(centre("2D 2H"))
      assert Rules.chop_target?(centre(@quad, true))
      refute Rules.chop_target?(nil)
      refute Rules.chop_target?(centre("AH"))
      refute Rules.chop_target?(centre("2S 2C 2D"))
      refute Rules.chop_target?(centre(@quad))
    end
  end

  describe "RULES §16 examples about legality" do
    test "4: no bombs on ordinary cards" do
      assert on("5S 5C 5D 5H", centre("AH")) == {:error, :cannot_chop}
    end

    test "5: a normal three-pair only falls to a higher three-pair" do
      c = centre("3S 3C 4S 4C 5S 5C")
      assert on("9S 9C 9D 9H", c) == {:error, :cannot_chop}
      assert on(@four_pair, c) == {:error, :cannot_chop}
      assert on("4D 4H 5D 5H 6S 6C", c) == {:ok, false}
    end

    test "7: a pair of 2s falls to four 7s but not to a three-pair" do
      c = centre("2S 2H")
      assert on(@three_pair, c) == {:error, :cannot_chop}
      assert on("7S 7C 7D 7H", c) == {:ok, true}
    end
  end

  describe "auto_lead/2 (S1, interpretation X1)" do
    test "the lowest single, or the mandatory card as a single" do
      hand = cards("9C 3D 2H 3H")
      assert Rules.auto_lead(hand, nil) == cards("3D")
      assert Rules.auto_lead(hand, Card.parse!("3H")) == cards("3H")

      assert {:ok, _, false} =
               Rules.play(Rules.auto_lead(hand, Card.parse!("3D")), nil, Card.parse!("3D"))
    end

    test "raises if the mandatory card is not in the hand" do
      assert_raise ArgumentError, fn -> Rules.auto_lead(cards("9C"), Card.parse!("3S")) end
    end
  end

  describe "invariants over random combinations" do
    setup do
      combos =
        for seed <- 1..400, size <- [1, 2, 3, 4, 5, 6, 8], reduce: [] do
          acc ->
            hand = Deck.new() |> Deck.shuffle(seed) |> Enum.take(size)

            case Combination.classify(hand) do
              {:ok, c} -> [c | acc]
              _ -> acc
            end
        end

      # add every bomb and 2-combination shape explicitly
      extra =
        Enum.map(
          [
            @three_pair,
            @quad,
            @four_pair,
            "2S",
            "2H",
            "2S 2C",
            "2D 2H",
            "2S 2C 2D",
            "KS KC KD KH"
          ],
          &combo/1
        )

      %{combos: Enum.uniq(combos ++ extra)}
    end

    test "same shape: the higher top card wins; equal tops (e.g. two straights) beat neither way",
         %{combos: combos} do
      for a <- combos, b <- combos, a != b, a.type == b.type, a.length == b.length do
        ab = match?({:ok, _}, Rules.beats(a, %{combo: b, chop_context: false}))
        ba = match?({:ok, _}, Rules.beats(b, %{combo: a, chop_context: false}))

        if a.top == b.top do
          refute ab or ba
        else
          assert ab != ba
          assert ab == (Card.compare(a.top, b.top) == :gt)
        end
      end
    end

    test "equal top cards do not beat (straights sharing the top card)" do
      assert on("3S 4C 5H", centre("3D 4D 5H")) == {:error, :too_low}
    end

    test "cross-type beats are only bombs over 2s or over chop-context bombs", %{combos: combos} do
      for a <- combos,
          b <- combos,
          a.type != b.type or a.length != b.length,
          context <- [false, true] do
        case Rules.beats(a, %{combo: b, chop_context: context}) do
          {:ok, true} ->
            assert Combination.bomb?(a)
            assert b.top.rank == 15 or (context and Combination.bomb?(b))

          {:ok, false} ->
            flunk("cross-type beat without chop context: #{inspect({a.type, b.type})}")

          {:error, _} ->
            :ok
        end
      end
    end

    test "a beat never lowers the chop context", %{combos: combos} do
      for a <- combos, b <- combos do
        assert Rules.beats(a, %{combo: b, chop_context: true}) in [
                 {:ok, true},
                 {:error, :too_low},
                 {:error, :does_not_match},
                 {:error, :cannot_chop}
               ]
      end
    end
  end
end
