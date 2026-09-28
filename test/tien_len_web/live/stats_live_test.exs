defmodule TienLenWeb.StatsLiveTest do
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.Stats

  defp record(placed, opts \\ []) do
    {:ok, _} =
      Stats.record(%{
        room_id: "r",
        player_count: length(placed),
        instant_win: Keyword.get(opts, :instant, false),
        players:
          for {{user, place}, seat} <- Enum.with_index(placed) do
            %{user_id: user.id, seat: seat, place: place, won: place == 1, removed: false}
          end
      })
  end

  test "leaderboard and history require login (Y8)" do
    assert {:error, {:redirect, %{to: "/"}}} = live(sandbox_conn(), ~p"/bang-xep-hang")
    assert {:error, {:redirect, %{to: "/"}}} = live(sandbox_conn(), ~p"/lich-su")
  end

  test "the leaderboard lists wins, games and rate, highlights me, and updates live" do
    conn = login_conn("An")
    _ = login_conn("Binh")
    an = test_user("An")
    binh = test_user("Binh")

    {:ok, view, _} = live(conn, ~p"/bang-xep-hang")
    assert has_element?(view, "#my-standing", "chưa chơi xong ván nào")

    record([{an, 1}, {binh, 2}])
    record([{an, 2}, {binh, 1}])
    record([{an, 1}, {binh, 2}])

    # updated through PubSub, no reload
    assert has_element?(view, "#row-#{an.id}", "An")
    assert render(view) =~ ~r/id="row-#{an.id}"[^>]*font-bold/
    html = view |> element("#row-#{an.id}") |> render()
    assert html =~ ~r/>\s*2\s*</ and html =~ ~r/>\s*3\s*</ and html =~ "67%"
    assert has_element?(view, "#my-standing", "hạng")
  end

  test "history shows my recent games with places and instant wins" do
    conn = login_conn("An")
    _ = login_conn("Binh")
    _ = login_conn("Chi")
    [an, binh, chi] = Enum.map(~w(An Binh Chi), &test_user/1)

    {:ok, view, _} = live(conn, ~p"/lich-su")
    assert has_element?(view, "#no-games")

    record([{an, 3}, {binh, 1}, {chi, 2}])
    record([{an, 1}, {binh, 2}, {chi, 2}], instant: true)

    assert has_element?(view, "#history li", "tới trắng")
    html = render(view)
    assert html =~ "Bét: An"
    assert html =~ "Nhất: Binh"
    assert html =~ "Thua (tới trắng)"
  end

  test "the header links to the leaderboard and history" do
    {:ok, view, _} = live(login_conn("An"), ~p"/")
    assert has_element?(view, "a[href='/bang-xep-hang']")
    assert has_element?(view, "a[href='/lich-su']")
  end
end
