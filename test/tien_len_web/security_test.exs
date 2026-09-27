defmodule TienLenWeb.SecurityTest do
  @moduledoc """
  Phase 10 security review: one check per risk in `docs/RISKS.md` section A (R1–R9) where it
  is not already covered elsewhere, plus web-layer checks (XSS, resume links, tampered events).
  """

  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Card, Lobby, RoomServer}

  defp player_conn(name), do: login_conn(name)

  defp open_room!(opts) do
    {:ok, id} = Lobby.open_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  defp deal(map),
    do: {:hands, Map.new(map, fn {seat, codes} -> {seat, Card.parse_many!(codes)} end)}

  describe "R1 — the shuffle seed never leaves the server and is not kept" do
    test "after a seeded game starts, the room process holds no seed" do
      id = open_room!([])
      {:ok, _, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, _, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      :ok = Lobby.start_game(id, test_user("An").id)

      state = :sys.get_state(RoomServer.whereis(id))
      assert state.deals == []
      refute Map.has_key?(Map.from_struct(state.room.game), :seed)
    end
  end

  describe "R3/R4 — a client cannot choose who it is or act for someone else" do
    test "LiveView identity comes only from the signed session (user id), not from params" do
      id = open_room!(deals: [deal(%{0 => "3S 9H", 1 => "4S 9C"})])
      {:ok, _binh_first, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      binh_id = test_user("Binh").id

      {:ok, an, _} =
        live(player_conn("An"), ~p"/phong/#{id}?player_id=#{binh_id}&user_id=#{binh_id}")

      binh = RoomServer.whereis(id)
      # Bình joined first (seat 0, host); An is seat 1 whatever the URL says
      assert :sys.get_state(binh).room.seats[1].player_id == test_user("An").id
      :ok = Lobby.start_game(id, binh_id)

      # An's page shows seat 1's cards (4S 9C), not Bình's
      assert has_element?(an, "#card-4S")
      refute has_element?(an, "#card-3S")
    end

    test "events cannot pick another player's cards or seat" do
      id = open_room!(deals: [deal(%{0 => "3S 9H", 1 => "4S 9C"})])
      {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      an |> element("#start") |> render_click()

      # Bình pushes toggles for An's cards and plays out of turn
      render_hook(binh, "toggle", %{"card" => "3S"})
      render_hook(binh, "play", %{})
      render_hook(binh, "play", %{"seat" => 0, "cards" => ["3S"]})
      assert has_element?(an, "#card-3S")
      refute has_element?(an, "#centre img")
    end
  end

  describe "R6/R7 — tampered or malformed events are ignored" do
    test "unknown events, junk params and foreign card codes do nothing" do
      id = open_room!(deals: [deal(%{0 => "3S 9H", 1 => "4S 9C"})])
      {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, _binh, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      an |> element("#start") |> render_click()
      parts = fn -> for sel <- ~w(#hand #centre #actions), do: an |> element(sel) |> render() end
      before = parts.()

      for {event, params} <- [
            {"toggle", %{"card" => "ZZ"}},
            {"toggle", %{"card" => 42}},
            {"toggle", %{}},
            {"toggle", %{"card" => "4S"}},
            {"explode", %{"x" => 1}}
          ] do
        render_hook(an, event, params)
      end

      assert Process.alive?(an.pid)
      assert parts.() == before
    end

    test "the lobby ignores unknown events" do
      {:ok, lobby, _} = live(player_conn("An"), ~p"/")
      render_hook(lobby, "nuke", %{"all" => true})
      assert Process.alive?(lobby.pid)
    end
  end

  describe "R9 — rooms are created only through the lobby" do
    test "visiting an unknown room id does not create it" do
      conn = player_conn("An")
      {:ok, _lobby, _} = conn |> live(~p"/phong/made-up-id") |> follow_redirect(conn, "/")
      assert RoomServer.whereis("made-up-id") == nil
    end
  end

  describe "XSS" do
    test "a display name with HTML is escaped everywhere it is shown" do
      evil = "<script>x()</script>"
      conn = login_conn(evil)
      {:ok, id, 0} = Lobby.create_room(test_user(evil).id, evil)
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)

      {:ok, lobby, _} = live(player_conn("An"), ~p"/")
      html = render(lobby)
      refute html =~ evil
      assert html =~ "&lt;script&gt;"

      {:ok, table, _} = live(conn, ~p"/phong/#{id}")
      refute render(table) =~ evil
    end
  end
end
