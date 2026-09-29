defmodule TienLenWeb.FunExtras2LiveTest do
  @moduledoc "Batch 15 in the browser: sounds, blowing, bot speech, charms, shame titles, events."
  use TienLenWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TienLen.{Admin, Card, Lobby, RoomServer, Settings, Shame, Stats}

  defp deal(map), do: {:hands, Map.new(map, fn {s, codes} -> {s, Card.parse_many!(codes)} end)}

  defp room!(opts \\ []) do
    {:ok, id} = Lobby.open_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  setup do
    on_exit(fn -> :persistent_term.erase({Settings, "season_event"}) end)
    :ok
  end

  test "sound button; a 2 pushes the pig sound to both players" do
    id = room!(deals: [deal(%{0 => "3D 2H 4S", 1 => "5D 6D"})])
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    assert has_element?(an, "#sound-toggle[phx-hook='Sfx']")

    an |> element("#start") |> render_click()
    an |> element("#card-3D") |> render_click()
    an |> element("#play") |> render_click()
    binh |> element("#pass") |> render_click()
    an |> element("#card-2H") |> render_click()
    an |> element("#play") |> render_click()
    assert_push_event(binh, "sfx", %{kinds: ["pig"]})
  end

  test "blowing on the cards shows a puff on my seat for everyone" do
    id = room!()
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")

    an |> element("#blow") |> render_click()
    assert has_element?(binh, "[id^='puff-0-']")
    assert an |> element("#blow") |> render_click() =~ "3 giây"
  end

  test "bots talk with a speech bubble" do
    fixed = %{roll: fn -> 0.0 end, pick: &hd/1}
    id = room!(deals: [deal(%{0 => "3D 4D", 1 => "5D 6D"})], talk_rng: fixed, bot_delay: 60_000)
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")

    an |> element("#add-bot-easy") |> render_click()
    an |> element("#start") |> render_click()
    assert has_element?(an, "#speech-1", "Bài xấu quá trời ơi!")
    assert has_element?(an, "#room-chat", "Bà Tám (dễ)")
  end

  test "a worn charm and a shame title show at the table and on the profile" do
    conn = login_conn("An")
    an = test_user("An")
    _ = login_conn("Binh")

    {:ok, _} =
      Stats.record(%{
        room_id: "t",
        ref: "room:t:game:#{System.unique_integer([:positive])}",
        player_count: 2,
        instant_win: false,
        players: [
          %{user_id: test_user("Binh").id, seat: 0, place: 1, won: true, removed: false},
          %{user_id: an.id, seat: 1, place: 2, won: false, removed: false, thoi: 2}
        ]
      })

    Shame.clear_cache()

    {:ok, shop, _} = live(conn, ~p"/cua-hang")
    shop |> element("#item-toi button") |> render_click()
    assert has_element?(shop, "#item-toi", "Đang dùng")

    id = room!()
    {:ok, table, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    assert has_element?(binh, "#charm-0", "🧄")
    assert has_element?(binh, "#titles-0 [title='Vua Thối Heo']")
    refute has_element?(table, "#titles-1")

    {:ok, profile, _} = live(login_conn("Binh"), ~p"/nguoi-choi/#{an.username}")
    assert has_element?(profile, "#profile-charm", "🧄")
    assert has_element?(profile, "#profile-titles", "Vua Thối Heo")

    {:ok, wall, _} = live(login_conn("Binh"), ~p"/tuong-xau-ho")
    assert has_element?(wall, "#title-thoi", "An")
    assert has_element?(wall, "#title-thoi", "2 heo")
    assert has_element?(wall, "#title-cong", "Chưa ai")

    shop |> element("#remove-charm") |> render_click()
    refute has_element?(shop, "#item-toi", "Đang dùng")
  end

  test "the admin picks an event; the banner shows on the next page" do
    conn = login_conn("Admin")
    {:ok, _} = Admin.promote(test_user("Admin").username)
    {:ok, page, _} = live(conn, ~p"/quan-tri/cai-dat")

    page |> form("#event-form", %{event: "trung_thu"}) |> render_submit()
    assert Settings.event() == "trung_thu"

    {:ok, lobby, _} = live(login_conn("Admin"), ~p"/")
    assert has_element?(lobby, "#event-banner", "Trung thu")

    page |> form("#event-form", %{event: "none"}) |> render_submit()
    {:ok, lobby, _} = live(login_conn("Admin"), ~p"/")
    refute has_element?(lobby, "#event-banner")
  end
end
