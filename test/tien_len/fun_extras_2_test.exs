defmodule TienLen.FunExtras2Test do
  @moduledoc """
  Batch 15: effects (SF1), shame titles (XH1–XH3), bot personalities (BP1–BP3), blowing
  (TB1), charms (TB2), seasonal events (EV1–EV3).

  Not async: the seasonal event is a global setting.
  """
  use TienLen.DataCase, async: false

  alias TienLen.{Accounts, Admin, BotTalk, Card, Commentary, Economy, Events, Room, RoomServer}
  alias TienLen.{Settings, Shame, Shop, Stats}

  defp cards(codes), do: Card.parse_many!(codes)
  defp hands(map), do: {:hands, Map.new(map, fn {seat, codes} -> {seat, cards(codes)} end)}

  defp user!(name) do
    {:ok, u} =
      Accounts.register_user(%{
        display_name: name,
        username: String.downcase(name) <> "_#{System.unique_integer([:positive])}",
        password: "mat-khau-123"
      })

    u
  end

  defp room_with(names) do
    names
    |> Enum.with_index(1)
    |> Enum.reduce(Room.new("r"), fn {name, id}, room ->
      {:ok, room, _seat, _events} = Room.join(room, id, name)
      room
    end)
  end

  defp fixed, do: %{roll: fn -> 0.0 end, pick: &hd/1}

  setup do
    on_exit(fn -> :persistent_term.erase({Settings, "season_event"}) end)
    :ok
  end

  describe "effects (SF1)" do
    test "a 2 is a pig, a chop is a chop, an instant win is confetti" do
      room = room_with(~w(An Binh Chi))

      {:ok, room, _} =
        Room.start_game(
          room,
          1,
          hands(%{0 => "3D 2H", 1 => "4S 4C 5S 5C 6S 6C 9D", 2 => "7S 8D"})
        )

      {:ok, new, events} = Room.command(room, 1, {:play, cards("3D")})
      assert Commentary.effects(room, events) == []
      {:ok, room, _} = Room.command(new, 2, :pass)
      {:ok, room, _} = Room.command(room, 3, :pass)

      {:ok, new, events} = Room.command(room, 1, {:play, cards("2H")})
      assert Commentary.effects(room, events) == ["pig"]
      {:ok, _new, events} = Room.command(new, 2, {:play, cards("4S 4C 5S 5C 6S 6C")})
      assert Commentary.effects(new, events) == ["chop"]

      assert Commentary.effects(room, [{:instant_win, [{0, :four_twos}]}]) == ["confetti"]
    end
  end

  describe "per-player facts and shame titles (XH1–XH3)" do
    test "a game records passes, plays, timeouts, thối and cóng" do
      room = room_with(~w(An Binh))
      {:ok, room, _} = Room.start_game(room, 1, hands(%{0 => "3D 5D", 1 => "4S 2S 2H 7C"}))
      {:ok, room, _} = Room.command(room, 1, {:play, cards("3D")})
      {:ok, room, _} = Room.turn_timeout(room)
      {:ok, room, _} = Room.command(room, 1, {:play, cards("5D")})

      [first, last] = Room.result(room).players
      assert %{seat: 0, plays: 2, passes: 0, timeouts: 0, thoi: 0, cong: false} = first
      assert %{seat: 1, plays: 0, passes: 1, timeouts: 1, thoi: 2, cong: false} = last
    end

    test "the week's holders, the pass-rate minimum and ties" do
      [a, b, c] = Enum.map(~w(An Binh Chi), &user!/1)

      record = fn players ->
        {:ok, _} =
          Stats.record(%{
            room_id: "t",
            ref: "room:t:game:#{System.unique_integer([:positive])}",
            player_count: length(players),
            instant_win: false,
            players:
              Enum.with_index(players, fn p, seat ->
                Map.merge(%{seat: seat, place: seat + 1, won: seat == 0, removed: false}, p)
              end)
          })
      end

      record.([
        %{user_id: a.id, chops: 2, plays: 10},
        %{user_id: b.id, thoi: 3, cong: true, passes: 40, plays: 5}
      ])

      record.([%{user_id: c.id, chops: 2, timeouts: 4, plays: 2}, %{user_id: a.id, passes: 1}])

      Shame.clear_cache()

      standings =
        Map.new(Shame.standings(), fn {t, rows} -> {t.id, Enum.map(rows, & &1.user_id)} end)

      assert standings["thoi"] == [b.id]
      assert standings["cong"] == [b.id]
      # a and c both chopped twice: c played fewer games, so c is "worse per game"
      assert standings["chop"] == [c.id, a.id]
      assert standings["slow"] == [c.id]
      # only b has 30 moves
      assert standings["pass"] == [b.id]

      assert Enum.map(Shame.titles_of(b.id), & &1.name) == [
               "Vua Thối Heo",
               "Chúa Tể Cóng",
               "Thánh Bỏ Lượt"
             ]

      assert [%{emoji: "🔪"}, %{emoji: "🐢"}] = Shame.titles_of(c.id)
      assert Shame.titles_of(a.id) == []
    end
  end

  describe "bot personalities (BP1–BP3)" do
    defp bots_room do
      room = room_with(["An"])
      {:ok, room, _} = Room.add_bot(room, 1, :easy)
      {:ok, room, _} = Room.add_bot(room, 1, :normal)
      room
    end

    test "names, avatars and speed of the personalities" do
      room = bots_room()
      assert %{name: "Bà Tám (dễ)", avatar: "👵", persona: :ba_tam} = room.seats[1]
      assert %{name: "Ông Cụ Non (thường)", avatar: "👴", persona: :ong_cu_non} = room.seats[2]
      {:ok, room, _} = Room.add_bot(room, 1, :easy)
      assert %{name: "Thanh Niên Nóng Tính (dễ)", avatar: "😤"} = room.seats[3]
      assert BotTalk.speed(room, 2) == 2.5
      assert BotTalk.speed(room, 3) == 0.5
      assert BotTalk.speed(room, 0) == 1.0

      # a freed personality is given again
      {:ok, room, _} = Room.remove_bot(room, 1, 1)
      {:ok, room, _} = Room.add_bot(room, 1, :normal)
      assert room.seats[1].persona == :ba_tam
    end

    test "lines at the start and on a chop (one per bot, most important first)" do
      room = bots_room()

      deal = hands(%{0 => "3D 2H 9S", 1 => "4S 4C 5D 5C 6S 6C 9D", 2 => "7S 8D 10H JC"})
      {:ok, started, events} = Room.start_game(room, 1, deal)

      assert BotTalk.lines(room, started, events, fixed()) == [
               {1, "Bài xấu quá trời ơi!"},
               {2, "Từ từ, để ông xem bài…"}
             ]

      {:ok, r, _} = Room.command(started, 1, {:play, cards("3D")})
      {:ok, r, _} = Room.command(r, {:bot, 1}, :pass)
      {:ok, r, _} = Room.command(r, {:bot, 2}, :pass)
      {:ok, r, _} = Room.command(r, 1, {:play, cards("2H")})
      {:ok, new, events} = Room.command(r, {:bot, 1}, {:play, cards("4S 4C 5D 5C 6S 6C")})

      # Bà Tám chopped; Ông Cụ Non has no line for someone else's chop
      assert BotTalk.lines(r, new, events, fixed()) == [{1, "Bà chặt nè, ai biểu!"}]
      # nothing happens when the roll misses
      assert BotTalk.lines(r, new, events, %{fixed() | roll: fn -> 0.99 end}) == []
      # no bots, no lines
      assert BotTalk.lines(room_with(["An"]), room_with(["An"]), events, fixed()) == []
    end
  end

  describe "blowing on the cards (TB1)" do
    test "only while waiting, once per 3 s, seen by everyone" do
      {:ok, id} =
        RoomServer.start_room(recorder: nil, deals: [hands(%{0 => "3D 4D", 1 => "5D 6D"})])

      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      RoomServer.subscribe(id)
      {:ok, _} = RoomServer.join(id, 1, "An")
      {:ok, _} = RoomServer.join(id, 2, "Binh")

      assert :ok = RoomServer.blow(id, 2)
      assert_receive {:blow, ^id, 1}
      assert {:error, :blow_too_fast} = RoomServer.blow(id, 2)
      assert {:error, :not_in_room} = RoomServer.blow(id, 3)
      :ok = RoomServer.start_game(id, 1)
      assert {:error, :game_in_progress} = RoomServer.blow(id, 1)
    end
  end

  describe "charms (TB2)" do
    test "buy, wear, take off; carried into the room" do
      u = user!("An")
      assert Shop.equipped(u, :charm) == nil
      assert {:ok, 800} = Shop.buy(u.id, "toi")
      assert {:ok, u} = Shop.equip(u, "toi")
      assert Shop.equipped(u, :charm) == "toi"
      assert Shop.charm_icon("toi") == "🧄"
      assert Shop.charm_icon("lixi") == nil
      assert {:ok, u} = Shop.remove_charm(u)
      assert Shop.equipped(u, :charm) == nil

      {:ok, id} = RoomServer.start_room(recorder: nil)
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)

      {:ok, _} =
        RoomServer.join(id, 1, "An", nil, %{
          charm: "toi",
          titles: [%{id: "x", emoji: "🐷", name: "Vua"}]
        })

      assert [%{charm: "toi", titles: [%{emoji: "🐷"}]}] = RoomServer.view(id, 1).players
    end
  end

  describe "seasonal events (EV1–EV3)" do
    test "the lì xì table, idempotency and the daily cap" do
      assert Events.draw(0) == 8
      assert Events.draw(29) == 8
      assert Events.draw(30) == 18
      assert Events.draw(99) == 168
      assert Enum.sum(Enum.map(Events.lixi_table(), &elem(&1, 1))) == 100

      u = user!("An")
      assert {:ok, 68} = Events.lixi(u.id, "room:x:game:1", 90)
      assert {:error, :already_claimed} = Events.lixi(u.id, "room:x:game:1", 0)
      assert Economy.balance(u.id) == 1_068
      assert [%{reason: "lixi", amount: 68} | _] = Economy.history(u.id)

      for n <- 2..10, do: {:ok, _} = Events.lixi(u.id, "room:x:game:#{n}", 0)
      assert {:error, :daily_cap} = Events.lixi(u.id, "room:x:game:11", 0)
    end

    test "an admin starts Tết: 1st places of recorded games get a lì xì, announced in the chat" do
      [admin, a, b] = Enum.map(~w(Admin An Binh), &user!/1)
      {:ok, _} = Admin.promote(admin.username)
      assert {:error, :unknown_event} = Admin.set_event(admin.id, "halloween")
      assert {:error, :forbidden} = Admin.set_event(a.id, "tet")
      assert :ok = Admin.set_event(admin.id, "tet")
      assert Events.current() == "tet"

      {:ok, id} =
        RoomServer.start_room(
          economy: Economy,
          recorder: Stats,
          deals: [hands(%{0 => "3D", 1 => "4D 5D"})]
        )

      pid = RoomServer.whereis(id)
      Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
      RoomServer.subscribe(id)
      {:ok, _} = RoomServer.join(id, a.id, "An")
      {:ok, _} = RoomServer.join(id, b.id, "Binh")
      :ok = RoomServer.start_game(id, a.id)
      :ok = RoomServer.play(id, a.id, cards("3D"))

      assert_receive {:room_chat, ^id, %{system: true, text: "🧧 An được lì xì " <> _}}
      assert [%{reason: "lixi"} | _] = Economy.history(a.id)
      assert Economy.balance(b.id) == 1_000

      assert :ok = Admin.set_event(admin.id, "none")
      assert Events.current() == nil
    end

    test "Trung thu: avatars wear a lantern" do
      :persistent_term.put({Settings, "season_event"}, "trung_thu")
      assert TienLenWeb.Text.avatar("🐼") == "🐼🏮"
      assert TienLenWeb.Text.avatar(nil) == "🙂🏮"
      :persistent_term.erase({Settings, "season_event"})
      assert TienLenWeb.Text.avatar("🐼") == "🐼"
    end
  end
end
