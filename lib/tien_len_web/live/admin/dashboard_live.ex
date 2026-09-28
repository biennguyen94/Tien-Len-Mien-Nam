defmodule TienLenWeb.Admin.DashboardLive do
  @moduledoc "Admin dashboard (AD3)."
  use TienLenWeb, :live_view
  import TienLenWeb.AdminComponents
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(5_000, :refresh)
    {:ok, socket |> assign(:page_title, "Quản trị") |> load()}
  end

  defp load(socket), do: assign(socket, :stats, TienLen.Admin.dashboard())

  @impl true
  def handle_info(:refresh, socket), do: {:noreply, load(socket)}
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
      <h1 class="text-xl font-bold">Quản trị</h1>
      <.admin_nav active={:dashboard} />
      <div id="dashboard" class="stats stats-vertical sm:stats-horizontal shadow w-full flex-wrap">
        <div class="stat">
          <div class="stat-title">Tài khoản</div><div id="stat-users" class="stat-value">
            {@stats.users}
          </div>
          <div class="stat-desc">
            +{@stats.registrations_today} hôm nay · {@stats.locked} bị khóa · {@stats.admins} admin
          </div>
        </div>
        <div class="stat">
          <div class="stat-title">Đang online</div><div id="stat-online" class="stat-value">
            {@stats.online}
          </div>
          <div class="stat-desc">người có trang đang mở</div>
        </div>
        <div class="stat">
          <div class="stat-title">Phòng đang mở</div><div id="stat-rooms" class="stat-value">
            {@stats.rooms}
          </div>
          <div class="stat-desc">
            {@stats.rooms_playing} đang chơi · {@stats.players_in_rooms} người trong phòng
          </div>
        </div>
        <div class="stat">
          <div class="stat-title">Ván</div><div id="stat-games" class="stat-value">
            {@stats.games_today}
          </div>
          <div class="stat-desc">hôm nay · {@stats.games_7_days} trong 7 ngày</div>
        </div>
        <div class="stat">
          <div class="stat-title">Coin lưu hành</div><div id="stat-coins" class="stat-value">
            {Text.coins(@stats.coins_in_circulation)}
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
