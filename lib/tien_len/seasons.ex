defmodule TienLen.Seasons do
  @moduledoc """
  Weekly seasons (decisions S1–S4). A season is a week, Monday 00:00 to Sunday 24:00 Vietnam
  time. Its ranking is the leaderboard (1st places, same order as A1/Y5) restricted to the
  games finished that week.

  When a week is over, the top 3 players **with at least one win** get the rewards
  `season_reward_1..3` (1,000 / 500 / 300). `payout/1` is idempotent (keys
  `season:<monday>:<rank>`), and `TienLen.Seasons.Scheduler` calls `payout_due/0` at start and
  every hour, so a restart never skips or doubles a payout.
  """

  import Ecto.Query

  alias TienLen.{Economy, Repo, Settings, Stats}
  alias TienLen.Economy.CoinTransaction

  @doc "Monday of the week holding `date`."
  def week_start(date \\ Economy.vn_today()), do: Date.beginning_of_week(date, :monday)

  @doc "UTC bounds of the week starting on `monday`."
  def period(monday) do
    {from, _} = Economy.vn_day_bounds(monday)
    {from, DateTime.add(from, 7 * 86_400, :second)}
  end

  @doc "\"28/09 – 04/10\""
  def label(monday),
    do:
      "#{Calendar.strftime(monday, "%d/%m")} – #{Calendar.strftime(Date.add(monday, 6), "%d/%m")}"

  @doc "Rewards by rank."
  def rewards, do: Enum.map(1..3, &Settings.int("season_reward_#{&1}"))

  @doc "Standings of the week starting on `monday`."
  def standings(monday, limit \\ 50), do: Stats.leaderboard(limit, period(monday))

  @doc "Pays the rewards of the week starting on `monday` (must be over). Idempotent."
  def payout(monday, today \\ Economy.vn_today()) do
    if Date.compare(Date.add(monday, 7), today) == :gt do
      {:error, :season_not_over}
    else
      winners = monday |> standings(3) |> Enum.filter(&(&1.wins > 0))

      paid =
        for {row, amount} <- Enum.zip(winners, rewards()), amount > 0 do
          key = "season:#{monday}:#{row.rank}"

          {row.rank, row.user_id,
           Economy.grant(row.user_id, key, amount, "season_reward", ref(monday))}
        end

      {:ok, paid}
    end
  end

  @doc "Pays last week's season (called every hour)."
  def payout_due(today \\ Economy.vn_today()),
    do: payout(Date.add(week_start(today), -7), today)

  @doc "Rewards paid for the week starting on `monday`: `[%{display_name, username, amount}]`."
  def paid(monday) do
    ref = ref(monday)

    Repo.all(
      from t in CoinTransaction,
        join: u in assoc(t, :user),
        where: t.reason == "season_reward" and t.ref == ^ref,
        order_by: [desc: t.amount],
        select: %{
          user_id: u.id,
          username: u.username,
          display_name: u.display_name,
          amount: t.amount
        }
    )
  end

  defp ref(monday), do: "Tuần #{label(monday)}"
end
