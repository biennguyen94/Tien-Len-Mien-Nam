defmodule TienLen.RoomServerTest do
  use ExUnit.Case, async: true

  alias TienLen.{Card, Combination, RoomServer}

  defp cards(codes), do: Card.parse_many!(codes)
  defp hands(map), do: {:hands, Map.new(map, fn {seat, codes} -> {seat, cards(codes)} end)}

  defp start!(opts \\ []) do
    {:ok, id} = RoomServer.start_room(opts)
    RoomServer.subscribe(id)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  # A player process: joins and stays alive until told to stop (or killed).
  defp spawn_player(id, player_id, name) do
    test = self()

    pid =
      spawn(fn ->
        send(test, {:joined, player_id, RoomServer.join(id, player_id, name)})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:joined, ^player_id, {:ok, seat}}
    {pid, seat}
  end

  defp events_until(pred, timeout \\ 2_000) do
    receive do
      {:room_updated, _id, _version, events} ->
        if pred.(events), do: events, else: events_until(pred, timeout)
    after
      timeout -> flunk("expected event did not arrive")
    end
  end

  describe "lifecycle" do
    test "start, join, start a game, view; duplicate ids are refused" do
      id = start!(deals: [hands(%{0 => "3S 9H", 1 => "4S 4C"})])
      assert RoomServer.start_room(id: id) == {:error, :already_exists}

      assert RoomServer.join(id, :p1, "An") == {:ok, 0}
      assert RoomServer.join(id, :p2, "Bình") == {:ok, 1}
      assert_receive {:room_updated, ^id, _, [{:joined, 1}]}

      assert RoomServer.start_game(id, :p2) == {:error, :not_host}
      assert RoomServer.start_game(id, :p1) == :ok
      assert_receive {:room_updated, ^id, _, [{:game_started, [0, 1]}]}

      view = RoomServer.view(id, :p2)
      assert view.status == :playing
      assert view.game.hand == cards("4S 4C")
      assert view.game.current == 0
      assert is_integer(view.turn_ms_left) and view.turn_ms_left > 0
    end

    test "unknown rooms answer :room_not_found" do
      assert RoomServer.join("nope", :p1, "x") == {:error, :room_not_found}
      assert RoomServer.view("nope", :p1) == {:error, :room_not_found}
    end

    test "the room stops when the last player leaves" do
      id = start!()
      {:ok, 0} = RoomServer.join(id, :p1, "An")
      pid = RoomServer.whereis(id)
      ref = Process.monitor(pid)
      assert RoomServer.leave(id, :p1) == :ok
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert RoomServer.whereis(id) == nil
    end
  end

  describe "commands" do
    test "are validated per player and bad input never crashes the room" do
      id = start!(deals: [hands(%{0 => "3S 9H", 1 => "4S 4C"})])
      {:ok, 0} = RoomServer.join(id, :p1, "An")
      {:ok, 1} = RoomServer.join(id, :p2, "Bình")
      :ok = RoomServer.start_game(id, :p1)
      pid = RoomServer.whereis(id)

      assert RoomServer.play(id, :p2, cards("4S")) == {:error, :not_your_turn}
      assert RoomServer.play(id, :p1, cards("4S")) == {:error, :not_your_cards}
      assert RoomServer.play(id, :p1, [:junk, 42]) == {:error, :not_your_cards}
      assert RoomServer.play(id, :p1, "3S") == {:error, :not_your_cards}
      assert RoomServer.pass(id, :p1) == {:error, :cannot_pass_on_lead}
      assert RoomServer.pass(id, :stranger) == {:error, :not_in_room}
      assert RoomServer.chop(id, :p2, cards("4S 4C")) == {:error, :not_four_pair}
      assert Process.alive?(pid)

      assert RoomServer.play(id, :p1, cards("3S")) == :ok
      assert_receive {:room_updated, ^id, _, [{:played, 0, %Combination{}}]}
    end

    test "near-simultaneous out-of-turn chops are serialised; the result is consistent" do
      # seat 0 opens with 3S, seat 1 answers with a 2; seats 2 and 3 both hold a four-pair
      deal =
        hands(%{
          0 => "3S 9H",
          1 => "2H 10C",
          2 => "4S 4C 5S 5C 6S 6C 7S 7C KD",
          3 => "8S 8C 9S 9C 10S 10D JS JC KH"
        })

      id = start!(deals: [deal])
      for {p, n} <- [p0: "a", p1: "b", p2: "c", p3: "d"], do: {:ok, _} = RoomServer.join(id, p, n)
      :ok = RoomServer.start_game(id, :p0)
      :ok = RoomServer.play(id, :p0, cards("3S"))
      :ok = RoomServer.play(id, :p1, cards("2H"))

      low = cards("4S 4C 5S 5C 6S 6C 7S 7C")
      high = cards("8S 8C 9S 9C 10S 10D JS JC")

      [r_low, r_high] =
        [
          Task.async(fn -> RoomServer.chop(id, :p2, low) end),
          Task.async(fn -> RoomServer.chop(id, :p3, high) end)
        ]
        |> Task.await_many()

      assert r_high == :ok
      assert r_low in [:ok, {:error, :too_low}]

      centre = RoomServer.view(id, :p0).game.centre
      # whatever the order, the higher four-pair ends on top and play continues after its owner
      assert centre.owner == 3
      assert centre.cards == high
      assert RoomServer.view(id, :p0).game.current == 0
    end
  end

  describe "turn timer (T16)" do
    test "the server acts for a player whose turn times out" do
      id = start!(turn_timeout: 30, deals: [hands(%{0 => "3S 9H", 1 => "4S 4C"})])
      {:ok, 0} = RoomServer.join(id, :p1, "An")
      {:ok, 1} = RoomServer.join(id, :p2, "Bình")
      :ok = RoomServer.start_game(id, :p1)

      # seat 0 must lead with 3S: the timeout plays it
      events = events_until(&({:timed_out, 0} in &1))
      assert [{:timed_out, 0}, {:played, 0, %Combination{cards: [three_spades]}} | _] = events
      assert three_spades == Card.parse!("3S")

      # seat 1 then responds; its timeout is a pass
      events = events_until(&({:timed_out, 1} in &1))
      assert {:passed, 1} in events
    end

    test "a whole game can be finished by timeouts; broadcasts never carry unplayed cards" do
      id = start!(turn_timeout: 2, deals: [123])

      for {p, n} <- [p0: "a", p1: "b", p2: "c", p3: "d"], do: {:ok, _} = RoomServer.join(id, p, n)
      :ok = RoomServer.start_game(id, :p0)

      broadcasts = collect_until_game_over([], 10_000)
      events = Enum.flat_map(broadcasts, & &1)

      played =
        for {kind, _seat, %Combination{cards: cs}} <- events,
            kind in [:played, :chopped],
            cs <- cs,
            do: cs

      carried = events |> Enum.flat_map(&cards_in/1)
      assert Enum.all?(carried, &(&1 in played)), "a broadcast carried an unplayed card"

      view = RoomServer.view(id, :p0)
      assert view.status == :waiting
      assert view.games_played == 1
      assert length(List.flatten(view.game.ranking)) == 4
    end
  end

  defp collect_until_game_over(acc, timeout) do
    receive do
      {:room_updated, _id, _v, events} ->
        acc = [events | acc]

        if Enum.any?(events, &(elem(&1, 0) == :game_over)),
          do: Enum.reverse(acc),
          else: collect_until_game_over(acc, timeout)
    after
      timeout -> flunk("game did not finish by timeouts")
    end
  end

  # Every %Card{} anywhere inside a term.
  defp cards_in(%Card{} = card), do: [card]
  defp cards_in(%_{} = struct), do: struct |> Map.from_struct() |> cards_in()
  defp cards_in(map) when is_map(map), do: map |> Map.values() |> Enum.flat_map(&cards_in/1)
  defp cards_in(list) when is_list(list), do: Enum.flat_map(list, &cards_in/1)
  defp cards_in(tuple) when is_tuple(tuple), do: tuple |> Tuple.to_list() |> cards_in()
  defp cards_in(_), do: []

  describe "connections (T15, S5, S6, X3)" do
    test "a player whose process dies is disconnected, then removed after the timeout; host moves" do
      id =
        start!(
          disconnect_timeout: 30,
          deals: [hands(%{0 => "3S 9H", 1 => "4S 9C", 2 => "5S 9D"})]
        )

      {host_pid, 0} = spawn_player(id, :p1, "An")
      {:ok, 1} = RoomServer.join(id, :p2, "Bình")
      {:ok, 2} = RoomServer.join(id, :p3, "Chi")
      :ok = RoomServer.start_game(id, :p1)

      Process.exit(host_pid, :kill)
      assert events_until(&({:disconnected, 0} in &1))
      events = events_until(&({:removed, 0} in &1))
      assert {:host_changed, 1} in events

      view = RoomServer.view(id, :p2)
      assert view.host == 1
      assert view.game.removed == [0]
      assert Enum.find(view.players, &(&1.seat == 0)).connected == false
    end

    test "reconnecting before the timeout cancels the removal" do
      id = start!(disconnect_timeout: 150, deals: [hands(%{0 => "3S 9H", 1 => "4S 9C"})])
      {:ok, 0} = RoomServer.join(id, :p1, "An")
      {pid, 1} = spawn_player(id, :p2, "Bình")
      :ok = RoomServer.start_game(id, :p1)

      Process.exit(pid, :kill)
      assert events_until(&({:disconnected, 1} in &1))
      assert {_pid2, 1} = spawn_player(id, :p2, "Bình")
      assert events_until(&({:connected, 1} in &1))

      refute_receive {:room_updated, _, _, [{:removed, 1} | _]}, 300
      assert RoomServer.view(id, :p1).game.removed == []
    end

    test "one player with two tabs stays connected until both are gone" do
      id = start!(disconnect_timeout: 1_000)
      {:ok, 0} = RoomServer.join(id, :p1, "An")
      {tab1, 1} = spawn_player(id, :p2, "Bình")
      {tab2, 1} = spawn_player(id, :p2, "Bình")

      Process.exit(tab1, :kill)
      refute_receive {:room_updated, _, _, [{:disconnected, 1}]}, 100
      Process.exit(tab2, :kill)
      assert events_until(&({:disconnected, 1} in &1))
    end

    test "the room stops once nobody is connected after the timeout" do
      id = start!(disconnect_timeout: 20)
      {pid, 0} = spawn_player(id, :p1, "An")
      room_pid = RoomServer.whereis(id)
      ref = Process.monitor(room_pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^room_pid, :normal}, 1_000
    end
  end
end
