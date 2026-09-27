defmodule TienLen.RoomCapTest do
  # Changes global config: runs after the async tests, on its own.
  use ExUnit.Case, async: false

  alias TienLen.{Lobby, RoomServer}

  test "room creation is capped (spam guard)" do
    open = DynamicSupervisor.count_children(TienLen.RoomSupervisor).active
    previous = Application.get_env(:tien_len, :max_rooms)
    Application.put_env(:tien_len, :max_rooms, open + 2)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:tien_len, :max_rooms, previous),
        else: Application.delete_env(:tien_len, :max_rooms)
    end)

    {:ok, a} = Lobby.open_room()
    {:ok, b} = Lobby.open_room()
    assert Lobby.open_room() == {:error, :too_many_rooms}
    assert Lobby.create_room("p", "An") == {:error, :too_many_rooms}

    for id <- [a, b], pid = RoomServer.whereis(id), do: Process.exit(pid, :kill)
  end
end
