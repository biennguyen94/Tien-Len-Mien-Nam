defmodule TienLen.Combination do
  @moduledoc """
  Classifies a set of cards into a Tiến Lên combination (RULES T5, §4).

  | type              | cards | constraint                                                  |
  |-------------------|-------|-------------------------------------------------------------|
  | `:single`         | 1     | any card                                                    |
  | `:pair`           | 2     | same rank (2s allowed)                                      |
  | `:triple`         | 3     | same rank (2s allowed)                                      |
  | `:straight`       | 3–12  | distinct consecutive ranks, **no 2**, no wrap-around        |
  | `:four_of_a_kind` | 4     | same rank (four 2s allowed)                                 |
  | `:three_pair`     | 6     | three pairs of consecutive rank, **no 2s** (D5)             |
  | `:four_pair`      | 8     | four pairs of consecutive rank, **no 2s** (D5)              |

  Everything else is invalid, including five or more consecutive pairs (Q7).
  Whether one combination beats another is not decided here (see `TienLen.Rules`, Phase 4).
  """

  alias TienLen.Card

  @enforce_keys [:type, :cards, :top, :length]
  defstruct [:type, :cards, :top, :length]

  @type type ::
          :single | :pair | :triple | :straight | :four_of_a_kind | :three_pair | :four_pair

  @typedoc """
  - `cards`: the cards, sorted ascending
  - `top`: the highest card (decides same-type comparisons)
  - `length`: number of cards (straights must match in length)
  """
  @type t :: %__MODULE__{
          type: type(),
          cards: [Card.t(), ...],
          top: Card.t(),
          length: pos_integer()
        }

  @type error :: :empty | :duplicate_cards | :invalid_combination

  @two 15
  @bomb_types [:three_pair, :four_of_a_kind, :four_pair]

  @doc "All combination types."
  @spec types() :: [type()]
  def types, do: [:single, :pair, :triple, :straight, :four_of_a_kind, :three_pair, :four_pair]

  @doc """
  Classifies `cards` (in any order).

  Returns `{:error, :empty}` for no cards, `{:error, :duplicate_cards}` if the same card
  appears twice, and `{:error, :invalid_combination}` for any other invalid set.

      iex> {:ok, combo} = TienLen.Combination.classify(TienLen.Card.parse_many!("5H 3S 4C"))
      iex> {combo.type, combo.length, to_string(combo.top)}
      {:straight, 3, "5♥"}
      iex> TienLen.Combination.classify(TienLen.Card.parse_many!("KS KC AS AC 2S 2C"))
      {:error, :invalid_combination}
  """
  @spec classify([Card.t()]) :: {:ok, t()} | {:error, error()}
  def classify([]), do: {:error, :empty}

  def classify(cards) when is_list(cards) do
    sorted = Card.sort(cards)

    cond do
      length(Enum.uniq(sorted)) != length(sorted) ->
        {:error, :duplicate_cards}

      type = type_of(sorted) ->
        {:ok,
         %__MODULE__{type: type, cards: sorted, top: List.last(sorted), length: length(sorted)}}

      true ->
        {:error, :invalid_combination}
    end
  end

  @doc "Like `classify/1` but raises `ArgumentError`."
  @spec classify!([Card.t()]) :: t()
  def classify!(cards) do
    case classify(cards) do
      {:ok, combo} -> combo
      {:error, reason} -> raise ArgumentError, "not a combination (#{reason}): #{inspect(cards)}"
    end
  end

  @doc """
  True for the chop combinations ("hàng"): three-pair, four-of-a-kind, four-pair.
  Where they may be played is decided by `TienLen.Rules` (RULES §5.2).
  """
  @spec bomb?(t()) :: boolean()
  def bomb?(%__MODULE__{type: type}), do: type in @bomb_types

  # -- classification ---------------------------------------------------------

  # `sorted` is non-empty, ascending, without duplicate cards.
  defp type_of(sorted) do
    ranks = Enum.map(sorted, & &1.rank)
    counts = ranks |> Enum.frequencies() |> Map.values()
    distinct = ranks |> Enum.dedup()

    case {length(sorted), counts} do
      {1, _} -> :single
      {2, [2]} -> :pair
      {3, [3]} -> :triple
      {4, [4]} -> :four_of_a_kind
      {n, _} when n >= 3 -> sequence_type(n, distinct, counts)
      _ -> nil
    end
  end

  defp sequence_type(n, distinct, counts) do
    cond do
      not consecutive_without_two?(distinct) -> nil
      Enum.all?(counts, &(&1 == 1)) -> :straight
      Enum.all?(counts, &(&1 == 2)) and n == 6 -> :three_pair
      Enum.all?(counts, &(&1 == 2)) and n == 8 -> :four_pair
      true -> nil
    end
  end

  # Distinct ranks (ascending) form an unbroken run that does not contain a 2.
  defp consecutive_without_two?([first | _] = distinct) do
    last = List.last(distinct)
    last != @two and last - first + 1 == length(distinct)
  end
end
