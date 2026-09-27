defmodule TienLenWeb.PlayerIdentityTest do
  use TienLenWeb.ConnCase, async: true

  alias TienLen.{Lobby, RoomServer}
  alias TienLenWeb.PlayerIdentity

  describe "plug" do
    test "gives a new session a random player id and keeps it across requests", %{conn: conn} do
      conn = get(conn, ~p"/")
      id = get_session(conn, "player_id")
      assert is_binary(id) and byte_size(id) >= 20
      assert conn.assigns.player_id == id

      conn = conn |> recycle() |> get(~p"/")
      assert get_session(conn, "player_id") == id
    end

    test "different sessions get different ids" do
      a = build_conn() |> get(~p"/") |> get_session("player_id")
      b = build_conn() |> get(~p"/") |> get_session("player_id")
      refute a == b
    end

    test "a tampered session cookie does not yield the chosen id", %{conn: conn} do
      conn = get(conn, ~p"/")
      id = get_session(conn, "player_id")
      [cookie] = Plug.Conn.get_resp_header(conn, "set-cookie")
      value = cookie |> String.split(";") |> hd() |> String.split("=", parts: 2) |> List.last()

      forged =
        build_conn()
        |> put_req_header("cookie", "_tien_len_key=" <> String.replace(value, "A", "B"))
        |> get(~p"/")

      refute get_session(forged, "player_id") == id
    end
  end

  describe "seat tokens" do
    test "sign/verify round-trip" do
      token = PlayerIdentity.sign("player-123")
      assert PlayerIdentity.verify(token) == {:ok, "player-123"}
    end

    test "forged, garbage, missing and expired tokens are rejected" do
      token = PlayerIdentity.sign("player-123")
      assert PlayerIdentity.verify(token <> "x") == {:error, :invalid}
      assert PlayerIdentity.verify("not-a-token") == {:error, :invalid}
      assert PlayerIdentity.verify(nil) == {:error, :missing}
      assert PlayerIdentity.verify(token, max_age: -1) == {:error, :expired}

      other_salt = Phoenix.Token.sign(TienLenWeb.Endpoint, "another salt", "player-123")
      assert PlayerIdentity.verify(other_salt) == {:error, :invalid}
    end

    test "a verified token reconnects the player to their seat" do
      {:ok, id, 0} = Lobby.create_room("host-id", "An")
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      {:ok, 1} = Lobby.join_room(id, "player-123", "Bình")

      {:ok, player_id} = "player-123" |> PlayerIdentity.sign() |> PlayerIdentity.verify()
      assert Lobby.join_room(id, player_id, "Bình") == {:ok, 1}

      assert {:error, :invalid} = PlayerIdentity.verify(PlayerIdentity.sign("player-123") <> "x")
    end
  end
end
