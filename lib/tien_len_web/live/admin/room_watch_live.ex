defmodule TienLenWeb.Admin.RoomWatchLive do
  @moduledoc "Admin watch view of a room with every hand (AD7, F6); remove a player; close."
  use TienLenWeb, :live_view
  import TienLenWeb.AdminComponents
  import TienLenWeb.CardComponents
  alias TienLen.Admin
  alias TienLenWeb.Text

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: TienLen.RoomServer.subscribe(id)
    {:ok, socket |> assign(room_id: id, page_title: "Xem phòng #{id}") |> load()}
  end

  defp load(socket) do
    case Admin.watch(socket.assigns.current_user.id, socket.assigns.room_id) do
      {:ok, view} ->
        assign(socket, :view, view)

      error ->
        socket |> put_flash(:error, error_text(error)) |> push_navigate(to: ~p"/quan-tri/phong")
    end
  end

  @impl true
  def handle_info({:room_updated, _id, _v, [{:closed_by_admin}]}, socket),
    do:
      {:noreply,
       socket |> put_flash(:info, "Phòng đã đóng") |> push_navigate(to: ~p"/quan-tri/phong")}

  def handle_info({:room_updated, _id, _v, _events}, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("kick", %{"seat" => seat}, socket) do
    player_id = socket.assigns.view.seat_players[String.to_integer(seat)]

    case Admin.kick(socket.assigns.current_user.id, socket.assigns.room_id, player_id) do
      :ok -> {:noreply, socket |> put_flash(:info, "Đã mời người chơi ra khỏi phòng") |> load()}
      error -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event("close", _params, socket) do
    case Admin.close_room(socket.assigns.current_user.id, socket.assigns.room_id) do
      :ok ->
        {:noreply,
         socket |> put_flash(:info, "Đã đóng phòng") |> push_navigate(to: ~p"/quan-tri/phong")}

      error ->
        {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def render(%{view: nil} = assigns), do: ~H""

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} announcement={@announcement} wide>
      <.admin_nav active={:rooms} />
      <h1 class="text-xl font-bold">
        Phòng <span class="font-mono">{@room_id}</span>
        <span class="badge">{if @view.stake == 0,
          do: "Chơi vui",
          else: "Cược " <> Text.coins(@view.stake)}</span>
        <span class="badge">{if @view.status == :playing, do: "Đang chơi", else: "Đang chờ"}</span>
      </h1>
      <button
        id="close-room"
        phx-click="close"
        class="btn btn-sm btn-error"
        data-confirm="Đóng phòng? Ván đang chơi sẽ bị hủy, không tính coin."
      >Đóng phòng</button>

      <div :if={@view.game} id="centre" class="card bg-success/15 p-3">
        <p class="text-sm">Trên bàn:</p>
        <div :if={@view.game.centre} class="flex gap-1">
          <.card :for={c <- @view.game.centre.cards} card={c} class="w-10" />
        </div>
      </div>

      <ul id="watch-seats" class="space-y-3">
        <li
          :for={p <- @view.players}
          id={"watch-seat-#{p.seat}"}
          class={[
            "card bg-base-200 p-3",
            @view.game && @view.game.current == p.seat && "ring-2 ring-primary"
          ]}
        >
          <div class="flex items-center justify-between gap-2">
            <span class="font-semibold">
              <span :if={p.host}>👑</span> {p.name}
              <span :if={!p.connected} class="badge badge-ghost badge-xs">mất kết nối</span>
              <span :if={@view.balances[p.seat]} class="text-xs">🪙 {Text.coins(@view.balances[p.seat])}</span>
            </span>
            <button
              phx-click="kick"
              phx-value-seat={p.seat}
              class="btn btn-xs btn-warning"
              data-confirm="Mời người này ra khỏi phòng?"
            >Mời ra</button>
          </div>
          <div
            :if={@view.game && Map.has_key?(@view.game.hands, p.seat)}
            class="flex flex-wrap gap-1 mt-2"
          >
            <.card :for={c <- @view.game.hands[p.seat]} card={c} class="w-10" />
          </div>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
