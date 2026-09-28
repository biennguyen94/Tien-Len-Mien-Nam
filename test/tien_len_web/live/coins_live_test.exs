defmodule TienLenWeb.CoinsLiveTest do
  @moduledoc "Phase 17: coin UI. Amounts are always decided by the server (C10)."
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Card, Economy, Lobby, Repo, RoomServer}

  defp cards(codes), do: Card.parse_many!(codes)

  defp set_coins!(user, coins) do
    import Ecto.Query

    Repo.update_all(from(u in TienLen.Accounts.User, where: u.id == ^user.id),
      set: [coins: coins]
    )
  end

  describe "lobby" do
    test "shows the balance in the header and the lobby; daily bonus once" do
      conn = login_conn("An")
      an = test_user("An")
      {:ok, view, _} = live(conn, ~p"/")

      assert has_element?(view, "#my-coins", "1.000")
      assert has_element?(view, "#balance", "1.000")
      assert has_element?(view, "#claim-daily")
      refute has_element?(view, "#claim-relief")

      view |> element("#claim-daily") |> render_click()
      assert has_element?(view, "#my-coins", "1.100")
      refute has_element?(view, "#claim-daily")
      assert Economy.balance(an.id) == 1_100

      # a replayed event does nothing
      render_hook(view, "claim_daily", %{"amount" => 1_000_000})
      assert Economy.balance(an.id) == 1_100
    end

    test "relief appears below 100 and pays 500" do
      conn = login_conn("An")
      set_coins!(test_user("An"), 40)
      {:ok, view, _} = live(conn, ~p"/")

      assert has_element?(view, "#claim-relief")
      view |> element("#claim-relief") |> render_click()
      assert has_element?(view, "#my-coins", "540")
      refute has_element?(view, "#claim-relief")
    end

    test "creating a room with a stake; invalid stakes are refused" do
      {:ok, view, _} = live(login_conn("An"), ~p"/")

      assert render_submit(form(view, "#create-room-form", room: %{stake: "5"})) =~
               "Tiền cược phải là 0 hoặc từ 10 trở lên"

      render_hook(view, "create", %{"room" => %{"stake" => "abc"}})
      assert render(view) =~ "Tiền cược phải là 0 hoặc từ 10 trở lên"

      {:error, {:live_redirect, %{to: "/phong/" <> id}}} =
        view |> form("#create-room-form", room: %{stake: "500"}) |> render_submit()

      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      assert :sys.get_state(RoomServer.whereis(id)).room.stake == 500
    end

    test "the room list shows the stake" do
      {:ok, view, _} = live(login_conn("An"), ~p"/")
      {:ok, id} = Lobby.open_room(stake: 250)
      {:ok, _} = RoomServer.join(id, 999_999, "Chi")
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      assert has_element?(view, "#room-#{id}", "Cược 250")
    end
  end

  describe "table" do
    defp coin_room!(stake, hands) do
      deal = {:hands, Map.new(hands, fn {seat, codes} -> {seat, cards(codes)} end)}

      {:ok, id} =
        RoomServer.start_room(stake: stake, economy: Economy, recorder: nil, deals: [deal])

      pid = RoomServer.whereis(id)
      Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
      id
    end

    test "stake, seat balances and the game's +/− are shown to everyone" do
      id = coin_room!(100, %{0 => "3D", 1 => "4S 9C"})
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")

      assert has_element?(an, "#stake", "Cược 100")
      assert has_element?(an, "#seat-1", "1.000")

      an |> element("#start") |> render_click()
      an |> element("#card-3D") |> render_click()
      an |> element("#play") |> render_click()

      for view <- [an, binh] do
        assert has_element?(view, "#coin-results", "+100")
        assert has_element?(view, "#coin-results", "-100")
        assert has_element?(view, "#delta-0", "+100")
      end

      assert has_element?(an, "#my-coins", "1.100")
      assert has_element?(binh, "#my-coins", "900")
    end

    test "the host changes the stake between games; others cannot" do
      id = coin_room!(0, %{0 => "3D 9H", 1 => "4S 9C"})
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")

      refute has_element?(binh, "#stake-form")
      render_hook(binh, "set_stake", %{"stake" => "500"})
      assert render(binh) =~ "Chỉ chủ phòng"

      an |> form("#stake-form", %{stake: "50"}) |> render_submit()
      assert has_element?(binh, "#stake", "Cược 50")

      an |> form("#stake-form", %{stake: "7"}) |> render_submit()
      assert render(an) =~ "Tiền cược phải là 0 hoặc từ 10 trở lên"
    end

    test "a player without 10×S is told so, and a start without 2 eligible players is refused" do
      id = coin_room!(200, %{0 => "3D 9H", 1 => "4S 9C"})
      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, _binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")

      assert has_element?(an, "#not-eligible", "2.000")
      an |> element("#start") |> render_click()
      assert render(an) =~ "Cần ít nhất 2 người có đủ 10× tiền cược"
    end
  end

  describe "pages" do
    test "coin history lists ledger lines with labels; richest tab ranks by coins" do
      conn = login_conn("An")
      an = test_user("An")
      {:ok, _} = Economy.claim_daily_bonus(an.id)

      {:ok, view, _} = live(conn, ~p"/lich-su-coin")
      assert has_element?(view, "#coin-history", "Tặng khi đăng ký")
      assert has_element?(view, "#coin-history", "Thưởng ngày")
      assert has_element?(view, "#coin-history", "+100")

      {:ok, view, _} = live(conn, ~p"/bang-xep-hang?tab=giau")
      assert has_element?(view, "#rich-#{an.id}", "1.100")
      assert has_element?(view, "#tab-richest.tab-active")
    end

    test "coin pages require login" do
      assert {:error, {:redirect, %{to: "/"}}} = live(sandbox_conn(), ~p"/lich-su-coin")
    end
  end
end
