defmodule TienLen.Shame do
  @moduledoc """
  Shame titles of the week (decisions XH1–XH4): computed from the week's recorded games
  (Monday–Sunday, Vietnam time, like `TienLen.Seasons`), so games with bots never count.

  Per player the week's sums are read in one query; each title then ranks the players by its
  value (a holder needs at least one occurrence; 🙈 needs at least #{30} moves). Ties: fewer
  games first (worse per game), then the earlier account. No coins are attached.

  `titles_of/1` (used when joining a room) is cached for #{60} s per week.
  """

  import Ecto.Query

  alias TienLen.{Repo, Seasons}
  alias TienLen.Accounts.User
  alias TienLen.Stats.{GamePlayer, GameRecord}

  @min_moves 30
  @cache_ms 60_000

  @titles [
    %{id: "thoi", emoji: "🐷", name: "Vua Thối Heo", what: "thối nhiều heo nhất", unit: "heo"},
    %{id: "cong", emoji: "🥶", name: "Chúa Tể Cóng", what: "bị cóng nhiều nhất", unit: "ván cóng"},
    %{id: "pass", emoji: "🙈", name: "Thánh Bỏ Lượt", what: "tỉ lệ bỏ lượt cao nhất", unit: "%"},
    %{id: "chop", emoji: "🔪", name: "Đồ Tể", what: "chặt heo nhiều nhất", unit: "lần chặt"},
    %{
      id: "slow",
      emoji: "🐢",
      name: "Rùa Thần",
      what: "để hết giờ nhiều nhất",
      unit: "lần hết giờ"
    }
  ]

  @doc "The titles, in display order."
  def titles, do: @titles

  @doc "Minimum number of own moves in the week for 🙈 Thánh Bỏ Lượt."
  def min_moves, do: @min_moves

  @doc """
  The top `n` of each title for the week starting on `monday`:
  `[{title, [%{user_id, username, display_name, avatar, value, games}]}]`.
  """
  def standings(monday \\ Seasons.week_start(), n \\ 3) do
    rows = week_rows(monday)
    Enum.map(@titles, fn title -> {title, rank(title, rows) |> Enum.take(n)} end)
  end

  @doc "Titles (`%{id, emoji, name}`) a user holds this week (cached #{60} s)."
  def titles_of(user_id) when is_integer(user_id) do
    holders()
    |> Map.get(user_id, [])
  end

  def titles_of(_), do: []

  # user_id => [title], for the current week
  defp holders do
    monday = Seasons.week_start()
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, monday}, nil) do
      {at, holders} when now - at < @cache_ms ->
        holders

      _ ->
        holders =
          monday
          |> standings(1)
          |> Enum.reduce(%{}, fn
            {title, [top | _]}, acc ->
              Map.update(acc, top.user_id, [short(title)], &(&1 ++ [short(title)]))

            {_title, []}, acc ->
              acc
          end)

        :persistent_term.put({__MODULE__, monday}, {now, holders})
        holders
    end
  end

  @doc false
  def clear_cache, do: :persistent_term.erase({__MODULE__, Seasons.week_start()})

  defp short(title), do: Map.take(title, [:id, :emoji, :name])

  defp week_rows(monday) do
    {from, to} = Seasons.period(monday)

    from(gp in GamePlayer,
      join: g in GameRecord,
      on: g.id == gp.game_id,
      join: u in User,
      on: u.id == gp.user_id,
      where: g.finished_at >= ^from and g.finished_at < ^to and is_nil(u.locked_at),
      group_by: [u.id, u.username, u.display_name, u.avatar],
      select: %{
        user_id: u.id,
        username: u.username,
        display_name: u.display_name,
        avatar: u.avatar,
        games: count(gp.id),
        thoi: sum(gp.thoi),
        cong: filter(count(gp.id), gp.cong),
        chop: sum(gp.chops),
        slow: sum(gp.timeouts),
        passes: sum(gp.passes),
        plays: sum(gp.plays)
      }
    )
    |> Repo.all()
  end

  defp rank(title, rows) do
    rows
    |> Enum.map(&Map.put(&1, :value, value(title.id, &1)))
    |> Enum.filter(&eligible?(title.id, &1))
    |> Enum.sort_by(&{-&1.value, &1.games, &1.user_id})
  end

  defp value("pass", row) do
    moves = row.passes + row.plays
    if moves > 0, do: round(row.passes * 100 / moves), else: 0
  end

  defp value(id, row), do: Map.fetch!(row, String.to_existing_atom(id)) || 0

  defp eligible?("pass", row), do: row.passes + row.plays >= @min_moves and row.passes > 0
  defp eligible?(_id, row), do: row.value > 0
end
