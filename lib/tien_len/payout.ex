defmodule TienLen.Payout do
  @moduledoc """
  Turns a game's outcome into coin debts (RULES T21–T24; C4–C8, E1–E4). Pure.

  Debts are expressed between **seats**: `%{from: seat, to: seat, amount: coins, reason: r}`.
  `TienLen.RoomServer` maps seats to accounts and `TienLen.Economy.settle/3` applies them with
  the balance caps of T25. With stake 0 every function returns `[]`.

  Reasons: `"place"`, `"instant_win"`, `"chop"`, `"thoi"`.
  """

  alias TienLen.Game

  @doc "Debts due at game over: instant-win payments, or place payments plus thối heo."
  @spec game_over(Game.t(), non_neg_integer()) :: [map()]
  def game_over(_game, 0), do: []

  def game_over(%Game{phase: :finished} = game, stake) do
    if Game.instant_win?(game),
      do: instant_win(game, stake),
      else: places(game.ranking, stake) ++ thoi(game, stake)
  end

  @doc """
  Place payments (T21): 4 players: Bét → Nhất S and Ba → Nhì ⌊S/2⌋; 3 or 2 players: Bét →
  Nhất S. `ranking` is a list of single-seat groups.
  """
  def places(ranking, stake) do
    seats = Enum.map(ranking, fn [seat] -> seat end)

    case seats do
      [first, second, third, last] ->
        [debt(last, first, stake, "place"), debt(third, second, div(stake, 2), "place")]

      [first | _] = seats when length(seats) in [2, 3] ->
        [debt(List.last(seats), first, stake, "place")]
    end
    |> Enum.reject(&(&1.amount == 0))
  end

  @doc "Instant win (T22, E2): every non-winner pays 2×S to every instant winner."
  def instant_win(%Game{instant_winners: winners, seats: seats}, stake) do
    winner_seats = Enum.map(winners, &elem(&1, 0))

    for loser <- seats, loser not in winner_seats, winner <- winner_seats do
      debt(loser, winner, 2 * stake, "instant_win")
    end
  end

  @doc """
  Thối heo (T24, E4): the last player still holding cards pays for each 2 in hand (black 1×S,
  red 2×S) to the player ranked just above. Removed players never pay thối.
  """
  def thoi(%Game{} = game, stake) do
    ranked = Enum.map(game.ranking, fn [seat] -> seat end)

    case Enum.find_index(ranked, &(&1 not in game.finished and &1 not in game.removed)) do
      nil ->
        []

      0 ->
        []

      i ->
        loser = Enum.at(ranked, i)
        units = Game.twos_units(game.hands[loser])
        if units > 0, do: [debt(loser, Enum.at(ranked, i - 1), units * stake, "thoi")], else: []
    end
  end

  @doc "Chop chain (T23, E3): the last chopped pays the last chopper."
  def chop_chain(_chain, 0), do: []
  def chop_chain(%{payer: same, payee: same}, _stake), do: []

  def chop_chain(%{payer: payer, payee: payee, units: units}, stake),
    do: [debt(payer, payee, units * stake, "chop")]

  defp debt(from, to, amount, reason), do: %{from: from, to: to, amount: amount, reason: reason}
end
