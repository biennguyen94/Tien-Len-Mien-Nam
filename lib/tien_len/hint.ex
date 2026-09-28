defmodule TienLen.Hint do
  @moduledoc """
  Legal plays for a seat (decision H1, "gợi ý bài"; also used by `TienLen.Bot`). Pure.

  Candidates are built from the hand and then **validated by `TienLen.Game`'s own dry runs**
  (`check_play/3`, `check_chop_out_of_turn/3`), so a hint is never a move the rules refuse.

  To keep the list small, variants that cannot differ in strength are not repeated: in a
  straight or a run of pairs only the top card / top pair varies (the lower ranks use their
  lowest suits), because only the top card decides what beats what (RULES §5).
  """

  alias TienLen.{Card, Combination, Game}

  @two 15

  @doc """
  Legal plays for `seat` on its own turn, weakest first (non-bombs before bombs, no 2s before
  2s, then by top card, then shorter first). `[]` when it is not `seat`'s turn.
  """
  @spec moves(Game.t(), term()) :: [[Card.t()]]
  def moves(%Game{current: seat} = game, seat) do
    game.hands
    |> Map.get(seat, [])
    |> candidates()
    |> Enum.filter(&(Game.check_play(game, seat, &1) == :ok))
    |> sort()
  end

  def moves(_game, _seat), do: []

  @doc "Four-pairs `seat` may chop with right now, out of turn (T10), weakest first."
  @spec chops(Game.t(), term()) :: [[Card.t()]]
  def chops(%Game{phase: :respond} = game, seat) do
    game.hands
    |> Map.get(seat, [])
    |> runs_of_pairs(4)
    |> Enum.filter(&(Game.check_chop_out_of_turn(game, seat, &1) == :ok))
    |> sort()
  end

  def chops(_game, _seat), do: []

  @doc "Every combination worth considering from a hand (not validated against a centre)."
  @spec candidates([Card.t()]) :: [[Card.t()]]
  def candidates(hand) do
    hand = Card.sort(hand)
    groups = by_rank(hand)

    singles = Enum.map(hand, &[&1])
    sets = for {_rank, cards} <- groups, n <- 2..4, set <- combinations(cards, n), do: set

    (singles ++ sets ++ straights(groups) ++ runs_of_pairs(hand, 3) ++ runs_of_pairs(hand, 4))
    |> Enum.uniq()
  end

  @doc "Sort key: `{bomb?, has a 2?, top card, length}`."
  def sort(moves) do
    Enum.sort_by(moves, fn cards ->
      combo = Combination.classify!(cards)

      {Combination.bomb?(combo), Enum.any?(cards, &(&1.rank == @two)), Card.key(combo.top),
       length(cards)}
    end)
  end

  # -- builders ---------------------------------------------------------------------

  defp by_rank(hand),
    do: hand |> Enum.group_by(& &1.rank) |> Map.new(fn {r, cs} -> {r, Card.sort(cs)} end)

  # straights of 3+ ranks, never with a 2 (RULES §4)
  defp straights(groups) do
    ranks = groups |> Map.keys() |> Enum.filter(&(&1 < @two)) |> Enum.sort()

    for start <- ranks,
        len <- 3..12,
        top = start + len - 1,
        top < @two,
        Enum.all?(start..top, &Map.has_key?(groups, &1)),
        top_card <- groups[top] do
      Enum.map(start..(top - 1)//1, &hd(groups[&1])) ++ [top_card]
    end
  end

  # three / four consecutive pairs, never with 2s
  defp runs_of_pairs(hand, n) do
    groups = by_rank(Card.sort(hand))
    ranks = groups |> Map.keys() |> Enum.filter(&(&1 < @two)) |> Enum.sort()

    for start <- ranks,
        top = start + n - 1,
        top < @two,
        Enum.all?(start..top, &(length(Map.get(groups, &1, [])) >= 2)),
        top_pair <- combinations(groups[top], 2) do
      Enum.flat_map(start..(top - 1)//1, &Enum.take(groups[&1], 2)) ++ top_pair
    end
  end

  defp combinations(_list, 0), do: [[]]
  defp combinations([], _n), do: []

  defp combinations([x | rest], n),
    do: Enum.map(combinations(rest, n - 1), &[x | &1]) ++ combinations(rest, n)
end
