defmodule TienLen.Game do
  @moduledoc """
  One game of Tiến Lên, as a pure state machine (RULES T2, T3, T7–T12, T15 effects, T16
  actions, T18 flow).

  No processes, timers or randomness: the room process (Phase 6) owns timers and calls
  `timeout/2` and `remove/2`. Every command names the acting seat explicitly and is validated
  for that seat (T17). Commands return `{:ok, game, events}` or `{:error, reason}` and never
  raise on bad input.

  ## Seats

  `seats` is the list of players taking part, **in turn order** (counter-clockwise). Seats
  can be any terms (integers, ids).

  ## Phases

  - `:lead` — `current` must play any valid combination (no pass, D3). On the first play
    of a card-led game it must contain `opening_card` (T3).
  - `:respond` — `current` beats the centre or passes. Any active player may chop out of
    turn with a four-pair (T10).
  - `:finished` — `ranking` is set.

  ## Events (public information only)

  `{:played, seat, combo}`, `{:chopped, seat, combo}` (out of turn), `{:passed, seat}`,
  `{:timed_out, seat}`, `{:finished, seat, position}`, `{:removed, seat}`,
  `{:round_ended, leader}`, `{:lead_moved, leader}`, `{:game_over, ranking}`,
  `{:chop_chain, %{payer, payee, units, chops}}` (when a round's chop chain ends, E3/T23;
  `units` = value of the chopped 2s in stakes × number of chops).

  ## Error reasons

  `:game_over`, `:not_in_game`, `:not_active` (finished or removed), `:not_your_turn`,
  `:not_your_cards`, plus every reason from `TienLen.Rules`.
  """

  alias TienLen.{Card, Combination, Deck, InstantWin, Rules}

  defstruct seats: [],
            hands: %{},
            undealt: [],
            discarded: [],
            mode: :card_led,
            opening_card: nil,
            phase: :lead,
            current: nil,
            centre: nil,
            passed: MapSet.new(),
            finished: [],
            removed: [],
            instant_winners: [],
            ranking: nil,
            # chop chain of the current round (E3): nil or %{units, chops, payer, payee}
            chain: nil

  @type seat :: term()
  @type centre :: nil | %{combo: Combination.t(), owner: seat(), chop_context: boolean()}
  @type ranking :: [[seat()]]
  @type event ::
          {:played | :chopped, seat(), Combination.t()}
          | {:passed | :timed_out | :removed, seat()}
          | {:finished, seat(), pos_integer()}
          | {:round_ended | :lead_moved, seat()}
          | {:game_over, ranking()}

  @type t :: %__MODULE__{
          seats: [seat()],
          hands: %{seat() => [Card.t()]},
          undealt: [Card.t()],
          discarded: [Card.t()],
          mode: :card_led | :winner_led,
          opening_card: Card.t() | nil,
          phase: :lead | :respond | :finished,
          current: seat() | nil,
          centre: centre(),
          passed: MapSet.t(seat()),
          finished: [seat()],
          removed: [seat()],
          instant_winners: [{seat(), InstantWin.hand_type()}],
          ranking: ranking() | nil
        }

  @type result :: {:ok, t(), [event()]} | {:error, atom()}

  # -- creation -----------------------------------------------------------------

  @doc """
  Shuffles with `seed`, deals 13 cards to each seat and starts the game.

  Options:
  - `leader: seat` — winner-led game (the previous winner leads freely, R1). Without it the
    game is card-led: the holder of the lowest dealt card leads and must include it (R4, S7).

  The seed is not stored in the game.
  """
  @spec new([seat()], Deck.seed(), keyword()) :: t()
  def new(seats, seed, opts \\ []) do
    validate_seats!(seats)
    %{hands: hands, undealt: undealt} = Deck.deal(length(seats), seed)
    start(seats, seats |> Enum.zip(hands) |> Map.new(), undealt, opts)
  end

  @doc """
  Starts a game from given hands (`%{seat => cards}`), e.g. for tests and replays.
  Same options as `new/3`.

  Instant wins (T18) are checked on 13-card hands. Dealt hands always have 13 cards; shorter
  hands (used in tests) never count as instant wins.
  """
  @spec start([seat()], %{seat() => [Card.t()]}, [Card.t()], keyword()) :: t()
  def start(seats, hands, undealt \\ [], opts \\ []) do
    validate_seats!(seats)
    leader = Keyword.get(opts, :leader)

    if leader != nil and leader not in seats,
      do: raise(ArgumentError, "leader #{inspect(leader)} is not a seat")

    mode = if leader == nil, do: :card_led, else: :winner_led
    hands = Map.new(seats, fn seat -> {seat, Card.sort(Map.fetch!(hands, seat))} end)
    game = %__MODULE__{seats: seats, hands: hands, undealt: Card.sort(undealt), mode: mode}

    instant =
      seats
      |> Enum.map(&{&1, hands[&1]})
      |> Enum.filter(fn {_seat, hand} -> length(hand) == 13 end)
      |> InstantWin.winners(mode)

    cond do
      instant != [] ->
        finish_instant(game, instant)

      leader != nil ->
        %{game | current: leader}

      true ->
        case Deck.lowest_holder(hands) do
          {seat, card} -> %{game | current: seat, opening_card: card}
          nil -> raise ArgumentError, "no cards dealt"
        end
    end
  end

  defp validate_seats!(seats) do
    unless is_list(seats) and length(seats) in 2..4 and length(Enum.uniq(seats)) == length(seats) do
      raise ArgumentError, "expected 2 to 4 distinct seats, got: #{inspect(seats)}"
    end
  end

  defp finish_instant(game, instant) do
    winners = Enum.map(instant, &elem(&1, 0))
    others = Enum.reject(game.seats, &(&1 in winners))
    ranking = if others == [], do: [winners], else: [winners, others]

    %{game | phase: :finished, current: nil, instant_winners: instant, ranking: ranking}
  end

  # -- commands -----------------------------------------------------------------

  @doc "Plays `cards` on `seat`'s own turn (a lead or a beat)."
  @spec play(t(), seat(), [Card.t()]) :: result()
  def play(game, seat, cards) do
    with :ok <- ensure_playing(game),
         :ok <- ensure_active(game, seat),
         :ok <- ensure_turn(game, seat),
         :ok <- ensure_owns(game, seat, cards),
         {:ok, combo, context} <- Rules.play(cards, game.centre, lead_card(game)) do
      apply_play(game, seat, combo, context, [{:played, seat, combo}])
    end
  end

  @doc "Passes on `seat`'s own turn. Not allowed while leading (D3)."
  @spec pass(t(), seat()) :: result()
  def pass(game, seat) do
    with :ok <- ensure_playing(game),
         :ok <- ensure_active(game, seat),
         :ok <- ensure_turn(game, seat),
         :ok <- Rules.pass(game.centre) do
      game = %{game | passed: MapSet.put(game.passed, seat)}
      advance_after(game, seat, [{:passed, seat}])
    end
  end

  @doc """
  Out-of-turn four-pair chop (T10, R3, S2, S4). Any active player may do it, including one who
  passed this round. Pass marks are reset and play continues from the seat after the chopper.
  """
  @spec chop_out_of_turn(t(), seat(), [Card.t()]) :: result()
  def chop_out_of_turn(game, seat, cards) do
    with :ok <- ensure_playing(game),
         :ok <- ensure_active(game, seat),
         :ok <- ensure_owns(game, seat, cards),
         {:ok, combo, true} <- Rules.play_out_of_turn(cards, game.centre) do
      game = %{game | passed: MapSet.new()}
      apply_play(game, seat, combo, true, [{:chopped, seat, combo}])
    end
  end

  @doc """
  The turn timer of `seat` expired (T16). Responding: pass. Leading: play the lowest single, or
  the mandatory opening card as a single (interpretation X1).
  """
  @spec timeout(t(), seat()) :: result()
  def timeout(game, seat) do
    with :ok <- ensure_playing(game),
         :ok <- ensure_active(game, seat),
         :ok <- ensure_turn(game, seat) do
      result =
        case game.phase do
          :respond -> pass(game, seat)
          :lead -> play(game, seat, Rules.auto_lead(game.hands[seat], lead_card(game)))
        end

      with {:ok, game, events} <- result, do: {:ok, game, [{:timed_out, seat} | events]}
    end
  end

  @doc """
  Removes `seat` from the game after the disconnect timeout (T15, R5, S5). Their cards are
  discarded; they rank after every normal finisher. If they were due to act, play moves on:
  a lead passes to the next active seat (without an opening-card requirement), a response
  counts as a pass.
  """
  @spec remove(t(), seat()) :: result()
  def remove(game, seat) do
    with :ok <- ensure_playing(game),
         :ok <- ensure_active(game, seat) do
      was_current = game.current == seat

      game = %{
        game
        | hands: Map.put(game.hands, seat, []),
          discarded: Card.sort(game.discarded ++ game.hands[seat]),
          removed: game.removed ++ [seat],
          passed: MapSet.delete(game.passed, seat)
      }

      events = [{:removed, seat}]

      cond do
        game_over?(game) ->
          finish(game, events)

        not was_current ->
          {:ok, game, events}

        game.phase == :lead ->
          leader = next_in(game.seats, seat, active_seats(game))
          {:ok, %{game | current: leader, opening_card: nil}, events ++ [{:lead_moved, leader}]}

        true ->
          advance_after(game, seat, events)
      end
    end
  end

  @doc "Dry run of `play/3`: `:ok` or `{:error, reason}`, without changing the game."
  @spec check_play(t(), seat(), [Card.t()]) :: :ok | {:error, atom()}
  def check_play(game, seat, cards), do: dry_run(play(game, seat, cards))

  @doc "Dry run of `chop_out_of_turn/3`."
  @spec check_chop_out_of_turn(t(), seat(), [Card.t()]) :: :ok | {:error, atom()}
  def check_chop_out_of_turn(game, seat, cards), do: dry_run(chop_out_of_turn(game, seat, cards))

  @doc "Dry run of `pass/2`."
  @spec check_pass(t(), seat()) :: :ok | {:error, atom()}
  def check_pass(game, seat), do: dry_run(pass(game, seat))

  defp dry_run({:ok, _game, _events}), do: :ok
  defp dry_run({:error, _} = error), do: error

  # -- queries ------------------------------------------------------------------

  @doc "Seats still playing: not finished and not removed, in seat order."
  @spec active_seats(t()) :: [seat()]
  def active_seats(game),
    do: Enum.filter(game.seats, &(&1 not in game.finished and &1 not in game.removed))

  @doc "True once the game is over."
  @spec finished?(t()) :: boolean()
  def finished?(game), do: game.phase == :finished

  @doc "True if the game ended by instant win (the next game is then card-led, I5)."
  @spec instant_win?(t()) :: boolean()
  def instant_win?(game), do: game.instant_winners != []

  @doc "1st place of a finished game (the first instant winner in seat order), else `nil`."
  @spec winner(t()) :: seat() | nil
  def winner(%__MODULE__{ranking: [[first | _] | _]}), do: first
  def winner(_game), do: nil

  @doc """
  Everything, for the admin watch view only (AD7, F6): all hands, undealt and discarded
  cards, plus the public state. Never sent to players.
  """
  @spec admin_view(t()) :: map()
  def admin_view(game) do
    game
    |> view(nil)
    |> Map.merge(%{
      hands: game.hands,
      undealt: game.undealt,
      discarded: game.discarded,
      chain: game.chain
    })
  end

  @doc """
  What `seat` may see (RULES T14). Other players' hands, undealt and discarded cards are never
  included, except the whole hands of instant winners (I8).
  """
  @spec view(t(), seat()) :: map()
  def view(game, seat) do
    member? = seat in game.seats

    %{
      seats: game.seats,
      me: if(member?, do: seat),
      hand: if(member?, do: game.hands[seat], else: []),
      card_counts: Map.new(game.seats, &{&1, length(game.hands[&1])}),
      mode: game.mode,
      phase: game.phase,
      current: game.current,
      centre:
        game.centre &&
          %{
            cards: game.centre.combo.cards,
            type: game.centre.combo.type,
            owner: game.centre.owner,
            chop_context: game.centre.chop_context
          },
      passed: Enum.filter(game.seats, &MapSet.member?(game.passed, &1)),
      finished: game.finished,
      removed: game.removed,
      ranking: game.ranking,
      must_include: if(member? and game.current == seat, do: lead_card(game)),
      instant_winners:
        Enum.map(game.instant_winners, fn {s, type} ->
          %{seat: s, type: type, hand: game.hands[s]}
        end)
    }
  end

  # -- internals ----------------------------------------------------------------

  defp ensure_playing(%{phase: :finished}), do: {:error, :game_over}
  defp ensure_playing(_game), do: :ok

  defp ensure_active(game, seat) do
    cond do
      seat not in game.seats -> {:error, :not_in_game}
      seat in game.finished or seat in game.removed -> {:error, :not_active}
      true -> :ok
    end
  end

  defp ensure_turn(%{current: seat}, seat), do: :ok
  defp ensure_turn(_game, _seat), do: {:error, :not_your_turn}

  defp ensure_owns(game, seat, cards) when is_list(cards) do
    hand = game.hands[seat]
    if Enum.all?(cards, &(&1 in hand)), do: :ok, else: {:error, :not_your_cards}
  end

  defp ensure_owns(_game, _seat, _cards), do: {:error, :not_your_cards}

  # The mandatory opening card applies only to the very first play of a card-led game.
  defp lead_card(%{centre: nil, opening_card: card}), do: card
  defp lead_card(_game), do: nil

  defp apply_play(game, seat, combo, context, events) do
    hand = game.hands[seat] -- combo.cards

    game = %{
      game
      | hands: Map.put(game.hands, seat, hand),
        chain: update_chain(game.centre, game.chain, seat, context),
        centre: %{combo: combo, owner: seat, chop_context: context},
        opening_card: nil
    }

    {game, events} =
      if hand == [] do
        finished = game.finished ++ [seat]
        {%{game | finished: finished}, events ++ [{:finished, seat, length(finished)}]}
      else
        {game, events}
      end

    if game_over?(game), do: finish(game, events), else: advance_after(game, seat, events)
  end

  # After `from` acted: the next responder (active, not passed, not the round owner) after
  # `from` in seat order; if there is none, the round ends (T9).
  defp advance_after(game, from, events) do
    case responders(game) do
      [] ->
        end_round(game, events)

      candidates ->
        {:ok, %{game | phase: :respond, current: next_in(game.seats, from, candidates)}, events}
    end
  end

  defp responders(game) do
    owner = game.centre && game.centre.owner

    game
    |> active_seats()
    |> Enum.reject(&(&1 == owner or MapSet.member?(game.passed, &1)))
  end

  defp end_round(game, events) do
    owner = game.centre.owner
    active = active_seats(game)
    leader = if owner in active, do: owner, else: next_in(game.seats, owner, active)

    {game, events} = close_chain(game, events)
    game = %{game | phase: :lead, current: leader, centre: nil, passed: MapSet.new()}
    {:ok, game, events ++ [{:round_ended, leader}]}
  end

  # First seat after `from` (cyclically, `from` itself last) that is in `candidates`.
  defp next_in(seats, from, candidates) do
    {before, [^from | rest]} = Enum.split_while(seats, &(&1 != from))
    Enum.find(rest ++ before ++ [from], &(&1 in candidates))
  end

  defp game_over?(game), do: length(active_seats(game)) <= 1

  @doc """
  Value of the 2s among `cards`, in stakes (C6): 2♠/2♣ = 1, 2♦/2♥ = 2. Other cards are 0.
  """
  @spec twos_units([Card.t()]) :: non_neg_integer()
  def twos_units(cards) do
    Enum.sum_by(cards, fn
      %Card{rank: 15, suit: suit} when suit in [:spades, :clubs] -> 1
      %Card{rank: 15} -> 2
      _ -> 0
    end)
  end

  # E3: a play that turns a normal centre into chop context chops the 2s and starts a chain;
  # every play on a chop-context centre is one more chop. The payer is always the owner of
  # the combination chopped last, the payee the last chopper.
  defp update_chain(%{chop_context: false, combo: chopped, owner: owner}, _chain, seat, true),
    do: %{units: twos_units(chopped.cards), chops: 1, payer: owner, payee: seat}

  defp update_chain(%{chop_context: true, owner: owner}, %{} = chain, seat, _context),
    do: %{chain | chops: chain.chops + 1, payer: owner, payee: seat}

  defp update_chain(_centre, chain, _seat, _context), do: chain

  defp close_chain(%{chain: nil} = game, events), do: {game, events}

  defp close_chain(%{chain: chain} = game, events) do
    event = {:chop_chain, %{chain | units: chain.units * chain.chops}}
    {%{game | chain: nil}, events ++ [event]}
  end

  defp finish(game, events) do
    {game, events} = close_chain(game, events)
    last = active_seats(game)

    ranking =
      Enum.map(game.finished, &[&1]) ++ Enum.map(last, &[&1]) ++ Enum.map(game.removed, &[&1])

    game = %{game | phase: :finished, current: nil, ranking: ranking}
    {:ok, game, events ++ [{:game_over, ranking}]}
  end
end
