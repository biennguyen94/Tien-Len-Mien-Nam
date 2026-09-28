defmodule TienLenWeb.LeaderboardLive do
  @moduledoc "Leaderboard: number of 1st places (A1), updated live after every game (Y5, Y8)."

  use TienLenWeb, :live_view

  alias TienLen.Stats

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Stats.subscribe()
    {:ok, socket |> assign(:page_title, "Bảng xếp hạng") |> load()}
  end

  defp load(socket) do
    socket
    |> assign(:rows, Stats.leaderboard(50))
    |> assign(:me, Stats.user_standing(socket.assigns.current_user.id))
  end

  @impl true
  def handle_info({:stats_updated}, socket), do: {:noreply, load(socket)}
  def handle_info(_unexpected, socket), do: {:noreply, socket}

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp percent(rate), do: "#{round(rate * 100)}%"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1 class="text-xl font-bold">Bảng xếp hạng</h1>
      <p class="text-sm text-base-content/70">Xếp theo số lần về nhất.</p>

      <p :if={@me} id="my-standing" class="card bg-base-200 p-3">
        Bạn đang hạng <strong>{@me.rank}</strong>: về nhất {@me.wins} lần / {@me.games} ván
        ({percent(@me.win_rate)}).
      </p>
      <p :if={!@me} id="my-standing" class="text-base-content/70">
        Bạn chưa chơi xong ván nào.
      </p>

      <p :if={@rows == []} id="no-rows" class="text-base-content/70">Chưa có ván nào được ghi.</p>

      <table :if={@rows != []} id="leaderboard" class="table table-zebra">
        <thead>
          <tr>
            <th>#</th>
            <th>Người chơi</th>
            <th class="text-right">Về nhất</th>
            <th class="text-right">Số ván</th>
            <th class="text-right">Tỉ lệ</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={row <- @rows}
            id={"row-#{row.user_id}"}
            class={row.user_id == @current_user.id && "font-bold bg-primary/10"}
          >
            <td>{row.rank}</td>
            <td>
              {row.display_name}
              <span class="text-xs text-base-content/60">@{row.username}</span>
            </td>
            <td class="text-right tabular-nums">{row.wins}</td>
            <td class="text-right tabular-nums">{row.games}</td>
            <td class="text-right tabular-nums">{percent(row.win_rate)}</td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end
end
