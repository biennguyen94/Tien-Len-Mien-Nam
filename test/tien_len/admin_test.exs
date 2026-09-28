defmodule TienLen.AdminTest do
  @moduledoc "Phases 19–21: TienLen.Admin (AD1–AD8, F1–F6)."
  use TienLen.DataCase, async: true

  alias TienLen.{Accounts, Admin, Card, Economy, RoomServer, Stats}
  alias TienLen.Admin.Action

  defp user!(name) do
    {:ok, u} =
      Accounts.register_user(%{
        display_name: name,
        username:
          String.replace(String.downcase(name), ~r/[^a-z0-9]/, "") <>
            "_#{System.unique_integer([:positive])}",
        password: "mat-khau-123"
      })

    u
  end

  defp admin!(name) do
    u = user!(name)
    {:ok, u} = Admin.promote(u.username)
    u
  end

  defp cards(codes), do: Card.parse_many!(codes)

  defp last_action, do: Repo.one(from a in Action, order_by: [desc: a.id], limit: 1)

  describe "roles (AD1, F1)" do
    test "promote/1 is the server command; audited without an acting admin" do
      u = user!("An")
      assert {:ok, %{role: "admin"}} = Admin.promote(String.upcase(u.username))
      assert %{action: "promote_server", admin_id: nil, target_user_id: target} = last_action()
      assert target == u.id
      assert Admin.promote("nobody_here") == {:error, :not_found}
    end

    test "only unlocked admins are authorized" do
      a = admin!("Ad")
      p = user!("Pl")
      assert {:ok, _} = Admin.authorize(a.id)
      assert Admin.authorize(p.id) == {:error, :forbidden}
      assert Admin.authorize(nil) == {:error, :forbidden}
    end

    test "an admin sets / removes admin; never on themselves; players cannot" do
      a = admin!("Ad")
      p = user!("Pl")
      q = user!("Qu")

      assert Admin.set_admin(p.id, q.id, true) == {:error, :forbidden}
      assert {:ok, %{role: "admin"}} = Admin.set_admin(a.id, p.id, true)
      assert %{action: "set_admin", admin_id: aid} = last_action()
      assert aid == a.id
      assert Admin.set_admin(a.id, p.id, true) == {:error, :already_admin}
      assert Admin.set_admin(a.id, a.id, false) == {:error, :cannot_demote_self}
      assert {:ok, %{role: "player"}} = Admin.set_admin(p.id, a.id, false)
      assert Admin.set_admin(a.id, q.id, true) == {:error, :forbidden}
    end

    test "a demoted admin's pages are told at once" do
      a = admin!("Ad")
      b = admin!("Be")
      Phoenix.PubSub.subscribe(TienLen.PubSub, Admin.user_topic(b.id))
      {:ok, _} = Admin.set_admin(a.id, b.id, false)
      assert_receive {:role_changed, "player"}
    end
  end

  describe "users (AD4, F2, F3)" do
    test "search by username or display name, case-insensitive; wildcards are literal" do
      a = admin!("Ad")
      u = user!("Nguyễn Văn Bình")
      assert Enum.any?(Admin.search_users("văn bình"), &(&1.id == u.id))
      assert Enum.any?(Admin.search_users(String.upcase(u.username)), &(&1.id == u.id))

      assert Admin.search_users("%")
             |> Enum.all?(&String.contains?(&1.username <> &1.display_name, "%"))

      assert a
    end

    test "lock (F2): no login, live logout, removed from rooms; unlock" do
      a = admin!("Ad")
      p = user!("Pl")
      other = user!("Ot")

      {:ok, room} = RoomServer.start_room()
      on_exit(fn -> if pid = RoomServer.whereis(room), do: Process.exit(pid, :kill) end)
      {:ok, _} = RoomServer.join(room, p.id, p.display_name)
      {:ok, _} = RoomServer.join(room, other.id, other.display_name)

      Phoenix.PubSub.subscribe(TienLen.PubSub, Admin.user_topic(p.id))
      assert {:ok, locked} = Admin.lock(a.id, p.id, "spam")
      assert locked.locked_at
      assert_receive {:force_logout}
      assert Accounts.get_active_user(p.id) == nil
      assert RoomServer.view(room, p.id) == {:error, :not_in_room}
      assert %{action: "lock", reason: "spam"} = last_action()

      assert Admin.lock(a.id, p.id) == {:error, :already_locked}
      assert {:ok, _} = Admin.unlock(a.id, p.id)
      assert Accounts.get_active_user(p.id)
      assert Admin.unlock(a.id, p.id) == {:error, :not_locked}
    end

    test "admins cannot lock themselves or another admin; players cannot lock" do
      a = admin!("Ad")
      b = admin!("Be")
      p = user!("Pl")
      assert Admin.lock(a.id, a.id) == {:error, :cannot_lock_self}
      assert Admin.lock(a.id, b.id) == {:error, :cannot_lock_admin}
      assert Admin.lock(p.id, a.id) == {:error, :forbidden}
    end

    test "rename is validated and audited" do
      a = admin!("Ad")
      p = user!("Pl")
      assert {:ok, %{display_name: "Tên Mới"}} = Admin.rename(a.id, p.id, "  Tên   Mới ")
      assert %{action: "rename", details: %{"from" => "Pl", "to" => "Tên Mới"}} = last_action()
      assert {:error, %Ecto.Changeset{}} = Admin.rename(a.id, p.id, "")
    end

    test "reset password (F3): temporary password works once shown; never stored in the log" do
      a = admin!("Ad")
      p = user!("Pl")
      assert {:ok, temp} = Admin.reset_password(a.id, p.id)
      assert String.length(temp) >= 12
      assert Accounts.authenticate(p.username, temp).id == p.id
      assert Accounts.authenticate(p.username, "mat-khau-123") == nil
      action = last_action()
      assert action.action == "reset_password"
      refute inspect(action) =~ temp

      # the player replaces it (F3)
      user = Accounts.get_user(p.id)
      assert Accounts.change_password(user, "wrong", "mat-khau-moi") == {:error, :wrong_password}
      assert {:error, %Ecto.Changeset{}} = Accounts.change_password(user, temp, "short")
      assert {:ok, _} = Accounts.change_password(user, temp, "mat-khau-moi")
      assert Accounts.authenticate(p.username, "mat-khau-moi")
    end
  end

  describe "coin adjustments (AD5, F4)" do
    test "add and remove with a reason, in the ledger and the audit log" do
      a = admin!("Ad")
      p = user!("Pl")

      assert {:ok, 1_500} = Admin.adjust_coins(a.id, p.id, 500, "bù lỗi hệ thống")
      assert {:ok, 1_300} = Admin.adjust_coins(a.id, p.id, -200, "thu hồi")

      assert [
               %{reason: "admin_adjust", amount: -200, counterparty: "Ad", ref: "thu hồi"},
               %{amount: 500} | _
             ] =
               Economy.history(p.id)

      assert %{
               action: "adjust_coins",
               details: %{"amount" => -200, "balance" => 1_300},
               reason: "thu hồi"
             } =
               last_action()
    end

    test "refuses a removal larger than the balance, bad amounts, missing reasons, non-admins" do
      a = admin!("Ad")
      p = user!("Pl")
      assert Admin.adjust_coins(a.id, p.id, -1_001, "quá nhiều") == {:error, :insufficient_coins}
      assert Admin.adjust_coins(a.id, p.id, 0, "không") == {:error, :invalid_amount}
      assert Admin.adjust_coins(a.id, p.id, :invalid, "abc") == {:error, :invalid_amount}
      assert Admin.adjust_coins(a.id, p.id, 10, " x ") == {:error, :reason_required}
      assert Admin.adjust_coins(p.id, p.id, 10, "tự cộng") == {:error, :forbidden}
      assert Economy.balance(p.id) == 1_000
    end

    test "admins may adjust themselves; it is audited (F4)" do
      a = admin!("Ad")
      assert {:ok, 1_010} = Admin.adjust_coins(a.id, a.id, 10, "kiểm thử")
      assert %{action: "adjust_coins", target_user_id: tid} = last_action()
      assert tid == a.id
    end
  end

  describe "rooms (AD6, AD7, F5, F6)" do
    defp coin_room!(hands) do
      deal = {:hands, Map.new(hands, fn {s, c} -> {s, cards(c)} end)}

      {:ok, id} =
        RoomServer.start_room(stake: 100, economy: Economy, recorder: Stats, deals: [deal])

      pid = RoomServer.whereis(id)
      Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
      id
    end

    test "watch shows every hand, to admins only" do
      a = admin!("Ad")
      [p, q] = Enum.map(~w(Pl Qu), &user!/1)
      id = coin_room!(%{0 => "3D 9H", 1 => "4S 9C"})
      for u <- [p, q], do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
      :ok = RoomServer.start_game(id, p.id)

      assert {:ok, view} = Admin.watch(a.id, id)
      assert view.game.hands == %{0 => cards("3D 9H"), 1 => cards("4S 9C")}
      assert Admin.watch(p.id, id) == {:error, :forbidden}
      assert Admin.watch(a.id, "nope") == {:error, :room_not_found}
    end

    test "closing mid-game (F5): settled chains stay, nothing else is paid or recorded" do
      a = admin!("Ad")
      [p, q, r] = Enum.map(~w(Pl Qu Ro), &user!/1)
      id = coin_room!(%{0 => "3D 2H 9H", 1 => "4S 4C 5S 5C 6S 6C 9D", 2 => "10D JD 2S"})
      for u <- [p, q, r], do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
      :ok = RoomServer.start_game(id, p.id)

      :ok = RoomServer.play(id, p.id, cards("3D"))
      :ok = RoomServer.pass(id, q.id)
      :ok = RoomServer.pass(id, r.id)
      :ok = RoomServer.play(id, p.id, cards("2H"))
      :ok = RoomServer.play(id, q.id, cards("4S 4C 5S 5C 6S 6C"))
      :ok = RoomServer.pass(id, r.id)
      # round ends: the chain is settled (p pays q 200)
      :ok = RoomServer.pass(id, p.id)
      assert Economy.balance(q.id) == 1_200

      RoomServer.subscribe(id)
      assert :ok = Admin.close_room(a.id, id, "test")
      assert_receive {:room_updated, ^id, _, [{:closed_by_admin}]}
      assert RoomServer.whereis(id) == nil

      assert Economy.balance(p.id) == 800
      assert Economy.balance(q.id) == 1_200
      assert Economy.balance(r.id) == 1_000
      assert Stats.history(p.id) == []
      assert %{action: "close_room", details: %{"room_id" => ^id}} = last_action()
    end

    test "kick removes the player and bans them from the room" do
      a = admin!("Ad")
      [p, q] = Enum.map(~w(Pl Qu), &user!/1)
      {:ok, id} = RoomServer.start_room()
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      for u <- [p, q], do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)

      assert :ok = Admin.kick(a.id, id, q.id)
      assert RoomServer.view(id, q.id) == {:error, :not_in_room}
      assert RoomServer.join(id, q.id, "Qu") == {:error, :kicked}
      assert Admin.kick(p.id, id, p.id) == {:error, :forbidden}
    end
  end

  describe "dashboard and games (AD3, AD8)" do
    test "numbers, and a recorded game shows its coin transfers" do
      a = admin!("Ad")
      [p, q] = Enum.map(~w(Pl Qu), &user!/1)
      d = Admin.dashboard()
      assert d.users >= 3 and d.admins >= 1
      assert d.coins_in_circulation >= 3_000

      deal = {:hands, %{0 => cards("3D"), 1 => cards("4S 9C")}}

      {:ok, id} =
        RoomServer.start_room(stake: 100, economy: Economy, recorder: Stats, deals: [deal])

      pid = RoomServer.whereis(id)
      Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
      for u <- [p, q], do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
      :ok = RoomServer.start_game(id, p.id)
      :ok = RoomServer.play(id, p.id, cards("3D"))

      assert Admin.dashboard().games_today >= 1
      [%{game: g, transfers: transfers} | _] = Admin.games(5)
      assert g.room_id == id
      assert [%{from: "Qu", to: "Pl", amount: 100, reason: "place"}] = transfers
      assert a
    end
  end

  test "the audit log lists actions with names" do
    a = admin!("Ad")
    p = user!("Pl")
    {:ok, _} = Admin.rename(a.id, p.id, "Mới")
    assert [%{action: "rename", admin: admin, target: target} | _] = Admin.actions(5)
    assert admin == a.username and target == p.username
  end
end
