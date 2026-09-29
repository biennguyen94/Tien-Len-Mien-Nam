defmodule TienLen.FunExtrasTest do
  @moduledoc "Batch 14: throwing items (TH1–TH4), commentator (BL1–BL2), runaway (RC1), shop (SH1–SH3)."
  use TienLen.DataCase, async: true

  alias TienLen.{Accounts, Card, Commentary, Economy, Room, RoomServer, Shop}

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

  defp hands(map), do: {:hands, Map.new(map, fn {seat, codes} -> {seat, cards(codes)} end)}

  # a room with players 1.. (names given) and a started game
  defp room_game(names, deal) do
    room =
      names
      |> Enum.with_index(1)
      |> Enum.reduce(Room.new("r"), fn {name, id}, room ->
        {:ok, room, _seat, _events} = Room.join(room, id, name)
        room
      end)

    {:ok, room, events} = Room.start_game(room, 1, deal)
    {room, events}
  end

  # applies a command and returns the new room with the commentator's lines (first template)
  defp step(room, player_id, cmd) do
    {:ok, new, events} = Room.command(room, player_id, cmd)
    {new, Commentary.lines(room, new, events, &hd/1)}
  end

  describe "commentator (BL1, BL2)" do
    test "về nhất, chặt heo, chặt chồng, báo 1 and thối heo in one game" do
      {room, _} =
        room_game(
          ~w(An Binh Chi),
          hands(%{
            0 => "3D 2H",
            1 => "4S 4C 5S 5C 6S 6C 9D 2C",
            2 => "7S 7C 8S 8C 9S 9C 10D 2S"
          })
        )

      {room, ["📢 An BÁO 1! Mọi người cẩn thận!"]} = step(room, 1, {:play, cards("3D")})
      {room, []} = step(room, 2, :pass)
      {room, _} = step(room, 3, :pass)
      {room, lines} = step(room, 1, {:play, cards("2H")})
      assert lines == ["🥇 An về nhất, nhẹ nhàng như đi chợ!"]

      {room, lines} = step(room, 2, {:play, cards("4S 4C 5S 5C 6S 6C")})
      assert lines == ["💥 Ối dồi ôi! Binh vừa chặt heo của An, heo khóc thét éc éc!"]

      {room, lines} = step(room, 3, {:play, cards("7S 7C 8S 8C 9S 9C")})
      assert lines == ["💣 Chặt chồng! Chi chặt luôn cả Binh, ai chặt người đó chịu!"]

      {room, _} = step(room, 2, :pass)
      {room, lines} = step(room, 3, {:play, cards("10D")})
      assert lines == ["📢 Chi BÁO 1! Mọi người cẩn thận!"]

      {room, _} = step(room, 2, :pass)
      {_room, lines} = step(room, 3, {:play, cards("2S")})
      assert "🐷 Binh ôm 1 con heo về chuồng, mất trắng!" in lines
      refute Enum.any?(lines, &(&1 =~ "cóng"))
    end

    test "cóng and thối heo together when the loser never played" do
      {room, _} =
        room_game(
          ~w(An Binh),
          hands(%{0 => "3D", 1 => "4S 5S 6S 7S 8S 9S JC QC KC AC 4H 5H 2S"})
        )

      {_room, lines} = step(room, 1, {:play, cards("3D")})

      assert lines == [
               "🥇 An về nhất, nhẹ nhàng như đi chợ!",
               "🥶 Binh bị cóng, chưa kịp đánh lá nào…",
               "🐷 Binh ôm 1 con heo về chuồng, mất trắng!"
             ]
    end

    test "tới trắng at the deal" do
      room =
        Enum.reduce([{1, "An"}, {2, "Binh"}], Room.new("r"), fn {id, name}, room ->
          {:ok, room, _, _} = Room.join(room, id, name)
          room
        end)

      deal =
        hands(%{
          0 => "2S 2C 2D 2H 3S 5C 7D 9H JS KC 4D 6H 8S",
          1 => "3C 4S 5D 6C 7H 8D 9S 10H JC QS KH 3D 10C"
        })

      {:ok, new, events} = Room.start_game(room, 1, deal)
      assert Commentary.lines(room, new, events, &hd/1) == ["🎆 An TỚI TRẮNG! Cả làng nín thở!"]
    end

    test "leaving during a game is a runaway (RC1); a disconnect timeout is a lost signal" do
      deal = hands(%{0 => "3D 4D", 1 => "5D 6D", 2 => "7D 8D"})
      {room, _} = room_game(~w(An Binh Chi), deal)

      {:ok, new, events} = Room.leave(room, 3)
      assert {:left, 2} in events

      assert Commentary.lines(room, new, events, &hd/1) == [
               "🏃💨 Chi đã chạy mất dép 🩴, bị loại khỏi ván!"
             ]

      {:ok, room, _} = Room.disconnect(room, 2)
      {:ok, new, events} = Room.disconnect_timeout(room, 2)

      assert Commentary.lines(room, new, events, &hd/1) == [
               "📵 Binh mất sóng lâu quá, bị loại khỏi ván!"
             ]

      # leaving between games says nothing
      room = %{room | status: :waiting}
      {:ok, new, events} = Room.leave(room, 3)
      assert Commentary.lines(room, new, events, &hd/1) == []
    end

    test "a timeout of a connected player is ngủ gật" do
      {room, _} = room_game(~w(An Binh), hands(%{0 => "3D 4D", 1 => "5D 6D"}))
      {:ok, new, events} = Room.turn_timeout(room)
      assert "😴 An ngủ gật, hết giờ rồi!" in Commentary.lines(room, new, events, &hd/1)
    end

    test "every template is filled (no placeholder left)" do
      for {_kind, list} <- Commentary.templates(), t <- list do
        filled =
          t
          |> String.replace("{a}", "X")
          |> String.replace("{b}", "Y")
          |> String.replace("{n}", "2")

        refute filled =~ "{"
      end
    end

    test "the room posts the lines in the room chat as the commentator" do
      {:ok, id} =
        RoomServer.start_room(recorder: nil, deals: [hands(%{0 => "3D 4D", 1 => "5D 2S"})])

      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      RoomServer.subscribe(id)
      {:ok, _} = RoomServer.join(id, 1, "An")
      {:ok, _} = RoomServer.join(id, 2, "Binh")
      :ok = RoomServer.start_game(id, 1)
      :ok = RoomServer.play(id, 1, cards("3D"))

      assert_receive {:room_chat, ^id, %{system: true, user_id: nil, text: text, name: name}}
      assert text =~ "An"
      assert name == Commentary.name()
      assert {:ok, [%{system: true}]} = RoomServer.chat_history(id, 1)
    end
  end

  describe "throwing items (TH1–TH4)" do
    setup do
      [a, b] = Enum.map(~w(An Binh), &user!/1)
      {:ok, id} = RoomServer.start_room(economy: Economy, recorder: nil)
      pid = RoomServer.whereis(id)
      Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
      RoomServer.subscribe(id)
      {:ok, 0} = RoomServer.join(id, a.id, "An")
      {:ok, 1} = RoomServer.join(id, b.id, "Binh")
      %{id: id, a: a, b: b}
    end

    test "the price is spent and everyone is told", %{id: id, a: a, b: b} do
      assert :ok = RoomServer.throw(id, a.id, 1, "rose")
      assert_receive {:thrown, ^id, 0, 1, "rose"}
      assert Economy.balance(a.id) == 995
      assert Economy.balance(b.id) == 1_000
      assert [%{reason: "throw", amount: -5, balance_after: 995} | _] = Economy.history(a.id)
    end

    test "refused: own seat, empty seat, unknown item, too fast, not enough coins", %{
      id: id,
      a: a,
      b: b
    } do
      assert {:error, :invalid_target} = RoomServer.throw(id, a.id, 0, "tomato")
      assert {:error, :invalid_target} = RoomServer.throw(id, a.id, 3, "tomato")
      assert {:error, :unknown_command} = RoomServer.throw(id, a.id, 1, "brick")
      assert {:error, :not_in_room} = RoomServer.throw(id, 999_999, 1, "tomato")

      assert :ok = RoomServer.throw(id, a.id, 1, "tomato")
      assert {:error, :throw_too_fast} = RoomServer.throw(id, a.id, 1, "tomato")

      {:ok, _} = Economy.adjust(b.id, -998, "test", a.id)
      assert {:error, :cannot_afford} = RoomServer.throw(id, b.id, 0, "slipper")
      assert Economy.balance(b.id) == 2
      refute_received {:thrown, ^id, 1, 0, _}
    end
  end

  describe "Economy.spend/5 (T26)" do
    test "spends, refuses more than the balance, and rolls back when `also` fails" do
      u = user!("An")
      assert {:ok, 900} = Economy.spend(u.id, 100, "shop", "x")
      assert {:error, :insufficient_coins} = Economy.spend(u.id, 901, "shop", "x")
      assert {:error, :nope} = Economy.spend(u.id, 10, "shop", "x", fn -> {:error, :nope} end)
      assert Economy.balance(u.id) == 900
      assert {:error, :invalid_amount} = Economy.spend(u.id, 0, "shop")
      assert [%{amount: -100, reason: "shop"} | _] = Economy.history(u.id)
    end
  end

  describe "shop (SH1–SH3)" do
    test "buy once, equip, and never pay twice" do
      u = user!("An")
      assert MapSet.member?(Shop.owned(u.id), "classic")
      assert Shop.equipped(u, :card_back) == "classic"
      assert Shop.equipped(u, :table) == "felt"

      assert {:error, :not_owned} = Shop.equip(u, "lixi")
      assert {:ok, 500} = Shop.buy(u.id, "lixi")
      assert {:error, :already_owned} = Shop.buy(u.id, "lixi")
      assert {:error, :cannot_afford} = Shop.buy(u.id, "song_bai")
      assert {:error, :not_found} = Shop.buy(u.id, "nope")
      assert {:error, :already_owned} = Shop.buy(u.id, "classic")
      assert Economy.balance(u.id) == 500

      assert {:ok, u} = Shop.equip(u, "lixi")
      assert Shop.equipped(u, :card_back) == "lixi"
      assert {:ok, u} = Shop.equip(u, "felt")
      assert Shop.equipped(u, :table) == "felt"
      assert [%{reason: "shop", amount: -500, ref: "Bao lì xì"} | _] = Economy.history(u.id)
    end

    test "every item has a known kind and a unique id; one free default per kind" do
      ids = Enum.map(Shop.items(), & &1.id)
      assert ids == Enum.uniq(ids)
      assert Enum.all?(Shop.items(), &(&1.kind in [:card_back, :table, :charm]))
      assert Enum.filter(Shop.items(:charm), &(&1.price == 0)) == []
      assert [%{id: "classic"}] = Enum.filter(Shop.items(:card_back), &(&1.price == 0))
      assert [%{id: "felt"}] = Enum.filter(Shop.items(:table), &(&1.price == 0))
      assert Shop.valid("felt", :card_back) == "classic"
      assert Shop.valid(nil, :table) == "felt"
    end

    test "the card back is taken into the room and shown to others" do
      {:ok, id} = RoomServer.start_room(recorder: nil)
      on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
      {:ok, _} = RoomServer.join(id, 1, "An", nil, %{card_back: "lixi"})
      {:ok, _} = RoomServer.join(id, 2, "Binh")
      view = RoomServer.view(id, 2)
      assert [%{card_back: "lixi"}, %{card_back: nil}] = view.players
    end
  end
end
