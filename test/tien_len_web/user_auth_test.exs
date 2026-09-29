defmodule TienLenWeb.UserAuthTest do
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Accounts, Lobby, RoomServer}

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        display_name: "An",
        username: "an_nguyen",
        password: "mat-khau-123"
      })

    %{user: user}
  end

  defp login(conn, username, password),
    do: post(conn, ~p"/dang-nhap", %{"user" => %{"username" => username, "password" => password}})

  describe "login" do
    test "right credentials: session holds the user id, renewed, redirect to lobby", %{
      conn: conn,
      user: user
    } do
      conn =
        conn
        |> init_test_session(%{"planted" => "by attacker"})
        |> login("an_nguyen", "mat-khau-123")

      assert redirected_to(conn) == "/"
      assert get_session(conn, "user_id") == user.id
      assert "user_sessions:" <> _ = get_session(conn, "live_socket_id")
      # session renewed and cleared: nothing planted before login survives (fixation)
      assert get_session(conn, "planted") == nil
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Chào An"
    end

    test "wrong password and unknown user get the same message; no session", %{conn: conn} do
      for {u, p} <- [
            {"an_nguyen", "sai-mat-khau"},
            {"khong_co", "mat-khau-123"},
            {"an_nguyen", ""}
          ] do
        conn = login(conn, u, p)
        assert redirected_to(conn) == "/"
        assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Sai tài khoản hoặc mật khẩu"
        refute get_session(conn, "user_id")
      end
    end

    test "malformed login params do not crash", %{conn: conn} do
      conn = post(conn, ~p"/dang-nhap", %{"user" => "x"})
      assert redirected_to(conn) == "/"
      conn = post(build_conn(), ~p"/dang-nhap", %{})
      assert redirected_to(conn) == "/"
    end
  end

  describe "logout (Y3)" do
    test "clears the session and disconnects this browser's LiveViews", %{conn: conn} do
      conn = login(conn, "an_nguyen", "mat-khau-123")
      socket_id = get_session(conn, "live_socket_id")
      TienLenWeb.Endpoint.subscribe(socket_id)

      conn = conn |> recycle() |> delete(~p"/dang-xuat")
      assert redirected_to(conn) == "/"
      refute get_session(conn, "user_id")
      assert_receive %Phoenix.Socket.Broadcast{topic: ^socket_id, event: "disconnect"}
    end

    test "after logout the lobby shows the login forms again", %{conn: conn} do
      conn = conn |> login("an_nguyen", "mat-khau-123") |> recycle() |> delete(~p"/dang-xuat")
      {:ok, view, _} = live(recycle(conn), ~p"/")
      assert has_element?(view, "#login-form")
    end

    test "logout needs the CSRF-protected DELETE; a GET does nothing", %{conn: conn, user: user} do
      conn = login(conn, "an_nguyen", "mat-khau-123")
      assert (conn |> recycle() |> get("/dang-xuat")).status == 404

      # still logged in afterwards
      conn = conn |> recycle() |> get(~p"/")
      assert conn.assigns.current_user.id == user.id
    end
  end

  describe "session and rooms (A3, Y4)" do
    test "a session pointing at a deleted user is treated as logged out", %{user: user} do
      TienLen.Repo.delete!(user)
      conn = sandbox_conn() |> init_test_session(%{"user_id" => user.id})
      {:ok, view, _} = live(conn, ~p"/")
      assert has_element?(view, "#login-form")
      assert {:error, {:redirect, %{to: "/?next=%2Fphong%2Fabc"}}} = live(conn, ~p"/phong/abc")
    end

    test "the room player id is the user id; two devices of one account share the seat", %{
      user: user
    } do
      {:ok, id} = Lobby.open_room()
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)

      device = fn -> sandbox_conn() |> init_test_session(%{"user_id" => user.id}) end
      {:ok, _phone, _} = live(device.(), ~p"/phong/#{id}")
      {:ok, _laptop, _} = live(device.(), ~p"/phong/#{id}")

      room = :sys.get_state(RoomServer.whereis(id)).room

      assert room.seats == %{
               0 => %{
                 player_id: user.id,
                 name: "An",
                 connected: true,
                 avatar: nil,
                 card_back: "classic"
               }
             }
    end
  end
end
