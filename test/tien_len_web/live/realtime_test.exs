defmodule TienLenWeb.RealtimeTest do
  @moduledoc """
  Phase 9: several players' LiveViews on one room.

  After every change, each player's rendered HTML is checked against the server's actual
  hands: it must never contain a card that sits in another player's hand or among the undealt
  cards (RULES T14). The game is driven through `RoomServer` one command at a time (the timers
  are long), so the snapshot of the hands and the rendered HTML describe the same state.
  """

  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import TienLenWeb.CardComponents, only: [card_src: 1]

  alias TienLen.{Card, Game, Lobby, RoomServer}

  @names ~w(An Binh Chi Dung)

  defp player_conn(name), do: login_conn(name)

  defp open_room!(opts) do
    {:ok, id} = Lobby.open_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  defp cards(codes), do: Card.parse_many!(codes)
  defp deal(map), do: {:hands, Map.new(map, fn {seat, codes} -> {seat, cards(codes)} end)}

  defp room_state(id), do: :sys.get_state(RoomServer.whereis(id)).room

  # Every card src/alt of `hidden` must be absent from `html`.
  defp assert_no_leak(html, hidden, who) do
    leaked =
      Enum.filter(hidden, &(html =~ card_src(&1) or html =~ ~s(id="card-#{Card.to_code(&1)}")))

    assert leaked == [],
           "#{who} sees hidden cards: #{Enum.map_join(leaked, " ", &Card.to_code/1)}"
  end

  defp check_all_views(id, views) do
    room = room_state(id)
    game = room.game

    for {seat, lv} <- views do
      html = render(lv)
      others = game.seats -- [seat]
      revealed = Enum.flat_map(game.instant_winners, fn {s, _} -> game.hands[s] end)

      hidden =
        (Enum.flat_map(others, &game.hands[&1]) ++ game.undealt ++ game.discarded) -- revealed

      assert_no_leak(html, hidden, "seat #{seat}")

      # own hand is shown in full while playing
      if room.status == :playing and seat in Game.active_seats(game) do
        for card <- game.hands[seat], do: assert(html =~ ~s(id="card-#{Card.to_code(card)}"))
      end
    end
  end

  # Current player plays their lowest legal single, else passes (leading always has a legal
  # single; a card-led opening needs the mandatory card, which is a legal single too).
  defp step(id) do
    room = room_state(id)
    game = room.game
    seat = game.current
    player = room.seats[seat].player_id

    single =
      Enum.find(game.hands[seat], fn card ->
        RoomServer.check(id, player, {:play, [card]}) == :ok
      end)

    if single,
      do: :ok = RoomServer.play(id, player, [single]),
      else: :ok = RoomServer.pass(id, player)
  end

  defp play_to_the_end(id, views, steps \\ 0) do
    check_all_views(id, views)

    cond do
      room_state(id).status == :waiting ->
        steps

      steps > 500 ->
        flunk("game did not finish")

      true ->
        step(id)
        play_to_the_end(id, views, steps + 1)
    end
  end

  describe "no hidden card ever reaches another player's page" do
    for {n, seed} <- [{2, 11}, {3, 22}, {4, 33}, {4, 44}] do
      test "#{n} players, seed #{seed}: a whole game, checked after every command" do
        id = open_room!(deals: [unquote(seed)])

        views =
          for {name, seat} <- Enum.with_index(Enum.take(@names, unquote(n))) do
            {:ok, lv, _} = live(player_conn(name), ~p"/phong/#{id}")
            {seat, lv}
          end

        {0, host} = hd(views)
        host |> element("#start") |> render_click()

        steps = play_to_the_end(id, views)
        assert room_state(id).games_played == 1
        assert has_element?(host, "#ranking")
        assert steps >= 0
      end
    end
  end

  describe "connections seen by others (T15)" do
    test "closing a tab shows 'mất kết nối' to others; reopening restores the seat and hand" do
      id = open_room!(deals: [deal(%{0 => "3S 9H", 1 => "4S 9C"})])
      {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      an |> element("#start") |> render_click()

      # LiveViewTest links the LiveView to the test: trap the exit of the "closed tab"
      Process.flag(:trap_exit, true)
      Process.exit(binh.pid, :kill)
      assert eventually(fn -> has_element?(an, "#seat-1", "mất kết nối") end)

      {:ok, binh2, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      assert eventually(fn -> not has_element?(an, "#seat-1", "mất kết nối") end)
      assert has_element?(binh2, "#card-4S")
      assert has_element?(binh2, "#card-9C")
    end

    test "two tabs of the same player share the seat; closing one keeps them connected" do
      id = open_room!(deals: [deal(%{0 => "3S 9H", 1 => "4S 9C"})])
      {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, tab1, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      {:ok, tab2, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      an |> element("#start") |> render_click()

      assert has_element?(tab1, "#card-4S") and has_element?(tab2, "#card-4S")
      Process.flag(:trap_exit, true)
      Process.exit(tab1.pid, :kill)
      Process.sleep(50)
      refute has_element?(an, "#seat-1", "mất kết nối")
    end
  end

  describe "out-of-turn chop through the UI (T10)" do
    test "the current player plays a four-pair normally: no chop button for them" do
      id =
        open_room!(
          deals: [
            deal(%{
              0 => "3S 9H",
              1 => "2H 10C",
              2 => "4S 4C 5S 5C 6S 6C 7S 7C KD"
            })
          ]
        )

      {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      {:ok, chi, _} = live(player_conn("Chi"), ~p"/phong/#{id}")
      an |> element("#start") |> render_click()

      an |> element("#card-3S") |> render_click()
      an |> element("#play") |> render_click()
      binh |> element("#card-2H") |> render_click()
      binh |> element("#play") |> render_click()

      # Chi is the current player: a four-pair is a normal play for them, not an out-of-turn chop
      for code <- ~w(4S 4C 5S 5C 6S 6C 7S 7C),
          do: chi |> element("#card-#{code}") |> render_click()

      refute has_element?(chi, "#chop")
      refute has_element?(chi, "#play[disabled]")
    end

    test "the chop button appears for a player whose turn it is not" do
      id =
        open_room!(
          deals: [
            deal(%{
              0 => "3S 9H",
              1 => "4S 4C 5S 5C 6S 6C 7S 7C KD",
              2 => "2H 10C"
            })
          ]
        )

      {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      {:ok, chi, _} = live(player_conn("Chi"), ~p"/phong/#{id}")
      an |> element("#start") |> render_click()

      an |> element("#card-3S") |> render_click()
      an |> element("#play") |> render_click()
      binh |> element("#pass") |> render_click()
      chi |> element("#card-2H") |> render_click()
      chi |> element("#play") |> render_click()

      # An is current; Bình (already passed) chops out of turn
      for code <- ~w(4S 4C 5S 5C 6S 6C 7S 7C),
          do: binh |> element("#card-#{code}") |> render_click()

      assert has_element?(binh, "#chop")
      binh |> element("#chop") |> render_click()

      for lv <- [an, binh, chi] do
        assert has_element?(lv, "#centre", "Bốn đôi thông")
        assert has_element?(lv, "#chop-context")
      end

      # play continues after the chopper: Chi (seat 2)
      assert has_element?(chi, "#pass")
      refute has_element?(an, "#pass")
    end
  end

  describe "server actions on timeout (T16)" do
    test "an auto-played card appears on the other players' tables" do
      id = open_room!(turn_timeout: 40, deals: [deal(%{0 => "3S 9H", 1 => "4S 9C"})])
      {:ok, an, _} = live(player_conn("An"), ~p"/phong/#{id}")
      {:ok, binh, _} = live(player_conn("Binh"), ~p"/phong/#{id}")
      an |> element("#start") |> render_click()

      assert has_element?(binh, "#timer-0")
      assert eventually(fn -> has_element?(binh, "#centre img[alt='3♠']") end)
    end
  end

  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end
end
