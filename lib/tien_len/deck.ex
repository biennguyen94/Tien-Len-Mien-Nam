defmodule TienLen.Deck do
  @moduledoc """
  The 52-card deck: seeded shuffle, deal and opening-leader lookup (RULES T1, T2).

  Randomness is fully determined by the seed passed in. This module never touches the process
  dictionary or the global `:rand` state, so the same seed always produces the same deal
  (needed for tests and replays). The seed must stay on the server (RULES T14, RISKS R1).
  """

  alias TienLen.Card

  @hand_size 13
  @players 2..4

  @typedoc "Any seed accepted by `:rand.seed_s(:exsss, seed)`."
  @type seed :: integer() | {integer(), integer(), integer()}

  @type deal :: %{hands: [[Card.t()]], undealt: [Card.t()]}

  @doc "Cards dealt to each player."
  @spec hand_size() :: 13
  def hand_size, do: @hand_size

  @doc "The 52 cards in ascending order."
  @spec new() :: [Card.t()]
  def new, do: Card.all()

  @doc "A fresh, unpredictable seed from a cryptographically strong source."
  @spec new_seed() :: {integer(), integer(), integer()}
  def new_seed do
    <<a::32, b::32, c::32>> = :crypto.strong_rand_bytes(12)
    {a, b, c}
  end

  @doc """
  Shuffles `cards` deterministically for `seed` (Fisher–Yates with the `:exsss` generator).
  """
  @spec shuffle([Card.t()], seed()) :: [Card.t()]
  def shuffle(cards, seed) do
    state = :rand.seed_s(:exsss, seed)
    array = cards |> List.to_tuple()
    n = tuple_size(array)

    {array, _state} =
      Enum.reduce((n - 1)..1//-1, {array, state}, fn i, {acc, st} ->
        {j, st} = :rand.uniform_s(i + 1, st)
        j = j - 1
        a = elem(acc, i)
        b = elem(acc, j)
        {acc |> put_elem(i, b) |> put_elem(j, a), st}
      end)

    Tuple.to_list(array)
  end

  @doc """
  Shuffles a new deck with `seed` and deals #{@hand_size} cards to each of `n_players` (2–4).

  Cards are dealt round-robin, one at a time, starting with player index 0. Each hand is
  returned sorted ascending. Cards left after the deal (26 with 2 players, 13 with 3, none
  with 4) are returned sorted as `:undealt`; they are out of the game (RULES T1).
  """
  @spec deal(2..4, seed()) :: deal()
  def deal(n_players, seed) when n_players in @players do
    shuffled = shuffle(new(), seed)
    {dealt, undealt} = Enum.split(shuffled, n_players * @hand_size)

    hands =
      dealt
      |> Enum.with_index()
      |> Enum.group_by(fn {_card, i} -> rem(i, n_players) end, fn {card, _i} -> card end)
      |> then(fn by_player -> for p <- 0..(n_players - 1), do: Card.sort(by_player[p]) end)

    %{hands: hands, undealt: Card.sort(undealt)}
  end

  @doc """
  Finds the player holding the lowest card among `hands`, searched in the order
  `3♠ → 3♣ → 3♦ → 3♥ → 4♠ → …` (RULES T2, card-led games).

  `hands` is a map `seat => cards`, or a list where the index is the seat. Pass only the
  players taking part in the game. Returns `{seat, card}`, or `nil` when no one holds a card.
  """
  @spec lowest_holder(%{optional(term()) => [Card.t()]} | [[Card.t()]]) ::
          {term(), Card.t()} | nil
  def lowest_holder(hands) when is_list(hands) do
    hands |> Enum.with_index() |> Map.new(fn {cards, i} -> {i, cards} end) |> lowest_holder()
  end

  def lowest_holder(hands) when is_map(hands) do
    hands
    |> Enum.flat_map(fn {seat, cards} -> Enum.map(cards, &{seat, &1}) end)
    |> Enum.min_by(fn {_seat, card} -> Card.key(card) end, fn -> nil end)
  end
end
