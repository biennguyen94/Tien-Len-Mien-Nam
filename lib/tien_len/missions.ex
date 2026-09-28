defmodule TienLen.Missions do
  @moduledoc """
  Daily missions (decisions M1–M4). The same three missions every Vietnam day (UTC+7):

  | key | mission | reward (setting) |
  |---|---|---|
  | `play` | play 5 recorded games | `mission_play_reward` (100) |
  | `win` | finish 1st in 2 games | `mission_win_reward` (150) |
  | `chop` | chặt heo once | `mission_chop_reward` (200) |

  Progress is read from the recorded games of the day (`TienLen.Stats.counts/2`), so games
  with bots, which are not recorded (B3), never count. The reward is claimed with a button,
  once per mission and day (idempotency key `mission:<user>:<date>:<key>`), through
  `TienLen.Economy.grant/5` (ledger reason `mission`).
  """

  alias TienLen.{Economy, Settings, Stats}

  @missions [
    %{key: "play", title: "Chơi 5 ván", stat: :games, goal: 5},
    %{key: "win", title: "Về nhất 2 ván", stat: :wins, goal: 2},
    %{key: "chop", title: "Chặt heo 1 lần", stat: :chops, goal: 1}
  ]

  def keys, do: Enum.map(@missions, & &1.key)

  @doc "Today's missions of a user with progress, reward and state."
  def today(user_id, date \\ Economy.vn_today()) do
    counts = Stats.counts(user_id, Economy.vn_day_bounds(date))

    for m <- @missions do
      progress = min(Map.fetch!(counts, m.stat), m.goal)

      Map.merge(m, %{
        progress: progress,
        reward: reward(m.key),
        done: progress >= m.goal,
        claimed: Economy.settled?(key(user_id, date, m.key))
      })
    end
  end

  @doc "Claims a finished mission's reward. `{:ok, balance}` or `{:error, reason}`."
  def claim(user_id, mission_key, date \\ Economy.vn_today()) do
    case Enum.find(today(user_id, date), &(&1.key == mission_key)) do
      nil -> {:error, :unknown_mission}
      %{done: false} -> {:error, :mission_not_done}
      m -> Economy.grant(user_id, key(user_id, date, m.key), m.reward, "mission", m.title)
    end
  end

  defp reward(key), do: Settings.int("mission_#{key}_reward")
  defp key(user_id, date, key), do: "mission:#{user_id}:#{date}:#{key}"
end
