defmodule TienLen.Card do
  @moduledoc """
  A playing card and the Tiến Lên card order (RULES T4).

  Ranks are integers `3..15`, low to high: `3 4 5 6 7 8 9 10 J(11) Q(12) K(13) A(14) 2(15)`.
  Suits, low to high: `:spades < :clubs < :diamonds < :hearts`.
  Rank decides first, suit breaks ties: `3♠` is the lowest card and `2♥` the highest.

  Cards have a compact text code used in tests and on the wire: rank (`3`..`10`, `J`, `Q`,
  `K`, `A`, `2`; `T` is accepted for ten) followed by suit (`S`, `C`, `D`, `H`), e.g. `"3S"`,
  `"10H"`, `"2H"`.
  """

  @enforce_keys [:rank, :suit]
  defstruct [:rank, :suit]

  @type rank :: 3..15
  @type suit :: :spades | :clubs | :diamonds | :hearts
  @type t :: %__MODULE__{rank: rank(), suit: suit()}

  @ranks Enum.to_list(3..15)
  @suits [:spades, :clubs, :diamonds, :hearts]

  @rank_labels %{11 => "J", 12 => "Q", 13 => "K", 14 => "A", 15 => "2"}
  @suit_letters %{spades: "S", clubs: "C", diamonds: "D", hearts: "H"}
  @suit_symbols %{spades: "♠", clubs: "♣", diamonds: "♦", hearts: "♥"}

  @doc "All ranks, low to high."
  @spec ranks() :: [rank()]
  def ranks, do: @ranks

  @doc "All suits, low to high."
  @spec suits() :: [suit()]
  def suits, do: @suits

  @doc "Builds a card. Raises `ArgumentError` for an invalid rank or suit."
  @spec new(rank(), suit()) :: t()
  def new(rank, suit) when rank in @ranks and suit in @suits,
    do: %__MODULE__{rank: rank, suit: suit}

  def new(rank, suit),
    do: raise(ArgumentError, "invalid card: rank #{inspect(rank)}, suit #{inspect(suit)}")

  @doc "The 52 cards in ascending order (`3♠` first, `2♥` last)."
  @spec all() :: [t()]
  def all, do: for(rank <- @ranks, suit <- @suits, do: %__MODULE__{rank: rank, suit: suit})

  @doc """
  Position of the card in the total order: `0` for `3♠` up to `51` for `2♥`.
  """
  @spec key(t()) :: 0..51
  def key(%__MODULE__{rank: rank, suit: suit}), do: (rank - 3) * 4 + suit_index(suit)

  @doc "Index of the suit, `0` (spades) to `3` (hearts)."
  @spec suit_index(suit()) :: 0..3
  def suit_index(:spades), do: 0
  def suit_index(:clubs), do: 1
  def suit_index(:diamonds), do: 2
  def suit_index(:hearts), do: 3

  @doc """
  Compares two cards by rank, then suit. Returns `:lt`, `:eq` or `:gt`, so the module can be
  passed to `Enum.sort/2`, `Enum.max/2`, etc.
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt
  def compare(a, b) do
    ka = key(a)
    kb = key(b)

    cond do
      ka < kb -> :lt
      ka > kb -> :gt
      true -> :eq
    end
  end

  @doc "Sorts cards in ascending order."
  @spec sort([t()]) :: [t()]
  def sort(cards), do: Enum.sort_by(cards, &key/1)

  @doc "The highest card of a non-empty list."
  @spec highest([t(), ...]) :: t()
  def highest([_ | _] = cards), do: Enum.max_by(cards, &key/1)

  @doc "The lowest card of a non-empty list."
  @spec lowest([t(), ...]) :: t()
  def lowest([_ | _] = cards), do: Enum.min_by(cards, &key/1)

  @doc "Rank label: `\"3\"`..`\"10\"`, `\"J\"`, `\"Q\"`, `\"K\"`, `\"A\"`, `\"2\"`."
  @spec rank_label(rank()) :: String.t()
  def rank_label(rank) when rank in @ranks,
    do: Map.get(@rank_labels, rank, Integer.to_string(rank))

  @doc "Suit symbol: `♠ ♣ ♦ ♥`."
  @spec suit_symbol(suit()) :: String.t()
  def suit_symbol(suit) when suit in @suits, do: Map.fetch!(@suit_symbols, suit)

  @doc "Text code, e.g. `\"3S\"`, `\"10H\"`, `\"2H\"`."
  @spec to_code(t()) :: String.t()
  def to_code(%__MODULE__{rank: rank, suit: suit}),
    do: rank_label(rank) <> Map.fetch!(@suit_letters, suit)

  @doc "Human-readable label, e.g. `\"3♠\"`, `\"10♥\"`."
  @spec display(t()) :: String.t()
  def display(%__MODULE__{rank: rank, suit: suit}), do: rank_label(rank) <> suit_symbol(suit)

  @doc """
  Parses a text code (case-insensitive; `T` or `10` for ten).

      iex> TienLen.Card.parse("10h")
      {:ok, %TienLen.Card{rank: 10, suit: :hearts}}
      iex> TienLen.Card.parse("1S")
      :error
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(code) when is_binary(code) do
    code = String.upcase(code)

    with {rank_part, suit_part} <- String.split_at(code, -1),
         {:ok, suit} <- parse_suit(suit_part),
         {:ok, rank} <- parse_rank(rank_part) do
      {:ok, %__MODULE__{rank: rank, suit: suit}}
    else
      _ -> :error
    end
  end

  def parse(_), do: :error

  @doc "Like `parse/1` but raises `ArgumentError`."
  @spec parse!(String.t()) :: t()
  def parse!(code) do
    case parse(code) do
      {:ok, card} -> card
      :error -> raise ArgumentError, "invalid card code: #{inspect(code)}"
    end
  end

  @doc "Parses a space-separated list of codes, e.g. `\"3S 3C 4H\"`. Raises on invalid input."
  @spec parse_many!(String.t()) :: [t()]
  def parse_many!(codes), do: codes |> String.split() |> Enum.map(&parse!/1)

  defp parse_suit("S"), do: {:ok, :spades}
  defp parse_suit("C"), do: {:ok, :clubs}
  defp parse_suit("D"), do: {:ok, :diamonds}
  defp parse_suit("H"), do: {:ok, :hearts}
  defp parse_suit(_), do: :error

  defp parse_rank("J"), do: {:ok, 11}
  defp parse_rank("Q"), do: {:ok, 12}
  defp parse_rank("K"), do: {:ok, 13}
  defp parse_rank("A"), do: {:ok, 14}
  defp parse_rank("2"), do: {:ok, 15}
  defp parse_rank("T"), do: {:ok, 10}

  defp parse_rank(digits) do
    case Integer.parse(digits) do
      {n, ""} when n in 3..10 -> {:ok, n}
      _ -> :error
    end
  end

  defimpl String.Chars do
    def to_string(card), do: TienLen.Card.display(card)
  end
end
