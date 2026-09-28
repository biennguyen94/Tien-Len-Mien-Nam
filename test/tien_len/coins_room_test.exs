defmodule TienLen.CoinsRoomTest do
  @moduledoc "Phase 16: rooms settle coins through TienLen.Economy (T20–T25)."
  use TienLen.DataCase, async: true

  alias TienLen.{Accounts, Card, Economy, RoomServer}

  defp cards(codes), do: Card.parse_many!(codes)

  defp user!(name) do
    {:ok, u} =
      Accounts.register_user(%{
        display_name: name,
        username: String.downcase(name) <> "_#{System.unique_integer([:positive])}",
        password: "mat-khau-123"
      })

    u
  end

  defp room!(stake, hands) do
    deal = {:hands, Map.new(hands, fn {seat, codes} -> {seat, cards(codes)} end)}

    {:ok, id} =
      RoomServer.start_room(stake: stake, economy: Economy, recorder: nil, deals: [deal])

    pid = RoomServer.whereis(id)
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
    RoomServer.subscribe(id)
    id
  end

  test "stake 100, 3 players: chop chain, place and thối are settled; the total stays the same" do
    [a, b, c] = users = Enum.map(~w(An Binh Chi), &user!/1)

    id =
      room!(100, %{
        0 => "3D 2H",
        1 => "4S 4C 5S 5C 6S 6C 9D 2C",
        2 => "7S 7C 8S 8C 9S 9C 10D 2S"
      })

    for u <- users, do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
    :ok = RoomServer.start_game(id, a.id)

    play = fn u, codes -> assert :ok == RoomServer.play(id, u.id, cards(codes)) end
    pass = fn u -> assert :ok == RoomServer.pass(id, u.id) end

    play.(a, "3D")
    pass.(b)
    pass.(c)

    # a leads 2H and finishes; b chops, c chops b's chop; b passes → chain ends: b pays c 2 × 2 × 100
    play.(a, "2H")
    play.(b, "4S 4C 5S 5C 6S 6C")
    play.(c, "7S 7C 8S 8C 9S 9C")
    pass.(b)

    # c leads 10D (b passes), then 2S and finishes: b is Bét holding 9D 2C
    play.(c, "10D")
    pass.(b)
    play.(c, "2S")

    assert Economy.balance(a.id) == 1_100
    assert Economy.balance(b.id) == 400
    assert Economy.balance(c.id) == 1_500
    assert Enum.sum(Enum.map(users, &Economy.balance(&1.id))) == 3_000

    reasons = b.id |> Economy.history() |> Enum.map(&{&1.reason, &1.amount})
    assert {"chop", -400} in reasons
    assert {"place", -100} in reasons
    assert {"thoi", -100} in reasons

    view = RoomServer.view(id, a.id)
    assert view.coin_deltas == %{0 => 100, 1 => -600, 2 => 500}
    assert view.balances == %{0 => 1_100, 1 => 400, 2 => 1_500}
    assert view.stake == 100
  end

  test "the chop payment arrives as a {:coins, transfers} event right when the round ends" do
    [a, b, c] = users = Enum.map(~w(An Binh Chi), &user!/1)
    id = room!(100, %{0 => "3D 2H 9H", 1 => "4S 4C 5S 5C 6S 6C 9D", 2 => "10D JD"})
    for u <- users, do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
    :ok = RoomServer.start_game(id, a.id)

    :ok = RoomServer.play(id, a.id, cards("3D"))
    :ok = RoomServer.pass(id, b.id)
    :ok = RoomServer.pass(id, c.id)
    :ok = RoomServer.play(id, a.id, cards("2H"))
    :ok = RoomServer.play(id, b.id, cards("4S 4C 5S 5C 6S 6C"))
    :ok = RoomServer.pass(id, c.id)
    :ok = RoomServer.pass(id, a.id)

    assert_receive {:room_updated, _, _, events}
                   when is_list(events) and elem(hd(events), 0) == :passed and length(events) > 2

    assert {:coins, [%{from: 0, to: 1, amount: 200, reason: "chop"}]} = List.last(events)
    assert Economy.balance(b.id) == 1_200
  end

  test "stake 0 moves no coins" do
    [a, b] = users = Enum.map(~w(An Binh), &user!/1)
    id = room!(0, %{0 => "3D", 1 => "4S 2H"})
    for u <- users, do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
    :ok = RoomServer.start_game(id, a.id)
    :ok = RoomServer.play(id, a.id, cards("3D"))
    assert Economy.balance(a.id) == 1_000 and Economy.balance(b.id) == 1_000
  end

  test "eligibility: only players with 10×S are dealt in (E7)" do
    [a, b, c] = users = Enum.map(~w(An Binh Chi), &user!/1)
    id = room!(100, %{0 => "3D 9H", 2 => "4S 9C"})
    for u <- users, do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)

    # b drops below 1,000
    {:ok, _} = Economy.settle("drain", [%{from: b.id, to: c.id, amount: 1, reason: "test"}])
    :ok = RoomServer.start_game(id, a.id)
    assert RoomServer.view(id, a.id).game.seats == [0, 2]
    assert RoomServer.view(id, b.id).game.hand == []
  end

  test "the start is refused when fewer than 2 players have 10×S" do
    [a, b] = users = Enum.map(~w(An Binh), &user!/1)
    id = room!(200, %{})
    for u <- users, do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)
    assert RoomServer.start_game(id, a.id) == {:error, :not_enough_coins}
    assert RoomServer.view(id, b.id).status == :waiting
  end

  test "stake: host only, between games, 0 or ≥ 10" do
    [a, b] = users = Enum.map(~w(An Binh), &user!/1)
    id = room!(0, %{0 => "3D 9H", 1 => "4S 9C"})
    for u <- users, do: {:ok, _} = RoomServer.join(id, u.id, u.display_name)

    assert RoomServer.set_stake(id, b.id, 50) == {:error, :not_host}

    for bad <- [5, -10, 1.5, "100", nil],
        do: assert(RoomServer.set_stake(id, a.id, bad) == {:error, :invalid_stake})

    assert RoomServer.set_stake(id, a.id, 50) == :ok
    assert RoomServer.view(id, a.id).stake == 50
    :ok = RoomServer.start_game(id, a.id)
    assert RoomServer.set_stake(id, a.id, 10) == {:error, :game_in_progress}
  end

  test "opening a room with an invalid stake is refused" do
    assert RoomServer.start_room(stake: 9, economy: Economy) == {:error, :invalid_stake}
    assert RoomServer.start_room(stake: -1, economy: Economy) == {:error, :invalid_stake}
  end
end
