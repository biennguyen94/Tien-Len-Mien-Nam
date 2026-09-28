defmodule TienLenWeb.HistoryLive do
  @moduledoc "The logged-in player's recent games (Phase 13, Y8)."

  use TienLenWeb, :live_view

  alias TienLen.Stats

  # Vietnam has no daylight saving time: UTC+7 all year.
  @vn_offset 7 * 3600

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Stats.subscribe()
    {:ok, socket |> assign(:page_title, "Lịch sử") |> load()}
  end

  defp load(socket), do: assign(socket, :games, Stats.history(socket.assigns.current_user.id, 20))

  @impl true
  def handle_info({:stats_updated}, socket), do: {:noreply, load(socket)}
  def handle_info(_unexpected, socket), do: {:noreply, socket}

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp vn_time(utc),
    do: utc |> DateTime.add(@vn_offset, :second) |> Calendar.strftime("%d/%m/%Y %H:%M")

  # Place label for a player in a game of n players (instant-win losers share place 2).
  defp place_label(%{place: 1}, _game), do: "Nhất"
  defp place_label(%{place: 2}, %{instant_win: true}), do: "Thua (tới trắng)"
  defp place_label(%{place: p}, %{player_count: n}) when p == n, do: "Bét"
  defp place_label(%{place: 2}, _game), do: "Nhì"
  defp place_label(%{place: 3}, _game), do: "Ba"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} announcement={@announcement}>
      <h1 class="text-xl font-bold">Lịch sử ván chơi</h1>
      <p :if={@games == []} id="no-games" class="text-base-content/70">Bạn chưa chơi xong ván nào.</p>

      <ul :if={@games != []} id="history" class="space-y-2">
        <li :for={g <- @games} id={"game-#{g.id}"} class="card bg-base-200 p-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <span class="text-sm text-base-content/70">{vn_time(g.finished_at)} · {g.player_count} người</span>
            <span class={["badge", if(g.won, do: "badge-success", else: "badge-ghost")]}>
              {place_label(g, g)}
            </span>
          </div>
          <p class="text-sm mt-1">
            <span :for={p <- g.players} class={["mr-3", p.me && "font-semibold"]}>
              {place_label(p, g)}: {p.display_name}<span :if={p.removed}> (bị loại)</span>
            </span>
            <span :if={g.instant_win} class="badge badge-warning badge-sm">tới trắng</span>
          </p>
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
