defmodule TienLenWeb.Admin.GamesLive do
  @moduledoc "Admin: recent games with their coin settlements (AD8)."
  use TienLenWeb, :live_view
  import TienLenWeb.AdminComponents
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: TienLen.Stats.subscribe()
    {:ok, socket |> assign(:page_title, "Ván") |> load()}
  end

  defp load(socket), do: assign(socket, :games, TienLen.Admin.games(50))

  @impl true
  def handle_info({:stats_updated}, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

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
      <h1 class="text-xl font-bold">Ván gần đây</h1>
      <.admin_nav active={:games} />
      <ul id="admin-games" class="space-y-2">
        <li
          :for={g <- @games}
          id={"agame-#{g.game.id}"}
          class="card bg-base-200 p-3 text-sm space-y-1"
        >
          <p>
            {vn_time(g.game.finished_at)} · phòng <span class="font-mono">{g.game.room_id}</span>
            · {g.game.player_count} người
            <span :if={g.game.instant_win} class="badge badge-warning badge-sm">tới trắng</span>
            <.link :if={g.game.replay} navigate={~p"/van/#{g.game.id}"} class="link ml-2">
              ▶ Xem lại
            </.link>
          </p>
          <p>
            <span :for={p <- g.players} class="mr-3">#{p.place} {p.user.display_name}<span :if={
              p.removed
            }> (bị loại)</span></span>
          </p>
          <p :for={t <- g.transfers} class="text-base-content/70">
            🪙 {Text.coin_reason(t.reason)}: {t.from} → {t.to} {Text.coins(t.amount)}
          </p>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
