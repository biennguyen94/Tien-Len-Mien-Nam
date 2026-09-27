defmodule TienLenWeb.LobbyLive do
  @moduledoc """
  Lobby: set a display name, see the rooms (live), create or join a room (RULES T13).
  """

  use TienLenWeb, :live_view

  alias TienLen.Lobby
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe()

    {:ok,
     socket
     |> assign(:page_title, "Sảnh")
     |> assign(:rooms, Lobby.list_rooms())
     |> assign(:editing_name, false)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    case Lobby.open_room() do
      {:ok, id} -> {:noreply, push_navigate(socket, to: ~p"/phong/#{id}")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
  end

  def handle_event("edit_name", _params, socket),
    do: {:noreply, assign(socket, :editing_name, true)}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:lobby_updated, _id}, socket),
    do: {:noreply, assign(socket, :rooms, Lobby.list_rooms())}

  def handle_info({:room_closed, _id}, socket),
    do: {:noreply, assign(socket, :rooms, Lobby.list_rooms())}

  def handle_info(_unexpected, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section :if={@player_name == nil or @editing_name} id="name-form" class="card bg-base-200 p-6">
        <h1 class="text-xl font-bold mb-2">Chào bạn! Bạn tên gì?</h1>
        <form action={~p"/ten"} method="post" class="flex gap-2">
          <input type="hidden" name="_csrf_token" value={Plug.CSRFProtection.get_csrf_token()} />
          <input type="hidden" name="return_to" value="/" />
          <input
            type="text"
            name="name"
            value={@player_name}
            maxlength="20"
            required
            placeholder="Tên hiển thị"
            class="input input-bordered flex-1"
            autofocus
          />
          <button type="submit" class="btn btn-primary">Lưu</button>
        </form>
      </section>

      <section :if={@player_name != nil and not @editing_name} class="space-y-4">
        <div class="flex items-center justify-between gap-2">
          <p>
            Xin chào <strong id="player-name">{@player_name}</strong>
            <button phx-click="edit_name" class="btn btn-ghost btn-xs">đổi tên</button>
          </p>
          <button id="create-room" phx-click="create" class="btn btn-primary">Tạo phòng</button>
        </div>

        <h2 class="text-lg font-semibold">Các phòng</h2>
        <p :if={@rooms == []} id="no-rooms" class="text-base-content/70">
          Chưa có phòng nào. Hãy tạo phòng mới!
        </p>

        <ul :if={@rooms != []} id="rooms" class="divide-y divide-base-300 rounded-box bg-base-200">
          <li :for={room <- @rooms} id={"room-#{room.id}"} class="flex items-center gap-3 p-3">
            <span class="font-mono text-sm">{room.id}</span>
            <span class="flex-1 truncate">Chủ phòng: {room.host_name || "—"}</span>
            <span class="tabular-nums">{room.players}/{room.max_players}</span>
            <span class={[
              "badge",
              if(room.status == :playing, do: "badge-warning", else: "badge-success")
            ]}>
              {if room.status == :playing, do: "Đang chơi", else: "Đang chờ"}
            </span>
            <.link
              :if={room.joinable}
              navigate={~p"/phong/#{room.id}"}
              class="btn btn-sm btn-outline"
            >
              Vào
            </.link>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
