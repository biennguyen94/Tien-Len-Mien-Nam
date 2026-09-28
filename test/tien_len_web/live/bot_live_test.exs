defmodule TienLenWeb.BotLiveTest do
  @moduledoc "Bots, hints and the phone layout on the table page (B1, H1, M1, M2)."
  use TienLenWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias TienLen.{Card, Lobby, RoomServer}

  defp open_room!(opts) do
    {:ok, id} = Lobby.open_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  defp deal(map),
    do: {:hands, Map.new(map, fn {seat, codes} -> {seat, Card.parse_many!(codes)} end)}

  test "the host adds and removes bots; a game against a bot starts" do
    # a fixed deal: a random one could be an instant win that ends the game at once
    hands = %{0 => "3S 3C 5D 9H KH 2S", 1 => "4S 6D 8C 10C JD QS"}
    id = open_room!(deals: [deal(hands)], bot_delay: 60_000)
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    assert has_element?(an, "#start[disabled]")

    an |> element("#add-bot-normal") |> render_click()
    assert has_element?(an, "#seat-1", "Máy 1 (thường)")
    assert has_element?(an, "#seat-1 [title='Máy chơi']")
    assert render(an) =~ "không tính coin"
    refute has_element?(an, "#start[disabled]")

    an |> element("#remove-bot-1") |> render_click()
    refute has_element?(an, "#seat-1", "Máy")

    an |> element("#add-bot-easy") |> render_click()
    an |> element("#start") |> render_click()
    assert has_element?(an, "#hand")
  end

  test "no bot buttons in a room with a stake" do
    id = open_room!(stake: 100)
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    refute has_element?(an, "#add-bot-easy")
    assert render(an) =~ "Chỉ thêm máy được ở phòng chơi vui"
  end

  test "guests cannot add bots (the button is not there and the event is refused)" do
    id = open_room!([])
    {:ok, _an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    refute has_element?(binh, "#add-bot-easy")
    render_click(binh, "add_bot", %{"level" => "easy"})
    assert render(binh) =~ "Chỉ chủ phòng"
  end

  test "hint selects a legal play, cycling; sort by suit changes the order" do
    hands = %{0 => "3S 3C 5D 9H KH 2S", 1 => "4S 6D 8C 10C JD QS"}
    id = open_room!(deals: [deal(hands)], bot_delay: 60_000)
    {:ok, an, _} = live(login_conn("An"), ~p"/phong/#{id}")
    {:ok, _binh, _} = live(login_conn("Binh"), ~p"/phong/#{id}")
    an |> element("#start") |> render_click()

    an |> element("#hint") |> render_click()
    assert has_element?(an, "#card-3S[aria-pressed=true]")
    refute has_element?(an, "#play[disabled]")
    an |> element("#hint") |> render_click()
    assert has_element?(an, "#card-3S[aria-pressed=true]")
    assert has_element?(an, "#play", "Đánh")

    ids = fn ->
      Regex.scan(~r/id="card-([0-9JQKA]+[SCDH])"/, render(an), capture: :all_but_first)
      |> List.flatten()
    end

    assert ids.() == ~w(3S 3C 5D 9H KH 2S)
    an |> element("#sort") |> render_click()
    assert ids.() == ~w(3S 2S 3C 5D 9H KH)
  end
end
