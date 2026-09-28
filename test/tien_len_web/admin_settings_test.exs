defmodule TienLenWeb.AdminSettingsTest do
  @moduledoc """
  Phase 22 (AD9, F7): settings are global (persistent_term), so this module is not async and
  restores the defaults afterwards.
  """
  use TienLenWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias TienLen.{Accounts, Admin, Economy, Settings}

  setup do
    on_exit(fn ->
      for key <- Map.keys(Settings.economy_defaults()) ++ ["announcement"] do
        :persistent_term.erase({Settings, key})
      end
    end)

    conn = login_conn("Admin")
    {:ok, _} = Admin.promote(test_user("Admin").username)
    %{conn: conn, admin: test_user("Admin")}
  end

  test "economy settings apply to new actions only; the old ledger is unchanged (F7)", %{
    admin: admin
  } do
    {:ok, before} =
      Accounts.register_user(%{display_name: "Old", username: "old_one", password: "12345678"})

    assert {:ok, %{"starting_coins" => 2_000, "daily_bonus" => 250}} =
             Admin.update_settings(admin.id, %{
               "starting_coins" => "2000",
               "daily_bonus" => " 250 "
             })

    assert Settings.int("starting_coins") == 2_000

    {:ok, fresh} =
      Accounts.register_user(%{display_name: "New", username: "new_one", password: "12345678"})

    assert fresh.coins == 2_000
    assert [%{amount: 2_000, reason: "registration"}] = Economy.history(fresh.id)
    assert [%{amount: 1_000}] = Economy.history(before.id)
    assert {:ok, 1_250} = Economy.claim_daily_bonus(before.id)

    assert %{action: "update_settings"} = hd(Admin.actions(1))
  end

  test "invalid values are refused; players cannot change settings", %{admin: admin} do
    assert Admin.update_settings(admin.id, %{"relief" => "-5"}) ==
             {:error, {:invalid_setting, "relief"}}

    assert Admin.update_settings(admin.id, %{"max_rooms" => "0"}) ==
             {:error, {:invalid_setting, "max_rooms"}}

    assert Admin.update_settings(admin.id, %{"daily_bonus" => "abc"}) ==
             {:error, {:invalid_setting, "daily_bonus"}}

    _ = login_conn("Player")

    assert Admin.update_settings(test_user("Player").id, %{"relief" => "1"}) ==
             {:error, :forbidden}

    assert Settings.int("relief") == 500
  end

  test "the announcement appears live on the lobby and is cleared with an empty text", %{
    admin: admin
  } do
    {:ok, lobby, _} = live(login_conn("Player"), ~p"/")
    refute has_element?(lobby, "#announcement")

    :ok = Admin.announce(admin.id, "Bảo trì lúc 22h")
    assert has_element?(lobby, "#announcement", "Bảo trì lúc 22h")

    :ok = Admin.announce(admin.id, "   ")
    refute has_element?(lobby, "#announcement")

    assert Admin.announce(admin.id, String.duplicate("a", 301)) ==
             {:error, :announcement_too_long}
  end

  test "the settings page saves values and the announcement", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/quan-tri/cai-dat")
    view |> form("#settings-form", %{"settings" => %{"relief" => "700"}}) |> render_submit()
    assert Settings.int("relief") == 700
    view |> form("#announce-form", %{"text" => "Xin chào"}) |> render_submit()
    assert has_element?(view, "#announcement", "Xin chào")
  end

  test "settings are cached and reloaded from the database" do
    :ok = Settings.put("relief", 900)
    :persistent_term.erase({Settings, "relief"})
    assert Settings.int("relief") == 500
    :ok = Settings.load()
    assert Settings.int("relief") == 900
  end
end
