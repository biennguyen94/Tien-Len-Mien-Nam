defmodule TienLen.InstantWin do
  @moduledoc """
  Instant-win (tới trắng) detection on a dealt 13-card hand (RULES T18, §10; I1–I8).

  | hand          | condition                                                         | applies        |
  |---------------|-------------------------------------------------------------------|----------------|
  | `:four_twos`  | 2♠ 2♣ 2♦ 2♥                                                       | always         |
  | `:dragon`     | one card of every rank 3 → A (12 ranks) + any 13th card           | always         |
  | `:six_pairs`  | splits into 6 disjoint pairs + 1 card; 2s count; a four of a kind counts as two pairs | always |
  | `:four_threes`| 3♠ 3♣ 3♦ 3♥                                                       | card-led games only |

  Four triples is deliberately **not** an instant win.

  `mode` is `:card_led` (the opening leader is chosen by the lowest card: first game of a
  session, previous winner gone, or after an instant-win game) or `:winner_led`. It is known
  before the deal (RULES §6.1).
  """

  alias TienLen.Card

  @type hand_type :: :four_twos | :dragon | :six_pairs | :four_threes
  @type mode :: :card_led | :winner_led

  # Priority when a hand qualifies in several ways (only affects the label shown).
  @priority [:four_twos, :dragon, :six_pairs, :four_threes]

  @doc """
  Returns the instant-win type of a 13-card hand, or `nil`. If the hand qualifies in several
  ways, the first of `#{inspect(@priority)}` is returned.
  """
  @spec detect([Card.t()], mode()) :: hand_type() | nil
  def detect(hand, mode) when length(hand) == 13 and mode in [:card_led, :winner_led] do
    hand |> matches(mode) |> List.first()
  end

  @doc "All instant-win types a 13-card hand qualifies for, in priority order."
  @spec matches([Card.t()], mode()) :: [hand_type()]
  def matches(hand, mode) when length(hand) == 13 and mode in [:card_led, :winner_led] do
    counts = hand |> Enum.map(& &1.rank) |> Enum.frequencies()

    Enum.filter(@priority, fn
      :four_twos -> Map.get(counts, 15) == 4
      :dragon -> Enum.all?(3..14, &Map.has_key?(counts, &1))
      :six_pairs -> counts |> Map.values() |> Enum.map(&div(&1, 2)) |> Enum.sum() >= 6
      :four_threes -> mode == :card_led and Map.get(counts, 3) == 4
    end)
  end

  @doc """
  Checks every seat. `hands` is a list of `{seat, hand}` in seat order, or a list of hands
  (index = seat). Returns the instant winners as `[{seat, hand_type}]` in seat order, which is
  also their tie-break order (I4). An empty list means the game is played normally.
  """
  @spec winners([{term(), [Card.t()]}] | [[Card.t()]], mode()) :: [{term(), hand_type()}]
  def winners(hands, mode) do
    hands
    |> normalise()
    |> Enum.flat_map(fn {seat, hand} ->
      case detect(hand, mode) do
        nil -> []
        type -> [{seat, type}]
      end
    end)
  end

  defp normalise([{_seat, _hand} | _] = pairs), do: pairs
  defp normalise(hands), do: Enum.with_index(hands, fn hand, i -> {i, hand} end)
end
