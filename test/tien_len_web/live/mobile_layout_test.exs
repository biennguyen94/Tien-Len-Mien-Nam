defmodule TienLenWeb.MobileLayoutTest do
  @moduledoc """
  M3: the phone header (☰ menu). The real widths (360/390/412 px, no horizontal scroll) are
  measured with tools/mobile-audit (headless Chromium); this only checks the markup.
  """
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "logged in: coin badge and ☰ for phones; the nav starts hidden on phones, shown from sm" do
    {:ok, view, _} = live(login_conn("An"), ~p"/")
    assert has_element?(view, "#my-coins-mobile.sm\\:hidden", "1.000")
    assert has_element?(view, "#nav-menu-toggle[aria-controls=site-nav][aria-expanded=false]")
    assert has_element?(view, "#site-nav.hidden.sm\\:flex")
    # the desktop links are still there (one set of ids)
    for id <- ~w(friends-link my-coins current-user logout),
        do: assert(has_element?(view, "##{id}"))
  end

  test "logged out: no ☰, the nav (theme toggle) is always visible" do
    {:ok, view, _} = live(sandbox_conn(), ~p"/")
    refute has_element?(view, "#nav-menu-toggle")
    assert has_element?(view, "#site-nav.flex")
    refute has_element?(view, "#site-nav.hidden")
  end

  test "the table lifts the message button above its action bar on phones" do
    {:ok, id} = TienLen.Lobby.open_room([])
    on_exit(fn -> if pid = TienLen.RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    {:ok, table, _} = live(login_conn("An"), ~p"/phong/#{id}")
    assert has_element?(table, "#social.bottom-24")
    {:ok, lobby, _} = live(login_conn("An"), ~p"/")
    assert has_element?(lobby, "#social.bottom-3")
  end

  test "M4: every card slot is relative (a lifted card never covers its neighbour); the ring is on the image" do
    hands = %{0 => "3S 4S 5S 6S", 1 => "3C 4C 5C 6C"}
    deal = {:hands, Map.new(hands, fn {s, c} -> {s, TienLen.Card.parse_many!(c)} end)}
    {:ok, id} = TienLen.Lobby.open_room(deals: [deal])
    on_exit(fn -> if pid = TienLen.RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, _binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    an |> element("#start") |> render_click()
    an |> element("#card-4S") |> render_click()

    for code <- ~w(3S 4S 5S 6S), do: assert(has_element?(an, "#card-#{code}.relative"))
    assert has_element?(an, "#card-4S.-translate-y-3[aria-pressed=true] img.ring-2")
    refute has_element?(an, "#card-5S.-translate-y-3")
    refute has_element?(an, "#hand [class*=z-]")
    refute has_element?(an, "#hand [class*=scale]")
  end
end
