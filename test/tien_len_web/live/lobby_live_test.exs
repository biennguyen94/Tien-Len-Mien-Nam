defmodule TienLenWeb.LobbyLiveTest do
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Lobby, RoomServer}

  test "a new visitor is asked for a name, and the name is stored in the session", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#name-form")

    conn = post(conn, ~p"/ten", %{"name" => "  Bình  ", "return_to" => "/"})
    assert redirected_to(conn) == "/"
    assert get_session(conn, "player_name") == "Bình"

    {:ok, view, _html} = live(recycle(conn), ~p"/")
    assert has_element?(view, "#player-name", "Bình")
    refute has_element?(view, "#name-form")
  end

  test "an invalid name is refused with a message", %{conn: conn} do
    conn = post(conn, ~p"/ten", %{"name" => "   "})
    assert redirected_to(conn) == "/"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Tên không hợp lệ"
    assert get_session(conn, "player_name") == nil
  end

  test "return_to only accepts local paths (no open redirect)", %{conn: conn} do
    for evil <- ["https://evil.example", "//evil.example", "javascript:alert(1)"] do
      assert build_conn()
             |> post(~p"/ten", %{"name" => "A", "return_to" => evil})
             |> redirected_to() == "/"
    end

    assert conn
           |> post(~p"/ten", %{"name" => "A", "return_to" => "/phong/abc"})
           |> redirected_to() ==
             "/phong/abc"
  end

  test "creating a room goes to the table" do
    conn =
      Plug.Test.init_test_session(build_conn(), %{"player_id" => "p1", "player_name" => "An"})

    {:ok, view, _} = live(conn, ~p"/")

    {:error, {:live_redirect, %{to: "/phong/" <> id}}} =
      view |> element("#create-room") |> render_click()

    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    assert RoomServer.whereis(id)
  end

  test "the room list updates live" do
    conn =
      Plug.Test.init_test_session(build_conn(), %{"player_id" => "p1", "player_name" => "An"})

    {:ok, view, _} = live(conn, ~p"/")

    {:ok, id, 0} = Lobby.create_room("someone", "Chi")
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)

    assert render(view) =~ "room-#{id}"
    assert has_element?(view, "#room-#{id}", "Chi")
    assert has_element?(view, "#room-#{id} a", "Vào")
  end
end
