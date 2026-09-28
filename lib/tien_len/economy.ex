defmodule TienLen.Economy do
  @moduledoc """
  Virtual coins (RULES T19–T25; decisions C1–C10, E5, E6, E8, E9).

  The only module that changes balances. Everything runs in database transactions with row
  locks; every operation is recorded in the append-only ledger (`coin_transactions`) and is
  idempotent through a unique key in `coin_settlements`. Balances can never go negative (a
  `CHECK` constraint backs this up).

  Game code never passes balances or chooses who pays: `TienLen.Payout` turns a game's result
  into **debts** (`%{from, to, amount, reason}`), and `settle/3` applies them:

  - every debtor pays at most the balance they had when the settlement started (C9);
  - several creditors of one debtor share what was paid proportionally, rounding down, with
    the leftover coins going to the creditors in the order given (E5);
  - credits are added after all debits are computed, so the order of debts cannot make a
    balance negative; the total change is always 0.

  After a commit, `{:coins_updated, user_id, balance}` is broadcast on `topic(user_id)`.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias TienLen.Accounts.User
  alias TienLen.Economy.CoinTransaction
  alias TienLen.Repo

  @starting_coins 1_000
  @daily_bonus 100
  @relief 500
  @relief_below 100
  # Vietnam has no daylight saving time: UTC+7 all year (E8)
  @vn_offset 7 * 3600

  def starting_coins, do: @starting_coins
  def daily_bonus, do: @daily_bonus
  def relief, do: @relief
  def relief_below, do: @relief_below

  def topic(user_id), do: "coins:#{user_id}"
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(TienLen.PubSub, topic(user_id))

  @doc "Today's date in Vietnam (UTC+7)."
  def vn_today(now \\ DateTime.utc_now()),
    do: now |> DateTime.add(@vn_offset, :second) |> DateTime.to_date()

  # -- queries --------------------------------------------------------------------

  @doc "The user's balance (0 for an unknown id)."
  def balance(user_id) when is_integer(user_id) do
    Repo.one(from u in User, where: u.id == ^user_id, select: u.coins) || 0
  end

  def balance(_), do: 0

  @doc "Balances of several users: `%{user_id => coins}` (integer ids only)."
  def balances(user_ids) do
    ids = Enum.filter(user_ids, &is_integer/1)
    Repo.all(from u in User, where: u.id in ^ids, select: {u.id, u.coins}) |> Map.new()
  end

  @doc "What the user may claim today: `%{daily_bonus: boolean, relief: boolean}`."
  def claimable(user_id, today \\ vn_today()) do
    case Repo.get(User, user_id) do
      nil ->
        %{daily_bonus: false, relief: false}

      user ->
        %{
          daily_bonus: user.daily_bonus_on != today,
          relief: user.relief_on != today and user.coins < @relief_below
        }
    end
  end

  @doc "The user's ledger, newest first, with the counterparty's display name."
  def history(user_id, limit \\ 50) do
    from(t in CoinTransaction,
      where: t.user_id == ^user_id,
      left_join: c in assoc(t, :counterparty),
      order_by: [desc: t.id],
      limit: ^limit,
      select: %{
        id: t.id,
        amount: t.amount,
        balance_after: t.balance_after,
        reason: t.reason,
        ref: t.ref,
        counterparty: c.display_name,
        inserted_at: t.inserted_at
      }
    )
    |> Repo.all()
  end

  @doc "Richest players: `%{rank, user_id, username, display_name, coins}`."
  def richest(limit \\ 50) do
    from(u in User,
      order_by: [desc: u.coins, asc: u.username],
      limit: ^limit,
      select: %{user_id: u.id, username: u.username, display_name: u.display_name, coins: u.coins}
    )
    |> Repo.all()
    |> Enum.with_index(1)
    |> Enum.map(fn {row, rank} -> Map.put(row, :rank, rank) end)
  end

  # -- grants ---------------------------------------------------------------------

  @doc """
  Multi steps that give a freshly inserted user (under `:user` in the multi) their starting
  coins. Used by `TienLen.Accounts.register_user/1` so the user and the grant commit together.
  """
  def grant_starting_coins(multi) do
    multi
    |> Multi.update(:starting_coins, fn %{user: user} ->
      Ecto.Changeset.change(user, coins: @starting_coins)
    end)
    |> Multi.insert(:starting_coins_ledger, fn %{user: user} ->
      %CoinTransaction{
        user_id: user.id,
        amount: @starting_coins,
        balance_after: @starting_coins,
        reason: "registration"
      }
    end)
  end

  @doc "Claims today's daily bonus (E8). `{:ok, balance}` or `{:error, :already_claimed | :not_found}`."
  def claim_daily_bonus(user_id, today \\ vn_today()) do
    claim(user_id, "daily:#{user_id}:#{today}", @daily_bonus, "daily_bonus", fn user ->
      if user.daily_bonus_on == today,
        do: {:error, :already_claimed},
        else: {:ok, [daily_bonus_on: today]}
    end)
  end

  @doc """
  Claims relief when the balance is below #{@relief_below} (E8).
  `{:ok, balance}` or `{:error, :already_claimed | :not_eligible | :not_found}`.
  """
  def claim_relief(user_id, today \\ vn_today()) do
    claim(user_id, "relief:#{user_id}:#{today}", @relief, "relief", fn user ->
      cond do
        user.relief_on == today -> {:error, :already_claimed}
        user.coins >= @relief_below -> {:error, :not_eligible}
        true -> {:ok, [relief_on: today]}
      end
    end)
  end

  defp claim(user_id, key, amount, reason, check) do
    result =
      Repo.transaction(fn ->
        with {:ok, user} <- lock_user(user_id),
             {:ok, changes} <- check.(user),
             :ok <- mark_settled(key) do
          balance = user.coins + amount
          user |> Ecto.Changeset.change([coins: balance] ++ changes) |> Repo.update!()

          Repo.insert!(%CoinTransaction{
            user_id: user_id,
            amount: amount,
            balance_after: balance,
            reason: reason
          })

          balance
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    with {:ok, balance} <- result do
      broadcast(user_id, balance)
      {:ok, balance}
    end
  end

  defp lock_user(user_id) when is_integer(user_id) do
    case Repo.one(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE") do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp lock_user(_), do: {:error, :not_found}

  # Inserting the key fails if the operation was already applied (idempotency).
  defp mark_settled(key) do
    case Repo.insert_all(
           "coin_settlements",
           [%{key: key, inserted_at: DateTime.utc_now() |> DateTime.truncate(:second)}],
           on_conflict: :nothing
         ) do
      {1, _} -> :ok
      {0, _} -> {:error, :already_claimed}
    end
  end

  # -- settlements ----------------------------------------------------------------

  @type debt :: %{from: integer(), to: integer(), amount: non_neg_integer(), reason: String.t()}

  @doc """
  Applies `debts` once for `key` (T25). Debts with a non-positive amount, a non-integer party,
  or `from == to` are ignored. Returns `{:ok, paid}` where `paid` lists the transfers actually
  made (`%{from, to, amount, reason}`), `{:ok, :already_applied}` if `key` was settled before,
  or `{:error, reason}`.
  """
  @spec settle(String.t(), [debt()], String.t() | nil) ::
          {:ok, [debt()] | :already_applied} | {:error, term()}
  def settle(key, debts, ref \\ nil) do
    debts =
      Enum.filter(debts, fn d ->
        is_integer(d.from) and is_integer(d.to) and d.from != d.to and is_integer(d.amount) and
          d.amount > 0
      end)

    result =
      Repo.transaction(fn ->
        case mark_settled("settle:" <> key) do
          {:error, _} ->
            :already_applied

          :ok ->
            users = lock_users(Enum.flat_map(debts, &[&1.from, &1.to]))
            paid = pay(debts, Map.new(users, &{&1.id, &1.coins}))
            write(paid, users, ref)
            paid
        end
      end)

    with {:ok, paid} when is_list(paid) <- result do
      paid
      |> Enum.flat_map(&[&1.from, &1.to])
      |> Enum.uniq()
      |> then(&balances/1)
      |> Enum.each(fn {id, bal} -> broadcast(id, bal) end)
    end

    result
  end

  # Lock in id order so concurrent settlements cannot deadlock.
  defp lock_users(ids) do
    ids = ids |> Enum.uniq() |> Enum.sort()
    Repo.all(from u in User, where: u.id in ^ids, order_by: u.id, lock: "FOR UPDATE")
  end

  # Caps every debtor at their starting balance and shares proportionally (C9, E5).
  # Debts keep their original order (by index) in the result.
  defp pay(debts, balances) do
    debts
    |> Enum.with_index()
    |> Enum.filter(fn {d, _i} ->
      Map.has_key?(balances, d.from) and Map.has_key?(balances, d.to)
    end)
    |> Enum.group_by(fn {d, _i} -> d.from end)
    |> Enum.flat_map(fn {debtor, owed} ->
      total = Enum.sum_by(owed, fn {d, _i} -> d.amount end)
      available = min(total, balances[debtor])
      shares = Enum.map(owed, fn {d, _i} -> div(d.amount * available, total) end)

      {paid, _left} =
        owed
        |> Enum.zip(shares)
        |> Enum.map_reduce(available - Enum.sum(shares), fn {{d, i}, share}, left ->
          extra = min(left, d.amount - share)
          {{%{d | amount: share + extra}, i}, left - extra}
        end)

      paid
    end)
    |> Enum.sort_by(fn {_d, i} -> i end)
    |> Enum.map(fn {d, _i} -> d end)
    |> Enum.filter(&(&1.amount > 0))
  end

  defp write(paid, users, ref) do
    start = Map.new(users, &{&1.id, &1.coins})

    {rows, final} =
      Enum.flat_map_reduce(paid, start, fn d, bal ->
        bal = bal |> Map.update!(d.from, &(&1 - d.amount)) |> Map.update!(d.to, &(&1 + d.amount))

        rows = [
          %{
            user_id: d.from,
            amount: -d.amount,
            balance_after: bal[d.from],
            reason: d.reason,
            counterparty_id: d.to,
            ref: ref
          },
          %{
            user_id: d.to,
            amount: d.amount,
            balance_after: bal[d.to],
            reason: d.reason,
            counterparty_id: d.from,
            ref: ref
          }
        ]

        {rows, bal}
      end)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if rows != [],
      do: Repo.insert_all(CoinTransaction, Enum.map(rows, &Map.put(&1, :inserted_at, now)))

    for {id, coins} <- final, coins != start[id] do
      from(u in User, where: u.id == ^id) |> Repo.update_all(set: [coins: coins])
    end
  end

  @doc "Topic with a `{:coins_changed}` message after any balance change (richest list)."
  def all_topic, do: "coins"

  defp broadcast(user_id, balance) do
    Phoenix.PubSub.broadcast(TienLen.PubSub, topic(user_id), {:coins_updated, user_id, balance})
    Phoenix.PubSub.broadcast(TienLen.PubSub, all_topic(), {:coins_changed})
  end
end
