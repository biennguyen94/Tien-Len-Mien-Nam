defmodule TienLen.Stats do
  @moduledoc """
  Game results, leaderboard and history (decisions A1, Y5, Y6, Y8).

  - `record/1` stores one finished game (called by `TienLen.RoomServer` at game over).
  - The leaderboard counts **wins = 1st places** (A1). Order: wins desc, win rate desc, games
    played asc, username asc (Y5). Instant-win games count (every instant winner wins) and so
    do games a player was removed from (they count as played).
  - Only integer player ids (user ids) are recorded; anything else is ignored.
  - After a successful write, `{:stats_updated}` is broadcast on `topic/0`.
  """

  import Ecto.Query

  alias TienLen.Repo
  alias TienLen.Accounts.User
  alias TienLen.Stats.{GamePlayer, GameRecord}

  @type result :: %{
          room_id: String.t(),
          player_count: pos_integer(),
          instant_win: boolean(),
          players: [
            %{
              user_id: term(),
              seat: integer(),
              place: pos_integer(),
              won: boolean(),
              removed: boolean()
            }
          ]
        }

  def topic, do: "stats"
  def subscribe, do: Phoenix.PubSub.subscribe(TienLen.PubSub, topic())

  @doc "Stores a finished game. Returns `{:ok, game}`, `:skipped` (no account players) or `{:error, reason}`."
  @spec record(result()) :: {:ok, GameRecord.t()} | :skipped | {:error, term()}
  def record(%{players: players} = result) do
    players = Enum.filter(players, &is_integer(&1.user_id))

    if players == [] do
      :skipped
    else
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.transaction(fn ->
        game =
          Repo.insert!(%GameRecord{
            room_id: to_string(result.room_id),
            ref: Map.get(result, :ref),
            player_count: result.player_count,
            instant_win: result.instant_win,
            finished_at: now
          })

        Repo.insert_all(
          GamePlayer,
          Enum.map(
            players,
            &Map.merge(Map.take(&1, [:user_id, :seat, :place, :won, :removed]), %{
              game_id: game.id,
              chops: Map.get(&1, :chops, 0),
              coins: Map.get(&1, :coins, 0),
              instant: Map.get(&1, :instant, false)
            })
          )
        )

        game
      end)
      |> tap(fn
        {:ok, _} -> Phoenix.PubSub.broadcast(TienLen.PubSub, topic(), {:stats_updated})
        _ -> :ok
      end)
    end
  end

  @doc """
  Leaderboard rows `%{rank, user_id, username, display_name, games, wins, win_rate}` for users
  with at least one game. `period` limits it to games finished in `{from, to}` (UTC, `to`
  excluded), used by the weekly season (S1).
  """
  def leaderboard(limit \\ 50, period \\ nil) do
    base_query()
    |> in_period(period)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
  end

  @doc "One user's row with their rank, or `nil` if they have not finished a game."
  def user_standing(user_id) do
    rows = base_query() |> Repo.all()

    Enum.find_value(Enum.with_index(rows, 1), fn {row, rank} ->
      if row.user_id == user_id, do: Map.put(row, :rank, rank)
    end)
  end

  defp in_period(query, nil), do: query

  defp in_period(query, {from, to}) do
    from([gp, u] in query,
      join: g in GameRecord,
      on: g.id == gp.game_id,
      where: g.finished_at >= ^from and g.finished_at < ^to
    )
  end

  defp base_query do
    from(gp in GamePlayer,
      join: u in User,
      on: u.id == gp.user_id,
      group_by: [u.id, u.username, u.display_name, u.avatar],
      select: %{
        user_id: u.id,
        username: u.username,
        display_name: u.display_name,
        avatar: u.avatar,
        games: count(gp.id),
        wins: filter(count(gp.id), gp.won),
        win_rate: fragment("?::float / ?", filter(count(gp.id), gp.won), count(gp.id))
      },
      order_by: [
        desc: filter(count(gp.id), gp.won),
        desc: fragment("?::float / ?", filter(count(gp.id), gp.won), count(gp.id)),
        asc: count(gp.id),
        asc: u.username
      ]
    )
  end

  @doc """
  Profile numbers of a user (P2): games, wins (1st places), win rate, average place, chặt heo,
  tới trắng, net coins from games, biggest win in one game.
  """
  def profile(user_id) do
    from(gp in GamePlayer,
      where: gp.user_id == ^user_id,
      select: %{
        games: count(gp.id),
        wins: filter(count(gp.id), gp.won),
        avg_place: avg(gp.place),
        chops: coalesce(sum(gp.chops), 0),
        instant_wins: filter(count(gp.id), gp.instant),
        coins: coalesce(sum(gp.coins), 0),
        best_coins: coalesce(max(gp.coins), 0)
      }
    )
    |> Repo.one()
    |> then(fn row ->
      %{
        row
        | avg_place: row.avg_place && Decimal.to_float(row.avg_place) |> Float.round(2),
          chops: to_int(row.chops),
          coins: to_int(row.coins),
          best_coins: max(to_int(row.best_coins), 0)
      }
      |> Map.put(:win_rate, if(row.games > 0, do: row.wins / row.games, else: 0.0))
    end)
  end

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n
  defp to_int(nil), do: 0

  @doc """
  Counts of a user's recorded games finished in `{from, to}` (UTC): `%{games, wins, chops}`
  (daily missions, M1).
  """
  def counts(user_id, {from, to}) do
    from(gp in GamePlayer,
      join: g in GameRecord,
      on: g.id == gp.game_id,
      where: gp.user_id == ^user_id and g.finished_at >= ^from and g.finished_at < ^to,
      select: %{
        games: count(gp.id),
        wins: filter(count(gp.id), gp.won),
        chops: coalesce(sum(gp.chops), 0)
      }
    )
    |> Repo.one()
    |> Map.update!(:chops, &to_int/1)
  end

  @doc """
  The user's most recent games, newest first: `%{finished_at, player_count, instant_win, place,
  won, removed, players: [%{display_name, place, won, removed, me}]}`.
  """
  def history(user_id, limit \\ 20) do
    game_ids =
      from(gp in GamePlayer,
        join: g in assoc(gp, :game),
        where: gp.user_id == ^user_id,
        order_by: [desc: g.finished_at, desc: g.id],
        limit: ^limit,
        select: g.id
      )
      |> Repo.all()

    from(g in GameRecord,
      where: g.id in ^game_ids,
      order_by: [desc: g.finished_at, desc: g.id],
      preload: [players: ^from(p in GamePlayer, order_by: [p.place, p.seat], preload: :user)]
    )
    |> Repo.all()
    |> Enum.map(fn g ->
      mine = Enum.find(g.players, &(&1.user_id == user_id))

      %{
        id: g.id,
        finished_at: g.finished_at,
        player_count: g.player_count,
        instant_win: g.instant_win,
        place: mine.place,
        won: mine.won,
        removed: mine.removed,
        players:
          Enum.map(g.players, fn p ->
            %{
              display_name: p.user.display_name,
              place: p.place,
              won: p.won,
              removed: p.removed,
              me: p.user_id == user_id
            }
          end)
      }
    end)
  end
end
