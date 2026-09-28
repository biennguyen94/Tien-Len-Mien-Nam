defmodule TienLenWeb.SocialFeaturesLiveTest do
  @moduledoc "Batch 11 in the browser: profile, avatar, friends, missions, weekly tabs, reactions."
  use TienLenWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TienLen.{Friends, Lobby, RoomServer, Stats}

  defp record!(players) do
    {:ok, _} =
      Stats.record(%{
        room_id: "t",
        ref: "room:t:game:#{System.unique_integer([:positive])}",
        player_count: length(players),
        instant_win: false,
        players:
          Enum.with_index(players, fn p, seat ->
            Map.merge(%{seat: seat, won: p.place == 1, removed: false}, p)
          end)
      })
  end

  test "own profile: numbers and avatar picker; the header shows the avatar" do
    conn = login_conn("An")
    an = test_user("An")
    _ = login_conn("Binh")

    record!([
      %{user_id: an.id, place: 1, chops: 1, coins: 200},
      %{user_id: test_user("Binh").id, place: 2}
    ])

    {:ok, view, _} = live(conn, ~p"/nguoi-choi/#{an.username}")
    assert has_element?(view, "#stat-wins", "1")
    assert has_element?(view, "#stat-chops", "1")
    assert has_element?(view, "#stat-coins", "+200")
    view |> element("#avatar-picker button", "🐼") |> render_click()
    assert has_element?(view, "#profile-avatar", "🐼")
    assert has_element?(view, "#current-user", "🐼")
    refute has_element?(view, "#friend-actions")
  end

  test "friend request from a profile, badge, accept on the friends page" do
    _ = login_conn("Binh")
    binh = test_user("Binh")
    {:ok, binh_lobby, _} = live(login_conn("Binh"), ~p"/")
    {:ok, profile, _} = live(login_conn("An"), ~p"/nguoi-choi/#{binh.username}")

    profile |> element("#friend-request") |> render_click()
    assert has_element?(profile, "#friend-cancel")
    assert has_element?(binh_lobby, "#friend-requests", "1")

    {:ok, friends, _} = live(login_conn("Binh"), ~p"/ban-be")
    friends |> element("#incoming-#{test_user("An").id} button", "Đồng ý") |> render_click()
    assert has_element?(friends, "#friend-#{test_user("An").id}")
    assert has_element?(profile, "#friend-remove")
    refute has_element?(binh_lobby, "#friend-requests")
  end

  test "search on the friends page and send a request" do
    _ = login_conn("Zed Tran")
    {:ok, view, _} = live(login_conn("An"), ~p"/ban-be")
    view |> form("#search-form", %{"q" => "zed"}) |> render_change()
    zed = test_user("Zed Tran")
    view |> element("#result-#{zed.id} button", "Kết bạn") |> render_click()
    assert has_element?(view, "#outgoing-#{zed.id}")
    assert Friends.relation(test_user("An").id, zed.id) == :outgoing
  end

  test "missions card: progress and claim" do
    conn = login_conn("An")
    _ = login_conn("Binh")
    {:ok, lobby, _} = live(conn, ~p"/")
    assert has_element?(lobby, "#mission-chop", "0/1")

    record!([
      %{user_id: test_user("An").id, place: 1, chops: 1},
      %{user_id: test_user("Binh").id, place: 2}
    ])

    # the lobby follows {:stats_updated}
    assert has_element?(lobby, "#mission-chop", "1/1")
    lobby |> element("#claim-chop") |> render_click()
    assert has_element?(lobby, "#mission-chop", "Đã nhận")
    assert has_element?(lobby, "#my-coins", "1.200")
  end

  test "weekly tabs on the leaderboard" do
    conn = login_conn("An")
    _ = login_conn("Binh")

    record!([
      %{user_id: test_user("An").id, place: 1},
      %{user_id: test_user("Binh").id, place: 2}
    ])

    {:ok, view, _} = live(conn, ~p"/bang-xep-hang?tab=tuan")
    assert has_element?(view, "#season", "Thưởng cuối tuần")
    assert has_element?(view, "#row-#{test_user("An").id}")
    {:ok, view, _} = live(conn, ~p"/bang-xep-hang?tab=tuan-truoc")
    refute has_element?(view, "#row-#{test_user("An").id}")
  end

  test "emoji reactions show on the seat for everyone at the table" do
    {:ok, id} = Lobby.open_room([])
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")

    an |> element("#reactions button", "🔥") |> render_click()
    assert has_element?(binh, "#reaction-0", "🔥")
    assert RoomServer.react(id, :stranger, "🔥") == {:error, :not_in_room}
    assert RoomServer.react(id, test_user("An").id, "💩") == {:error, :unknown_command}
  end
end
