defmodule TienLen.InvitesTest do
  @moduledoc "Phase 26 (IV1, IV3, G8, G9) and private rooms (IV2, G11)."
  use TienLenWeb.ConnCase, async: false

  alias TienLen.{Accounts, Admin, Invites, Lobby, Presence, Room, RoomServer}

  defp user(name) do
    _ = login_conn(name)
    test_user(name)
  end

  defp online(user, place \\ "lobby", room_id \\ nil) do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    {:ok, _} = Presence.track_page(pid, user, place, room_id)
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  defp room!(opts \\ []) do
    {:ok, id} = RoomServer.start_room(opts)
    on_exit(fn -> if pid = RoomServer.whereis(id), do: Process.exit(pid, :kill) end)
    id
  end

  defp listen(user), do: Phoenix.PubSub.subscribe(TienLen.PubSub, Admin.user_topic(user.id))

  setup do
    a = user("An")
    b = user("Binh")
    id = room!()
    {:ok, _} = RoomServer.join(id, a.id, "An")
    online(b)
    %{a: a, b: b, id: id}
  end

  test "invite → popup message → accept; the inviter is told", %{a: a, b: b, id: id} do
    listen(a)
    listen(b)

    assert {:ok, %{id: inv, room_id: ^id, from_name: "An", stake: 0}} =
             Invites.invite(a.id, b.id, id)

    assert_receive {:invite, %{id: ^inv}}
    assert %{id: ^inv} = Invites.pending(b.id)

    assert Invites.accept(b.id, inv) == {:ok, id}
    assert_receive {:invite_gone, ^inv}
    assert_receive {:invite_answer, :accepted, "Binh"}
    assert Invites.pending(b.id) == nil
    assert Invites.accept(b.id, inv) == {:error, :invite_expired}
  end

  test "decline and expiry are told to the inviter", %{a: a, b: b, id: id} do
    listen(a)
    {:ok, %{id: inv}} = Invites.invite(a.id, b.id, id)
    assert Invites.decline(b.id, inv) == :ok
    assert_receive {:invite_answer, :declined, "Binh"}

    {:ok, %{id: inv2}} = Invites.invite(a.id, b.id, id)
    # the 60 s timer's message, sent now
    send(Process.whereis(Invites), {:expire, b.id, inv2})
    assert_receive {:invite_answer, :expired, "Binh"}
    assert Invites.pending(b.id) == nil
  end

  test "one pending invite per target", %{a: a, b: b, id: id} do
    c = user("Cuong")
    id2 = room!()
    {:ok, _} = RoomServer.join(id2, c.id, "Cuong")
    {:ok, _} = Invites.invite(a.id, b.id, id)
    assert Invites.invite(c.id, b.id, id2) == {:error, :invite_pending}
  end

  test "refusals: self, offline, busy, invites off, not seated, game running", %{
    a: a,
    b: b,
    id: id
  } do
    assert Invites.invite(a.id, a.id, id) == {:error, :not_found}

    off = user("Offline")
    assert Invites.invite(a.id, off.id, id) == {:error, :not_online}

    busy = user("Busy")
    online(busy, "room", "zzz")
    assert Invites.invite(a.id, busy.id, id) == {:error, :target_busy}

    {:ok, _} = Accounts.set_accept_invites(b, false)
    assert Invites.invite(a.id, b.id, id) == {:error, :invites_off}
    {:ok, _} = Accounts.set_accept_invites(Accounts.get_user(b.id), true)

    stranger = user("Stranger")
    assert Invites.invite(stranger.id, b.id, id) == {:error, :not_in_room}
    assert Invites.invite(a.id, b.id, "no-room") == {:error, :room_not_found}

    d = user("Dung")
    {:ok, _} = RoomServer.join(id, d.id, "Dung")
    :ok = RoomServer.start_game(id, a.id)
    assert Invites.invite(a.id, b.id, id) == {:error, :game_in_progress}
  end

  test "at most 10 invites per minute per inviter", %{a: a, b: b, id: id} do
    for _ <- 1..10 do
      {:ok, %{id: inv}} = Invites.invite(a.id, b.id, id)
      :ok = Invites.decline(b.id, inv)
    end

    assert Invites.invite(a.id, b.id, id) == {:error, :invite_too_fast}
  end

  test "accepting re-checks the coins for the stake", %{a: a, b: b} do
    id = room!(stake: 200)
    {:ok, _} = RoomServer.join(id, a.id, "An")
    {:ok, %{id: inv}} = Invites.invite(a.id, b.id, id)
    assert Invites.accept(b.id, inv) == {:error, :not_enough_coins_to_join}
  end

  test "candidates: online, not in a room, not me; invites-off flagged", %{a: a, b: b} do
    busy = user("Busy")
    online(busy, "playing", "zzz")
    off = user("Quiet")
    online(off, "other")
    {:ok, _} = Accounts.set_accept_invites(off, false)

    list = Invites.candidates(a.id)
    ids = Enum.map(list, & &1.id)
    assert b.id in ids and off.id in ids
    refute a.id in ids or busy.id in ids
    assert %{invites_off: true} = Enum.find(list, &(&1.id == off.id))
    assert %{invites_off: false} = Enum.find(list, &(&1.id == b.id))
  end

  describe "private rooms (G11)" do
    test "host only, while waiting; hidden from the lobby list, listed for admins", %{
      a: a,
      b: b,
      id: id
    } do
      assert RoomServer.set_private(id, b.id, true) == {:error, :not_in_room}
      {:ok, _} = RoomServer.join(id, b.id, "Binh")
      assert RoomServer.set_private(id, b.id, true) == {:error, :not_host}
      assert RoomServer.set_private(id, a.id, "yes") == {:error, :unknown_command}
      assert :ok = RoomServer.set_private(id, a.id, true)

      assert %{private: true} = RoomServer.summary(id)
      refute Enum.any?(Lobby.public_rooms(), &(&1.id == id))
      assert Enum.any?(Lobby.list_rooms(), &(&1.id == id))
      assert Enum.any?(Admin.rooms(), &(&1.id == id))

      :ok = RoomServer.start_game(id, a.id)
      assert RoomServer.set_private(id, a.id, false) == {:error, :game_in_progress}
    end

    test "created private; still joinable by id (the link)" do
      id = room!(private: true)
      c = user("Cuong")
      assert {:ok, 0} = RoomServer.join(id, c.id, "Cuong")
      assert %{private: true} = RoomServer.view(id, c.id)
    end

    test "Room.set_private is pure" do
      room = Room.new("r") |> then(fn r -> elem(Room.join(r, 1, "A"), 1) end)
      assert {:ok, %{private: true}, [{:private_changed, true}]} = Room.set_private(room, 1, true)
    end
  end
end
