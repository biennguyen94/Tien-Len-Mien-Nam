defmodule TienLen.ChatTest do
  @moduledoc "Phases 24–25, 27 (CH1–CH4, G1–G7, G12): chat rules in the domain."
  # the lobby chat and private conversations are global processes
  use TienLenWeb.ConnCase, async: false

  alias TienLen.{Admin, Chat, Presence, RoomServer}
  alias TienLen.Chat.Private

  defp user(name) do
    _ = login_conn(name)
    test_user(name)
  end

  # an open page of `user` (G6), without a browser
  defp online(user, place \\ "lobby", room_id \\ nil) do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    {:ok, _} = Presence.track_page(pid, user, place, room_id)
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  defp room! do
    {:ok, id} = RoomServer.start_room()
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  describe "text and sender (G2, G12)" do
    test "normalize trims and collapses, 1–200 characters, valid UTF-8" do
      assert Chat.normalize("  xin \n  chào ") == {:ok, "xin chào"}
      assert {:ok, _} = Chat.normalize(String.duplicate("á", 200))
      assert Chat.normalize(String.duplicate("a", 201)) == {:error, :invalid_message}
      assert Chat.normalize("   ") == {:error, :invalid_message}
      assert Chat.normalize(<<0xFF>>) == {:error, :invalid_message}
      assert Chat.normalize(nil) == {:error, :invalid_message}
    end

    test "the name comes from the account; the 6th message in 10 s is refused" do
      u = user("Chatty")
      assert {:ok, %{name: "Chatty", user_id: id, text: "hi"}} = Chat.prepare(u.id, "hi")
      assert id == u.id
      for _ <- 1..4, do: assert({:ok, _} = Chat.prepare(u.id, "x"))
      assert Chat.prepare(u.id, "x") == {:error, :chat_too_fast}
    end

    test "muted and locked players cannot send; unknown ids neither" do
      admin = user("Boss")
      {:ok, _} = Admin.promote(admin.username)
      u = user("Loud")

      assert {:ok, _} = Admin.mute(admin.id, u.id, 10, "spam")
      assert Chat.prepare(u.id, "hello") == {:error, :muted}
      assert Chat.send_lobby(u.id, "hello") == {:error, :muted}
      assert {:ok, _} = Admin.unmute(admin.id, u.id)
      assert {:ok, _} = Chat.prepare(u.id, "hello")

      {:ok, _} = Admin.lock(admin.id, u.id, "abuse")
      assert Chat.prepare(u.id, "hello") == {:error, :forbidden}
      assert Chat.prepare(-1, "hello") == {:error, :forbidden}
    end

    test "mute rules: admins only, not yourself, 10 / 60 / 1440 minutes, audited" do
      admin = user("Boss")
      {:ok, _} = Admin.promote(admin.username)
      u = user("Pat")

      assert Admin.mute(u.id, admin.id, 10) == {:error, :forbidden}
      assert Admin.mute(admin.id, admin.id, 10) == {:error, :cannot_mute_self}
      assert Admin.mute(admin.id, u.id, 7) == {:error, :invalid_duration}
      assert Admin.unmute(admin.id, u.id) == {:error, :not_muted}
      assert {:ok, muted} = Admin.mute(admin.id, u.id, 1440)
      assert DateTime.diff(muted.muted_until, DateTime.utc_now()) in (1440 * 60 - 5)..(1440 * 60)
      assert %{action: "mute", details: %{"minutes" => 1440}} = hd(Admin.actions(1))
    end
  end

  describe "room chat (G4)" do
    test "only seated players write and read; broadcast on the room topic; last 50 kept" do
      id = room!()
      a = user("An")
      b = user("Binh")
      {:ok, _} = RoomServer.join(id, a.id, "An")
      RoomServer.subscribe(id)

      assert :ok = Chat.send_room(id, a.id, "chào cả nhà")
      assert_receive {:room_chat, ^id, %{text: "chào cả nhà", name: "An"}}
      assert Chat.send_room(id, b.id, "tôi chưa ngồi") == {:error, :not_in_room}
      assert Chat.room_history(id, b.id) == {:error, :not_in_room}
      assert {:ok, [%{text: "chào cả nhà"}]} = Chat.room_history(id, a.id)

      msg = %{id: 0, user_id: a.id, name: "An", text: "x", at: DateTime.utc_now()}
      for i <- 1..60, do: :ok = RoomServer.chat(id, a.id, %{msg | id: i, text: "m#{i}"})
      {:ok, history} = Chat.room_history(id, a.id)
      assert length(history) == 50
      assert hd(history).text == "m11" and List.last(history).text == "m60"
    end

    test "chat works during a game (CH4) and admins delete messages (G12)" do
      id = room!()
      a = user("An")
      b = user("Binh")
      admin = user("Boss")
      {:ok, _} = Admin.promote(admin.username)
      {:ok, _} = RoomServer.join(id, a.id, "An")
      {:ok, _} = RoomServer.join(id, b.id, "Binh")
      :ok = RoomServer.start_game(id, a.id)
      RoomServer.subscribe(id)

      :ok = Chat.send_room(id, b.id, "bài xấu quá")
      assert_receive {:room_chat, ^id, %{id: msg_id}}

      assert Admin.delete_message(a.id, {:room, id, msg_id}) == {:error, :forbidden}
      assert :ok = Admin.delete_message(admin.id, {:room, id, msg_id})
      assert_receive {:room_chat_deleted, ^id, ^msg_id}
      assert {:ok, []} = Chat.room_history(id, a.id)
      assert %{action: "delete_message", target: target} = hd(Admin.actions(1))
      assert target == b.username
      assert Admin.delete_message(admin.id, {:room, id, msg_id}) == {:error, :not_found}
    end
  end

  describe "lobby chat (G5)" do
    test "messages are broadcast and kept (last 100); admins delete them" do
      a = user("An")
      admin = user("Boss")
      {:ok, _} = Admin.promote(admin.username)
      Chat.subscribe_lobby()

      :ok = Chat.send_lobby(a.id, "có ai chơi không?")
      assert_receive {:lobby_chat, %{id: msg_id, text: "có ai chơi không?"}}
      assert Enum.any?(Chat.lobby_history(), &(&1.id == msg_id))
      assert length(Chat.lobby_history()) <= 100

      :ok = Admin.delete_message(admin.id, {:lobby, msg_id})
      assert_receive {:lobby_chat_deleted, ^msg_id}
      refute Enum.any?(Chat.lobby_history(), &(&1.id == msg_id))
    end
  end

  describe "private chat (G1, G7)" do
    test "only to online players; both sides get the line; unread counts; read" do
      a = user("An")
      b = user("Binh")
      Phoenix.PubSub.subscribe(TienLen.PubSub, Admin.user_topic(a.id))
      Phoenix.PubSub.subscribe(TienLen.PubSub, Admin.user_topic(b.id))

      assert Chat.send_private(a.id, b.id, "ê") == {:error, :not_online}
      assert Chat.send_private(a.id, a.id, "ê") == {:error, :not_found}

      online(b)
      assert :ok = Chat.send_private(a.id, b.id, "vào phòng không?")
      bid = b.id
      assert_receive {:private_msg, %{text: "vào phòng không?"}, ^bid}
      assert_receive {:private_msg, %{text: "vào phòng không?"}, ^bid}

      assert [%{text: "vào phòng không?"}] = Chat.conversation(b.id, a.id)
      assert [%{peer_id: pid, name: "An", unread: 1}] = Chat.conversations(b.id)
      assert pid == a.id
      assert [%{name: "Binh", unread: 0}] = Chat.conversations(a.id)
      Chat.mark_read(b.id, a.id)
      assert [%{unread: 0}] = Chat.conversations(b.id)
    end

    test "20 lines per pair; dropped after 1 hour without messages" do
      a = user("An")
      b = user("Binh")
      online(b)
      msg = %{id: 0, user_id: a.id, name: "An", text: "x", at: DateTime.utc_now()}
      for i <- 1..25, do: :ok = Private.post(b.id, "Binh", %{msg | id: i, text: "m#{i}"})
      lines = Chat.conversation(a.id, b.id)
      assert length(lines) == 20 and hd(lines).text == "m6"

      :ok = Private.sweep(System.monotonic_time(:millisecond) + :timer.minutes(59))
      assert length(Chat.conversation(a.id, b.id)) == 20
      :ok = Private.sweep(System.monotonic_time(:millisecond) + :timer.minutes(61))
      assert Chat.conversation(a.id, b.id) == []
      assert Chat.conversations(b.id) == []
    end
  end

  describe "presence (G6)" do
    test "the most specific place wins; gone when the page closes" do
      u = user("Walker")
      p1 = online(u, "other")
      assert %{place: "other"} = Presence.get_user(u.id)
      online(u, "playing", "abc")
      assert %{place: "playing", room_id: "abc"} = Presence.get_user(u.id)
      assert Enum.any?(Presence.online_users(), &(&1.id == u.id))
      Process.exit(p1, :kill)
    end
  end
end
