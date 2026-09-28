defmodule TienLenWeb.LobbyLiveTest do
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Accounts, Lobby, RoomServer}

  describe "logged out (A2, A3)" do
    test "the lobby shows the register form (3 fields) and the login form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "Chào bạn! Bạn tên gì?"
      assert has_element?(view, "#register-form input[name='user[display_name]']")
      assert has_element?(view, "#register-form input[name='user[username]']")
      assert has_element?(view, "#register-form input[name='user[password]'][type=password]")
      assert has_element?(view, "#login-form input[name='user[username]']")
      assert has_element?(view, "#login-form input[name='user[password]'][type=password]")
      refute has_element?(view, "#create-room")
      refute has_element?(view, "#rooms")
    end

    test "registration errors are shown live, in Vietnamese", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      html =
        view
        |> form("#register-form",
          user: %{display_name: " ", username: "A!", password: "short"}
        )
        |> render_change()

      assert html =~ "Hãy nhập tên hiển thị"
      assert html =~ "Tài khoản gồm 3–20 ký tự"
      assert html =~ "Mật khẩu phải có ít nhất 8 ký tự"
    end

    test "a taken username (any case) is refused", %{conn: conn} do
      {:ok, _} =
        Accounts.register_user(%{display_name: "An", username: "an_nguyen", password: "12345678"})

      {:ok, view, _} = live(conn, ~p"/")

      html =
        view
        |> form("#register-form",
          user: %{display_name: "B", username: "AN_Nguyen", password: "12345678"}
        )
        |> render_submit()

      assert html =~ "Tài khoản này đã có người dùng"
    end

    test "registering logs the new user in and shows the lobby", %{conn: conn} do
      {:ok, view, _} = live(conn, ~p"/")

      form =
        form(view, "#register-form",
          user: %{display_name: "Bình", username: "Binh.Tran", password: "mat-khau-123"}
        )

      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == "/"
      user = Accounts.authenticate("binh.tran", "mat-khau-123")
      assert user.display_name == "Bình"
      assert get_session(conn, "user_id") == user.id

      {:ok, lobby, _} = live(recycle(conn), ~p"/")
      assert has_element?(lobby, "#player-name", "Bình")
      assert has_element?(lobby, "#logout")
    end
  end

  describe "logged in" do
    test "creating a room goes to the table" do
      {:ok, view, _} = live(login_conn("An"), ~p"/")

      {:error, {:live_redirect, %{to: "/phong/" <> id}}} =
        view |> form("#create-room-form", room: %{stake: "0"}) |> render_submit()

      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      assert RoomServer.whereis(id)
    end

    test "the room list updates live" do
      {:ok, view, _} = live(login_conn("An"), ~p"/")

      {:ok, id, 0} = Lobby.create_room(123_456, "Chi")
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)

      assert has_element?(view, "#room-#{id}", "Chi")
      assert has_element?(view, "#room-#{id} a", "Vào")
    end

    test "the display name can be changed and is saved" do
      {:ok, view, _} = live(login_conn("An"), ~p"/")
      view |> element("button", "đổi tên") |> render_click()
      view |> form("#profile-form", profile: %{display_name: "  An   Nguyễn "}) |> render_submit()

      assert has_element?(view, "#player-name", "An Nguyễn")
      assert Accounts.get_user(test_user("An").id).display_name == "An Nguyễn"
    end

    test "an invalid new display name is refused" do
      {:ok, view, _} = live(login_conn("An"), ~p"/")
      view |> element("button", "đổi tên") |> render_click()
      html = view |> form("#profile-form", profile: %{display_name: "   "}) |> render_submit()

      assert html =~ "Tên không hợp lệ"
      assert Accounts.get_user(test_user("An").id).display_name == "An"
    end
  end
end
