defmodule TienLen.Rules do
  @moduledoc """
  Legality of plays and passes (RULES T3, T6, T7, T8, T10; §5–8).

  Pure functions. Card ownership, turn order and seats are checked by `TienLen.Game`; this
  module only answers "is this combination a legal play on this centre?".

  ## Centre

  The centre is `nil` when a round is being led (the table is empty), otherwise a map
  `%{combo: Combination.t(), chop_context: boolean()}` (extra keys such as `:owner` are
  ignored). `chop_context` is true once a single 2 or a pair of 2s has been chopped in the
  current round and stays true until the round ends (S3).

  ## Beat matrix (RULES §5.2)

  | centre                    | on your turn                                              |
  |---------------------------|-----------------------------------------------------------|
  | single 2                  | higher single 2; any three-pair / four of a kind / four-pair |
  | pair of 2s                | higher pair of 2s; any four of a kind / four-pair          |
  | three-pair, chop context  | higher three-pair; any four of a kind; any four-pair       |
  | four of a kind, chop ctx  | higher four of a kind; any four-pair                      |
  | anything else             | same type, same length, higher top card                   |

  Out of turn, only a four-pair may be played, and only on a single 2, a pair of 2s, or a
  centre in chop context (R3, S4).

  ## Error reasons

  From `TienLen.Combination`: `:empty`, `:duplicate_cards`, `:invalid_combination`.
  From this module:
  - `:does_not_match` — different type or length and not a legal chop
  - `:too_low` — same type and length but the top card is not higher
  - `:cannot_chop` — a chop combination played where chopping is not allowed (Q4, R2)
  - `:must_include_card` — the opening play lacks the mandatory card (T3)
  - `:cannot_pass_on_lead` — passing while leading (D3)
  - `:not_four_pair` — only a four-pair can be played out of turn
  - `:no_chop_target` — out-of-turn four-pair on a centre that is not a chop target
  """

  alias TienLen.{Card, Combination}

  @two 15

  @type centre ::
          nil | %{required(:combo) => Combination.t(), required(:chop_context) => boolean()}
  @type reason ::
          Combination.error()
          | :does_not_match
          | :too_low
          | :cannot_chop
          | :must_include_card
          | :cannot_pass_on_lead
          | :not_four_pair
          | :no_chop_target

  @doc """
  Validates a play made on the player's own turn.

  - With `centre == nil` this is a lead: any valid combination, which must contain
    `opening_card` when one is given (card-led opening, T3).
  - Otherwise the combination must beat the centre (`beats/2`).

  Returns `{:ok, combo, chop_context}` where `chop_context` is the context of the new centre.
  """
  @spec play([Card.t()], centre(), Card.t() | nil) ::
          {:ok, Combination.t(), boolean()} | {:error, reason()}
  def play(cards, centre, opening_card \\ nil)

  def play(cards, nil, opening_card) do
    with {:ok, combo} <- Combination.classify(cards),
         :ok <- check_opening(combo, opening_card) do
      {:ok, combo, false}
    end
  end

  def play(cards, centre, _opening_card) do
    with {:ok, combo} <- Combination.classify(cards),
         {:ok, chop_context} <- beats(combo, centre) do
      {:ok, combo, chop_context}
    end
  end

  @doc """
  Validates an out-of-turn four-pair (T10). Any player with cards may do this, including one
  who already passed; `TienLen.Game` checks that part.

  Returns `{:ok, combo, true}`: the result is always in chop context.
  """
  @spec play_out_of_turn([Card.t()], centre()) ::
          {:ok, Combination.t(), true} | {:error, reason()}
  def play_out_of_turn(cards, centre) do
    with {:ok, combo} <- Combination.classify(cards),
         :ok <- if(combo.type == :four_pair, do: :ok, else: {:error, :not_four_pair}),
         :ok <- if(chop_target?(centre), do: :ok, else: {:error, :no_chop_target}),
         {:ok, true} <- beats(combo, centre) do
      {:ok, combo, true}
    end
  end

  @doc "Validates a pass: only allowed when responding to a centre (D3, T7, T8)."
  @spec pass(centre()) :: :ok | {:error, :cannot_pass_on_lead}
  def pass(nil), do: {:error, :cannot_pass_on_lead}
  def pass(_centre), do: :ok

  @doc """
  Whether `combo` beats a non-empty `centre`. Returns `{:ok, chop_context}` for the new
  centre, or `{:error, :does_not_match | :too_low | :cannot_chop}`.
  """
  @spec beats(Combination.t(), map()) ::
          {:ok, boolean()} | {:error, :does_not_match | :too_low | :cannot_chop}
  def beats(%Combination{} = combo, %{combo: %Combination{} = current} = centre) do
    context = Map.get(centre, :chop_context, false)

    cond do
      same_shape?(combo, current) ->
        if Card.compare(combo.top, current.top) == :gt,
          do: {:ok, context},
          else: {:error, :too_low}

      chops?(combo.type, current, context) ->
        {:ok, true}

      Combination.bomb?(combo) ->
        {:error, :cannot_chop}

      true ->
        {:error, :does_not_match}
    end
  end

  @doc """
  True when the centre can be chopped by an out-of-turn four-pair: a single 2, a pair of 2s,
  or any centre in chop context.
  """
  @spec chop_target?(centre()) :: boolean()
  def chop_target?(nil), do: false
  def chop_target?(%{chop_context: true}), do: true
  def chop_target?(%{combo: combo}), do: twos?(combo, :single) or twos?(combo, :pair)

  @doc """
  The play the server makes for a player whose turn times out while leading (S1, X1): the
  lowest single card, or the mandatory opening card as a single.
  """
  @spec auto_lead([Card.t(), ...], Card.t() | nil) :: [Card.t()]
  def auto_lead([_ | _] = hand, nil), do: [Card.lowest(hand)]

  def auto_lead([_ | _] = hand, %Card{} = opening_card) do
    if opening_card in hand,
      do: [opening_card],
      else: raise(ArgumentError, "opening card #{Card.to_code(opening_card)} is not in hand")
  end

  # -- helpers ------------------------------------------------------------------

  defp check_opening(_combo, nil), do: :ok

  defp check_opening(combo, card),
    do: if(card in combo.cards, do: :ok, else: {:error, :must_include_card})

  defp same_shape?(a, b), do: a.type == b.type and a.length == b.length

  # Cross-type chops (D6, D7, Q3, R2, S3). Same-type beats are handled before this.
  defp chops?(new_type, current, context) do
    cond do
      twos?(current, :single) -> new_type in [:three_pair, :four_of_a_kind, :four_pair]
      twos?(current, :pair) -> new_type in [:four_of_a_kind, :four_pair]
      context and current.type == :three_pair -> new_type in [:four_of_a_kind, :four_pair]
      context and current.type == :four_of_a_kind -> new_type == :four_pair
      true -> false
    end
  end

  defp twos?(%Combination{type: type, top: %Card{rank: @two}}, type)
       when type in [:single, :pair],
       do: true

  defp twos?(_combo, _type), do: false
end
