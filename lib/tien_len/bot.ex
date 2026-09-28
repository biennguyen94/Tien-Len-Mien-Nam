defmodule TienLen.Bot do
  @moduledoc """
  Computer players (decisions B1–B6). Pure: `decide/3` looks at the game from the bot's seat
  (its own hand and public facts only, never other hands) and returns a command, which the
  room then runs through the normal rules like any player's command.

  Levels:
  - `:easy` ("dễ"): leads its lowest single, answers with the weakest legal play, never
    chops, never keeps cards back.
  - `:normal` ("thường"): leads with the biggest group holding its lowest card (straight,
    triple, pair), answers without breaking pairs / triples when it can, keeps 2s and bombs
    for when they matter (a 2 to chop, an opponent close to finishing, its own last cards),
    and chops a 2 out of turn with a four-pair.
  """

  alias TienLen.{Card, Combination, Game, Hint, Rules}

  @two 15

  @type level :: :easy | :normal
  @type command :: {:play, [Card.t()]} | :pass

  @doc "Levels with their labels."
  def levels, do: [easy: "dễ", normal: "thường"]

  def label(level), do: Keyword.fetch!(levels(), level)

  @doc "The bot's command on its own turn."
  @spec decide(Game.t(), term(), level()) :: command()
  def decide(%Game{} = game, seat, level) do
    hand = Map.get(game.hands, seat, [])

    case Hint.moves(game, seat) do
      [] -> :pass
      moves -> choose(level, game, seat, hand, moves)
    end
  end

  @doc "An out-of-turn four-pair chop for a `:normal` bot, or `nil`."
  @spec chop(Game.t(), term(), level()) :: [Card.t()] | nil
  def chop(_game, _seat, :easy), do: nil

  def chop(%Game{} = game, seat, :normal) do
    if game.centre && Rules.chop_target?(game.centre), do: List.first(Hint.chops(game, seat))
  end

  # -- choices ----------------------------------------------------------------------

  # finishing now always wins
  defp choose(level, game, seat, hand, moves) do
    case Enum.find(moves, &(length(&1) == length(hand))) do
      nil -> choose_by_level(level, game, seat, hand, moves)
      all -> {:play, all}
    end
  end

  defp choose_by_level(:easy, %Game{centre: nil}, _seat, hand, moves) do
    lowest = Card.lowest(hand)
    {:play, Enum.find(moves, hd(moves), &(&1 == [lowest]))}
  end

  defp choose_by_level(:easy, _game, _seat, _hand, moves) do
    case Enum.reject(moves, &bomb?/1) do
      [] -> :pass
      [weakest | _] -> {:play, weakest}
    end
  end

  defp choose_by_level(:normal, %Game{centre: nil}, _seat, hand, moves) do
    lowest = Card.lowest(hand)
    plain = Enum.reject(moves, &(bomb?(&1) or has_two?(&1)))
    pool = if plain == [], do: moves, else: plain
    with_lowest = Enum.filter(pool, &(lowest in &1))
    pool = if with_lowest == [], do: pool, else: with_lowest

    {:play, Enum.max_by(pool, &{length(&1), -Card.key(Combination.classify!(&1).top)})}
  end

  defp choose_by_level(:normal, game, seat, hand, moves) do
    counts = Enum.frequencies_by(hand, & &1.rank)
    {cheap, costly} = Enum.split_with(moves, &(not bomb?(&1) and not has_two?(&1)))
    pressed? = opponent_close?(game, seat) or length(hand) <= 4

    cond do
      cheap != [] ->
        {:play, Enum.min_by(cheap, &{breaks?(&1, counts), Hint.sort([&1])})}

      Rules.chop_target?(game.centre) and Enum.any?(costly, &bomb?/1) ->
        {:play, costly |> Enum.filter(&bomb?/1) |> hd()}

      pressed? and costly != [] ->
        {:play, hd(costly)}

      true ->
        :pass
    end
  end

  # -- helpers ----------------------------------------------------------------------

  defp bomb?(cards), do: cards |> Combination.classify!() |> Combination.bomb?()
  defp has_two?(cards), do: Enum.any?(cards, &(&1.rank == @two))

  # true if the play splits a pair / triple / quad of the hand
  defp breaks?(cards, counts) do
    cards
    |> Enum.frequencies_by(& &1.rank)
    |> Enum.any?(fn {rank, used} -> counts[rank] > used end)
  end

  defp opponent_close?(game, seat) do
    game
    |> Game.active_seats()
    |> Enum.any?(&(&1 != seat and length(Map.get(game.hands, &1, [])) <= 3))
  end
end
