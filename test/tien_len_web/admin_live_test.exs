defmodule TienLenWeb.AdminLiveTest do
  @moduledoc "Phases 19–21: admin pages and their effects on players' pages."
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Accounts, Admin, Card, Economy, RoomServer}

  @pages ~w(/quan-tri /quan-tri/nguoi-choi /quan-tri/phong /quan-tri/van /quan-tri/nhat-ky /quan-tri/cai-dat)

  defp admin_conn(name) do
    conn = login_conn(name)
    {:ok, _} = Admin.promote(test_user(name).username)
    conn
  end

  describe "access (AD1)" do
    test "logged-out users and players are sent away from every admin page" do
      _ = login_conn("Player")

      for path <- @pages ++ ["/quan-tri/nguoi-choi/1", "/quan-tri/phong/x"] do
        assert {:error, {:redirect, %{to: "/"}}} = live(sandbox_conn(), path)
        assert {:error, {:redirect, %{to: "/"}}} = live(login_conn("Player"), path)
      end
    end

    test "admins reach every page; only admins see the header link" do
      conn = admin_conn("Admin")
      for path <- @pages, do: assert({:ok, _, _} = live(conn, path))
      {:ok, lobby, _} = live(conn, ~p"/")
      assert has_element?(lobby, "#admin-link")
      {:ok, lobby, _} = live(login_conn("Player"), ~p"/")
      refute has_element?(lobby, "#admin-link")
    end

    test "an admin whose role is removed is sent away from the admin page at once" do
      conn_b = admin_conn("Bea")
      _ = admin_conn("Ann")
      {:ok, page, _} = live(conn_b, ~p"/quan-tri")
      {:ok, _} = Admin.set_admin(test_user("Ann").id, test_user("Bea").id, false)
      assert_redirect(page, "/")
    end
  end

  describe "user page (AD4, AD5, F1–F4)" do
    test "set admin, lock with live logout, reset password shown once, adjust coins, rename" do
      conn = admin_conn("Admin")
      player_conn = login_conn("Player")
      player = test_user("Player")
      {:ok, player_lobby, _} = live(player_conn, ~p"/")

      {:ok, view, _} = live(conn, ~p"/quan-tri/nguoi-choi/#{player.id}")

      view
      |> form("#adjust-form", %{"amount" => "250", "reason" => "quà tặng"})
      |> render_submit()

      assert has_element?(view, "#user-coins", "1.250")
      assert has_element?(player_lobby, "#my-coins", "1.250")

      view |> form("#adjust-form", %{"amount" => "-5000", "reason" => "phạt"}) |> render_submit()
      assert render(view) =~ "Không đủ coin để trừ"

      view |> form("#rename-form", %{"name" => "Người Mới"}) |> render_submit()
      assert Accounts.get_user(player.id).display_name == "Người Mới"

      view |> element("#reset-password") |> render_click()
      [temp] = Regex.run(~r{<code[^>]*>([^<]+)</code>}, render(view), capture: :all_but_first)
      assert Accounts.authenticate(player.username, temp)

      view |> element("#lock") |> render_click()
      assert has_element?(view, "#locked-badge")
      assert_redirect(player_lobby, "/")

      conn2 =
        post(sandbox_conn(), ~p"/dang-nhap", %{
          "user" => %{"username" => player.username, "password" => temp}
        })

      assert Phoenix.Flash.get(conn2.assigns.flash, :error) == "Tài khoản đã bị khóa"
      refute get_session(conn2, "user_id")

      view |> element("#unlock") |> render_click()
      view |> element("#set-admin") |> render_click()
      assert Accounts.get_user(player.id).role == "admin"
    end

    test "search finds users" do
      conn = admin_conn("Admin")
      _ = login_conn("Zed Tran")
      {:ok, view, _} = live(conn, ~p"/quan-tri/nguoi-choi?q=zed")
      assert has_element?(view, "#user-#{test_user("Zed Tran").id}")
    end
  end

  describe "rooms (AD6, AD7)" do
    defp cards(codes), do: Card.parse_many!(codes)

    test "watch shows every hand; closing sends players to the lobby" do
      conn = admin_conn("Admin")
      deal = {:hands, %{0 => cards("3D 9H"), 1 => cards("4S 9C")}}
      {:ok, id} = RoomServer.start_room(deals: [deal])
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)

      {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
      {:ok, _binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
      an |> element("#start") |> render_click()

      {:ok, watch, _} = live(conn, ~p"/quan-tri/phong/#{id}")
      html = render(watch)
      for code <- ~w(3D 9H 4S 9C), do: assert(html =~ "/images/cards/#{code}.svg")

      {:ok, rooms, _} = live(conn, ~p"/quan-tri/phong")
      rooms |> element("#aroom-#{id} button", "Đóng") |> render_click()
      {path, flash} = assert_redirect(an)
      assert path == "/"
      assert flash["error"] =~ "quản trị viên đóng"
    end

    test "a player cannot see the watch view" do
      {:ok, id} = RoomServer.start_room()
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)

      assert {:error, {:redirect, %{to: "/"}}} =
               live(login_conn("Player"), ~p"/quan-tri/phong/#{id}")
    end
  end

  describe "login (F8) and password change (F3)" do
    test "after 5 wrong passwords the account's logins are refused" do
      _ = login_conn("Victim")
      u = test_user("Victim")

      for _ <- 1..5 do
        post(sandbox_conn(), ~p"/dang-nhap", %{
          "user" => %{"username" => u.username, "password" => "sai-sai-sai"}
        })
      end

      conn =
        post(sandbox_conn(), ~p"/dang-nhap", %{
          "user" => %{"username" => u.username, "password" => "mat-khau-123"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "quá nhiều lần"
      refute get_session(conn, "user_id")
    end

    test "players change their own password from the lobby" do
      conn = login_conn("Player")
      u = test_user("Player")
      {:ok, view, _} = live(conn, ~p"/")
      view |> element("#toggle-password") |> render_click()

      view
      |> form("#password-form", %{"current" => "sai", "new" => "mat-khau-moi"})
      |> render_submit()

      assert render(view) =~ "Mật khẩu hiện tại không đúng"

      view
      |> form("#password-form", %{"current" => "mat-khau-123", "new" => "mat-khau-moi"})
      |> render_submit()

      assert render(view) =~ "Đã đổi mật khẩu"
      assert Accounts.authenticate(u.username, "mat-khau-moi")
    end
  end

  test "coin adjustments appear in the player's coin history with the admin's name" do
    _ = admin_conn("Admin")
    conn = login_conn("Player")

    {:ok, _} =
      Admin.adjust_coins(test_user("Admin").id, test_user("Player").id, 42, "thưởng sự kiện")

    {:ok, view, _} = live(conn, ~p"/lich-su-coin")
    assert has_element?(view, "#coin-history", "Quản trị viên điều chỉnh")
    assert has_element?(view, "#coin-history", "+42")
    assert Economy.balance(test_user("Player").id) == 1_042
  end
end
