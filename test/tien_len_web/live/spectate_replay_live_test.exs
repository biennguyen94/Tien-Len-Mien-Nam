defmodule TienLenWeb.SpectateReplayLiveTest do
  @moduledoc "Spectator page and replay page (V1–V6)."
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Card, Lobby, RoomServer, Stats}

  defp deal(map),
    do: {:hands, Map.new(map, fn {s, c} -> {s, Card.parse_many!(c)} end)}

  defp open_room!(opts) do
    {:ok, id} = Lobby.open_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  test "a spectator sees the public table only, live; players see the count" do
    id = open_room!(deals: [deal(%{0 => "3S 9H 2D", 1 => "4S 9C 5D"})])
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, _binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    an |> element("#start") |> render_click()

    {:ok, watch, html} = live(login_conn("Cuong"), ~p"/phong/#{id}/xem")
    assert has_element?(watch, "#spectators", "1 người xem")
    assert has_element?(an, "#spectator-count", "1")
    refute html =~ "/images/cards/9H.svg"
    refute render(watch) =~ "/images/cards/9C.svg"
    refute has_element?(watch, "#room-chat")

    an |> element("#card-3S") |> render_click()
    an |> element("#play") |> render_click()
    assert has_element?(watch, "#centre img[alt='3♠']")
    refute render(watch) =~ "/images/cards/9H.svg"
  end

  test "a seated player opening the watch page goes to the table; the lobby has Xem" do
    id = open_room!([])
    {:ok, lobby, _} = live(login_conn("Cuong"), ~p"/")
    {:ok, _an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    assert has_element?(lobby, "#watch-#{id}")
    assert {:error, {:live_redirect, %{to: to}}} = live(login_conn("An"), ~p"/phong/#{id}/xem")
    assert to == "/phong/#{id}"
  end

  test "replay page: steps through the game with every hand; history links to it" do
    _ = login_conn("An")
    _ = login_conn("Binh")

    replay = %{
      "seats" => [%{"seat" => 0, "name" => "An"}, %{"seat" => 1, "name" => "Binh"}],
      "hands" => %{"0" => ~w(3S 9H), "1" => ~w(4S 9C)},
      "events" => [
        %{"t" => "played", "s" => 0, "c" => ["3S"], "k" => "single"},
        %{"t" => "played", "s" => 1, "c" => ["4S"], "k" => "single"},
        %{"t" => "passed", "s" => 0},
        %{"t" => "round_ended", "s" => 1},
        %{"t" => "played", "s" => 1, "c" => ["9C"], "k" => "single"},
        %{"t" => "finished", "s" => 1, "p" => 1},
        %{"t" => "game_over", "r" => [[1], [0]]}
      ]
    }

    {:ok, game} =
      Stats.record(%{
        room_id: "r",
        ref: "room:r:game:1",
        player_count: 2,
        instant_win: false,
        replay: replay,
        players: [
          %{user_id: test_user("Binh").id, seat: 1, place: 1, won: true, removed: false},
          %{user_id: test_user("An").id, seat: 0, place: 2, won: false, removed: false}
        ]
      })

    conn = login_conn("An")
    {:ok, history, _} = live(conn, ~p"/lich-su")
    assert has_element?(history, "#replay-#{game.id}")

    {:ok, view, _} = live(conn, ~p"/van/#{game.id}")
    assert has_element?(view, "#replay-event", "Chia bài")
    assert has_element?(view, "#replay-seat-1 img[alt='9♣']")
    view |> element("#replay-next") |> render_click()
    assert has_element?(view, "#replay-event", "An đánh Lá lẻ: 3♠")
    assert has_element?(view, "#replay-centre img[alt='3♠']")
    refute has_element?(view, "#replay-seat-0 img[alt='3♠']")
    view |> element("#replay-last") |> render_click()
    assert has_element?(view, "#replay-event", "Kết thúc ván")
    assert has_element?(view, "#replay-seat-1", "hết bài")
    view |> element("#replay-first") |> render_click()
    assert has_element?(view, "#replay-step", "Bước 0/7")

    _ = login_conn("Stranger")

    assert {:error, {:live_redirect, %{to: "/lich-su"}}} =
             live(login_conn("Stranger"), ~p"/van/#{game.id}")
  end
end
