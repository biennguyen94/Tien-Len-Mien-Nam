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
    for id <- ~w(friends-link my-coins current-user logout), do: assert(has_element?(view, "##{id}"))
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
end
