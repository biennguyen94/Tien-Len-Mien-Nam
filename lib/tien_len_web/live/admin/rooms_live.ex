defmodule TienLenWeb.Admin.RoomsLive do
  @moduledoc "Admin: open rooms (AD6)."
  use TienLenWeb, :live_view
  import TienLenWeb.AdminComponents
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TienLen.Lobby.subscribe()
    {:ok, socket |> assign(:page_title, "Phòng") |> load()}
  end

  defp load(socket), do: assign(socket, :rooms, TienLen.Admin.rooms())

  @impl true
  def handle_event("close", %{"id" => id}, socket) do
    case TienLen.Admin.close_room(socket.assigns.current_user.id, id) do
      :ok -> {:noreply, socket |> put_flash(:info, "Đã đóng phòng #{id}") |> load()}
      error -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({event, _id}, socket) when event in [:lobby_updated, :room_closed],
    do: {:noreply, load(socket)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
      wide
    >
      <h1 class="text-xl font-bold">Phòng đang mở</h1>
      <.admin_nav active={:rooms} />
      <p :if={@rooms == []} class="text-base-content/70">Không có phòng nào.</p>
      <%!-- M3: a wide table scrolls inside its box on phones, never the page --%>
      <div :if={@rooms != []} class="overflow-x-auto">
        <table id="admin-rooms" class="table table-zebra">
          <thead>
            <tr>
              <th>Mã</th><th>Chủ phòng</th><th>Người</th><th>Cược</th><th>Trạng thái</th><th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={r <- @rooms} id={"aroom-#{r.id}"}>
              <td class="font-mono">{r.id}</td>
              <td>{r.host_name || "—"}</td>
              <td>{r.players}/{r.max_players}</td>
              <td>
                {if r.stake == 0, do: "Chơi vui", else: Text.coins(r.stake)}
                <span :if={r.private} class="badge badge-info badge-xs">riêng tư</span>
              </td>
              <td>{if r.status == :playing, do: "Đang chơi", else: "Đang chờ"}</td>
              <td class="flex gap-2">
                <.link navigate={~p"/quan-tri/phong/#{r.id}"} class="btn btn-xs">Xem</.link>
                <button
                  phx-click="close"
                  phx-value-id={r.id}
                  class="btn btn-xs btn-error"
                  data-confirm="Đóng phòng? Ván đang chơi sẽ bị hủy, không tính coin."
                >Đóng</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
