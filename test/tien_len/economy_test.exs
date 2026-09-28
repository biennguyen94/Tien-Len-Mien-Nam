defmodule TienLen.EconomyTest do
  use TienLen.DataCase, async: true

  alias TienLen.{Accounts, Economy}
  alias TienLen.Accounts.User
  alias TienLen.Economy.CoinTransaction

  defp user!(name) do
    {:ok, u} =
      Accounts.register_user(%{
        display_name: name,
        username: String.downcase(name) <> "_#{System.unique_integer([:positive])}",
        password: "mat-khau-123"
      })

    u
  end

  defp set_coins!(user, coins) do
    old = Economy.balance(user.id)
    Repo.update_all(from(u in User, where: u.id == ^user.id), set: [coins: coins])
    # keep the ledger consistent for the invariant checks
    Repo.insert!(%CoinTransaction{
      user_id: user.id,
      amount: coins - old,
      balance_after: coins,
      reason: "test_set"
    })

    %{user | coins: coins}
  end

  defp ledger_sum(user_id) do
    Repo.one(
      from t in CoinTransaction,
        where: t.user_id == ^user_id,
        select: type(sum(t.amount), :integer)
    ) || 0
  end

  describe "starting coins (T19)" do
    test "registration grants 1,000 coins with a ledger line, in the same transaction" do
      u = user!("An")
      assert u.coins == 1_000
      assert Economy.balance(u.id) == 1_000

      assert [%{amount: 1_000, reason: "registration", balance_after: 1_000}] =
               Economy.history(u.id)
    end

    test "a failed registration grants nothing" do
      {:error, _} = Accounts.register_user(%{display_name: "", username: "x", password: "1"})
      assert Repo.aggregate(CoinTransaction, :count) == 0
    end
  end

  describe "daily bonus and relief (E8)" do
    test "the daily bonus is paid once per Vietnam day" do
      u = user!("An")
      day = ~D[2026-09-28]
      assert Economy.claimable(u.id, day).daily_bonus
      assert {:ok, 1_100} = Economy.claim_daily_bonus(u.id, day)
      assert Economy.claim_daily_bonus(u.id, day) == {:error, :already_claimed}
      refute Economy.claimable(u.id, day).daily_bonus
      assert {:ok, 1_200} = Economy.claim_daily_bonus(u.id, Date.add(day, 1))
    end

    test "concurrent claims pay once" do
      u = user!("An")
      day = ~D[2026-09-28]

      results =
        1..10
        |> Enum.map(fn _ -> Task.async(fn -> Economy.claim_daily_bonus(u.id, day) end) end)
        |> Task.await_many()

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Economy.balance(u.id) == 1_100
    end

    test "relief only below 100, once per day" do
      u = user!("An")
      day = ~D[2026-09-28]
      assert Economy.claim_relief(u.id, day) == {:error, :not_eligible}
      refute Economy.claimable(u.id, day).relief

      set_coins!(u, 99)
      assert Economy.claimable(u.id, day).relief
      assert {:ok, 599} = Economy.claim_relief(u.id, day)
      set_coins!(u, 0)
      assert Economy.claim_relief(u.id, day) == {:error, :already_claimed}
      assert {:ok, 500} = Economy.claim_relief(u.id, Date.add(day, 1))
    end

    test "Vietnam day boundary is 17:00 UTC" do
      assert Economy.vn_today(~U[2026-09-28 16:59:59Z]) == ~D[2026-09-28]
      assert Economy.vn_today(~U[2026-09-28 17:00:00Z]) == ~D[2026-09-29]
    end

    test "unknown users" do
      assert Economy.claim_daily_bonus(-1) == {:error, :not_found}
      assert Economy.balance(nil) == 0
    end
  end

  describe "settle/3 (T25, C9, E5)" do
    test "moves coins, writes both ledger lines, broadcasts" do
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      Economy.subscribe(a.id)

      assert {:ok, [%{from: _, to: _, amount: 300}]} =
               Economy.settle(
                 "k1",
                 [%{from: b.id, to: a.id, amount: 300, reason: "place"}],
                 "game:1"
               )

      assert Economy.balance(a.id) == 1_300
      assert Economy.balance(b.id) == 700

      assert [
               %{
                 amount: 300,
                 reason: "place",
                 counterparty: "Binh",
                 ref: "game:1",
                 balance_after: 1_300
               }
               | _
             ] =
               Economy.history(a.id)

      assert_receive {:coins_updated, _, 1_300}
    end

    test "is idempotent by key" do
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      debt = [%{from: b.id, to: a.id, amount: 100, reason: "place"}]
      assert {:ok, [_]} = Economy.settle("same", debt)
      assert Economy.settle("same", debt) == {:ok, :already_applied}
      assert Economy.balance(a.id) == 1_100
    end

    test "a debtor pays at most their balance; never negative" do
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      b = set_coins!(b, 150)

      assert {:ok, [%{amount: 150}]} =
               Economy.settle("k", [%{from: b.id, to: a.id, amount: 500, reason: "place"}])

      assert Economy.balance(b.id) == 0
      assert Economy.balance(a.id) == 1_150
    end

    test "several creditors share proportionally; leftovers go in order (E5)" do
      [a, b, c, d] = Enum.map(~w(An Binh Chi Dung), &user!/1)
      d = set_coins!(d, 100)

      debts = [
        %{from: d.id, to: a.id, amount: 200, reason: "instant_win"},
        %{from: d.id, to: b.id, amount: 200, reason: "instant_win"},
        %{from: d.id, to: c.id, amount: 200, reason: "instant_win"}
      ]

      {:ok, paid} = Economy.settle("k", debts)
      # 100 × 200/600 = 33 each, 1 left over → first creditor
      assert Enum.map(paid, & &1.amount) == [34, 33, 33]
      assert Economy.balance(d.id) == 0
    end

    test "credits never fund debits in the same settlement" do
      [a, b, c] = Enum.map(~w(An Binh Chi), &user!/1)
      b = set_coins!(b, 0)
      # b receives 300 from c but owes 200 to a: b pays nothing (started at 0)
      {:ok, paid} =
        Economy.settle("k", [
          %{from: b.id, to: a.id, amount: 200, reason: "place"},
          %{from: c.id, to: b.id, amount: 300, reason: "thoi"}
        ])

      assert paid == [%{from: c.id, to: b.id, amount: 300, reason: "thoi"}]
      assert Economy.balance(b.id) == 300
    end

    test "ignores empty, self, non-account and non-positive debts" do
      a = user!("An")

      assert {:ok, []} =
               Economy.settle("k", [
                 %{from: a.id, to: a.id, amount: 5, reason: "x"},
                 %{from: :guest, to: a.id, amount: 5, reason: "x"},
                 %{from: a.id, to: -1, amount: 5, reason: "x"},
                 %{from: a.id, to: a.id + 999_999, amount: 0, reason: "x"}
               ])

      assert Economy.balance(a.id) == 1_000
    end

    test "random settlements keep totals, never go negative, and ledgers match balances" do
      users = Enum.map(~w(An Binh Chi Dung), &user!/1)
      ids = Enum.map(users, & &1.id)

      for seed <- 1..300 do
        rng = :rand.seed_s(:exsss, seed)

        {debts, _} =
          Enum.map_reduce(1..4, rng, fn _, rng ->
            {f, rng} = :rand.uniform_s(4, rng)
            {t, rng} = :rand.uniform_s(4, rng)
            {amt, rng} = :rand.uniform_s(900, rng)
            {%{from: Enum.at(ids, f - 1), to: Enum.at(ids, t - 1), amount: amt, reason: "r"}, rng}
          end)

        before = Economy.balances(ids)
        {:ok, paid} = Economy.settle("rand:#{seed}", debts)
        after_ = Economy.balances(ids)

        assert Enum.sum(Map.values(before)) == Enum.sum(Map.values(after_))
        assert Enum.all?(Map.values(after_), &(&1 >= 0))

        for id <- ids do
          out = paid |> Enum.filter(&(&1.from == id)) |> Enum.sum_by(& &1.amount)
          assert out <= before[id]
        end
      end

      for id <- ids, do: assert(ledger_sum(id) == Economy.balance(id))
    end

    test "the database refuses a negative balance even outside Economy" do
      a = user!("An")

      assert_raise Postgrex.Error, ~r/coins_not_negative/, fn ->
        Repo.update_all(from(u in User, where: u.id == ^a.id), set: [coins: -1])
      end
    end
  end

  describe "queries" do
    test "richest orders by coins, then username" do
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      set_coins!(b, 5_000)
      rows = Economy.richest() |> Enum.filter(&(&1.user_id in [a.id, b.id]))
      assert Enum.map(rows, & &1.user_id) == [b.id, a.id]
    end
  end
end
