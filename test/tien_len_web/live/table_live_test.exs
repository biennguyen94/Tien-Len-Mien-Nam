defmodule TienLenWeb.TableLiveTest do
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Card, Lobby, RoomServer}
  alias TienLenWeb.Text

  defp cards(codes), do: Card.parse_many!(codes)

  # A browser session with a player id and a name.
  defp player_conn(name), do: login_conn(name)

  defp open_room!(opts) do
    {:ok, id} = Lobby.open_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  defp deal(map), do: {:hands, Map.new(map, fn {seat, codes} -> {seat, cards(codes)} end)}

  # Host "An" in seat 0, guest "Bình" in seat 1, game started with a fixed deal.
  defp two_player_game(hands) do
    id = open_room!(deals: [deal(hands)])
    {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
    an |> element("#start") |> render_click()
    %{id: id, an: an, binh: binh}
  end

  describe "joining" do
    test "the first player is host and sees the start button (disabled alone)", %{conn: _} do
      id = open_room!([])
      {:ok, view, html} = live(player_conn("An"), ~p"/phong/#{id}")
      assert html =~ "An"
      assert has_element?(view, "#seat-0", "👑")
      assert has_element?(view, "#start[disabled]")
    end

    test "without logging in the player is sent to the lobby (A3)" do
      id = open_room!([])
      assert {:error, {:redirect, %{to: to}}} = live(sandbox_conn(), ~p"/phong/#{id}")
      assert to == "/?" <> URI.encode_query(next: "/phong/#{id}")
    end

    test "unknown room: back to the lobby with a message" do
      conn = player_conn("An")
      {:ok, _lobby, html} = conn |> live(~p"/phong/khong-co") |> follow_redirect(conn, "/")
      assert html =~ Text.reason(:room_not_found)
    end

    test "no spectators: a fifth player and late joiners are refused (R6, #17)" do
      id = open_room!(deals: [deal(%{0 => "3S 9H", 1 => "4S 9C"})])
      for name <- ~w(A B C D), do: {:ok, _, _} = live(player_conn(name), ~p"/phong/#{id}")

      conn = player_conn("E")
      {:ok, _lobby, html} = conn |> live(~p"/phong/#{id}") |> follow_redirect(conn, "/")
      assert html =~ Text.reason(:room_full)
    end
  end

  describe "playing" do
    test "each player sees only their own hand; plays update both tables" do
      %{an: an, binh: binh} = two_player_game(%{0 => "3S 5D 9H", 1 => "4S 6C 9C"})

      # An sees own cards, not Bình's
      assert has_element?(an, "#card-3S")
      refute has_element?(an, "#card-4S")
      assert has_element?(binh, "#card-4S")
      refute has_element?(binh, "#card-3S")
      refute render(binh) =~ "/images/cards/3S.svg"

      # both see card counts, An must include 3♠
      assert has_element?(an, "#must-include", "3♠")
      refute has_element?(binh, "#must-include")

      # nothing selected: the button explains why it is disabled
      assert has_element?(an, "#play[disabled]", Text.reason(:empty))

      # selecting 9H alone: must include 3♠
      an |> element("#card-9H") |> render_click()
      assert has_element?(an, "#play[disabled]", Text.reason(:must_include_card))

      # select 3S instead and play
      an |> element("#card-9H") |> render_click()
      an |> element("#card-3S") |> render_click()
      refute has_element?(an, "#play[disabled]")
      an |> element("#play") |> render_click()

      assert has_element?(an, "#centre img[alt='3♠']")
      assert has_element?(binh, "#centre img[alt='3♠']")
      refute has_element?(an, "#card-3S")

      # Bình's turn: can pass, An cannot act
      assert has_element?(binh, "#pass")
      refute has_element?(an, "#pass")
      binh |> element("#pass") |> render_click()

      # round ended: An leads again, cannot pass
      assert has_element?(an, "#centre", "Bàn trống")
      refute has_element?(an, "#pass")
    end

    test "a game played to the end shows the ranking and a new-game button for the host" do
      %{an: an, binh: binh} = two_player_game(%{0 => "3S", 1 => "4S 9C"})
      an |> element("#card-3S") |> render_click()
      an |> element("#play") |> render_click()

      assert has_element?(an, "#results")
      assert has_element?(an, "#ranking", "Nhất")
      assert has_element?(binh, "#ranking", "An")
      assert has_element?(an, "#start", "Ván mới")
      refute has_element?(binh, "#start")
    end

    test "an instant win is shown with the winner's hand revealed" do
      six_pairs = "3C 3D 5S 5D 7S 7C 9S 9C JC JD 2S 2D KH"

      %{an: an, binh: binh} =
        two_player_game(%{0 => "4S 4C 6S 8C 10S QS AS 5H 7H 9D JH KS 2H", 1 => six_pairs})

      assert has_element?(an, "#instant-1", Text.instant(:six_pairs))
      assert has_element?(an, "#instant-1 img[alt='K♥']")
      # the loser's hand is not revealed to the winner
      refute has_element?(binh, "#instant-0")
    end

    test "leaving returns to the lobby and frees the seat" do
      id = open_room!([])
      {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(player_conn("Binh"), ~p"/phong/#{id}")

      binh |> element("#leave") |> render_click()
      assert_redirect(binh, "/")
      assert has_element?(an, "#seat-1", "Trống")
    end
  end

  describe "texts" do
    test "every domain error reason has a Vietnamese message" do
      reasons = [
        :empty,
        :duplicate_cards,
        :invalid_combination,
        :does_not_match,
        :too_low,
        :cannot_chop,
        :must_include_card,
        :cannot_pass_on_lead,
        :not_four_pair,
        :no_chop_target,
        :game_over,
        :not_in_game,
        :not_active,
        :not_your_turn,
        :not_your_cards,
        :not_host,
        :not_enough_players,
        :game_in_progress,
        :room_full,
        :room_not_found,
        :not_in_room,
        :invalid_name,
        :too_many_rooms,
        :unknown_request,
        :not_enough_coins,
        :invalid_stake,
        :already_claimed,
        :not_eligible,
        :not_found,
        :forbidden,
        :already_admin,
        :not_admin,
        :cannot_demote_self,
        :last_admin,
        :cannot_lock_self,
        :cannot_lock_admin,
        :already_locked,
        :not_locked,
        :insufficient_coins,
        :invalid_amount,
        :reason_required,
        :kicked,
        :announcement_too_long,
        :wrong_password,
        :throttled,
        :no_game,
        :unknown_command,
        :invalid_message,
        :muted,
        :chat_too_fast,
        :not_online,
        :invites_off,
        :invite_pending,
        :target_busy,
        :invite_too_fast,
        :invite_expired,
        :not_enough_coins_to_join,
        :cannot_mute_self,
        :not_muted,
        :invalid_duration
      ]

      assert Enum.sort(reasons) == Enum.sort(Text.known_reasons())
      for r <- reasons, do: refute(Text.reason(r) == "Có lỗi xảy ra")
    end
  end
end
