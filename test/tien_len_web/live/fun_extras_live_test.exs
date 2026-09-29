defmodule TienLenWeb.FunExtrasLiveTest do
  @moduledoc "Batch 14 in the browser: throws, commentator ticker, runaway slipper, shop."
  use TienLenWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TienLen.{Card, Economy, Lobby, RoomServer}

  defp deal(map), do: {:hands, Map.new(map, fn {s, codes} -> {s, Card.parse_many!(codes)} end)}

  defp room!(opts \\ []) do
    {:ok, id} = Lobby.open_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  test "click another seat, throw a tomato: both players see the mark, the flight is pushed" do
    id = room!()
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")

    # my own seat is not a target
    refute has_element?(an, "#seat-0[phx-click]")

    an |> element("#seat-1") |> render_click()
    assert has_element?(an, "#throw-menu-1")
    an |> element("#throw-1-tomato") |> render_click()
    refute has_element?(an, "#throw-menu-1")

    assert_push_event(an, "throw", %{from: "seat-0", to: "seat-1", emoji: "🍅"})
    assert has_element?(binh, "[id^='mark-1-']", "🍅💦")
    assert has_element?(an, "[id^='mark-1-']")

    # 3 s cooldown (TH3)
    an |> element("#seat-1") |> render_click()
    assert an |> element("#throw-1-rose") |> render_click() =~ "3 giây"
  end

  test "the commentator's line shows under the table and in the chat, also for spectators" do
    id = room!(deals: [deal(%{0 => "3D 4D", 1 => "5D 2S"})])
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    {:ok, watcher, _} = live(login_conn("Chi"), ~p"/phong/#{id}/xem")

    an |> element("#start") |> render_click()
    an |> element("#card-3D") |> render_click()
    an |> element("#play") |> render_click()

    assert has_element?(binh, "#commentary", "An")
    assert has_element?(binh, "#room-chat", "Bình luận viên")
    assert has_element?(watcher, "#commentary", "An")
  end

  test "a player who leaves during a game: a slipper drops on the empty seat" do
    id = room!(deals: [deal(%{0 => "3D 4D", 1 => "5D 6D", 2 => "7D 8D"})])
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, _binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    {:ok, chi, _} = live(login_conn("Chi"), ~p"/phong/#{id}")

    an |> element("#start") |> render_click()
    chi |> element("#leave") |> render_click()

    assert has_element?(an, "#slipper-2", "🩴")
    assert has_element?(an, "#room-chat", "Chi")
  end

  test "shop: buy and equip; the card back is seen by others, the theme by me" do
    conn = login_conn("An")
    an_user = test_user("An")
    {:ok, shop, _} = live(conn, ~p"/cua-hang")

    assert has_element?(shop, "#shop-link")
    assert has_element?(shop, "#item-classic", "Đang dùng")
    shop |> element("#item-lixi button") |> render_click()
    assert has_element?(shop, "#item-lixi", "Đang dùng")
    shop |> element("#item-quan_coc button") |> render_click()
    assert has_element?(shop, "#item-quan_coc", "Đang dùng")
    assert Economy.balance(an_user.id) == 0

    # not enough coins left for the most expensive table
    assert has_element?(shop, "#item-song_bai button[disabled]")

    id = room!(deals: [deal(%{0 => "3D 4D", 1 => "5D 6D"})])
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    assert has_element?(an, "#centre.felt-quan_coc")
    assert has_element?(binh, "#centre.felt-felt")

    an |> element("#start") |> render_click()
    assert has_element?(binh, "#seat-0 .back-lixi")
    refute has_element?(an, "#seat-1 .back-lixi")

    # switching back is free
    shop |> element("#item-classic button") |> render_click()
    assert has_element?(shop, "#item-classic", "Đang dùng")
    assert Economy.balance(an_user.id) == 0
  end
end
