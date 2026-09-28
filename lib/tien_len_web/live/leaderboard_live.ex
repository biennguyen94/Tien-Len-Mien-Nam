defmodule TienLenWeb.LeaderboardLive do
  @moduledoc """
  Leaderboards, updated live (Y8): by number of 1st places (A1, default tab) and by coins
  ("Giàu nhất", `?tab=giau`, T19).
  """

  use TienLenWeb, :live_view

  alias TienLen.{Economy, Stats}
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Stats.subscribe()
      Phoenix.PubSub.subscribe(TienLen.PubSub, Economy.all_topic())
    end

    {:ok, assign(socket, :page_title, "Bảng xếp hạng")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] == "giau", do: :richest, else: :wins
    {:noreply, socket |> assign(:tab, tab) |> load()}
  end

  defp load(socket) do
    socket
    |> assign(:rows, Stats.leaderboard(50))
    |> assign(:me, Stats.user_standing(socket.assigns.current_user.id))
    |> assign(:richest, if(socket.assigns.tab == :richest, do: Economy.richest(50), else: []))
  end

  @impl true
  def handle_info({:stats_updated}, socket), do: {:noreply, load(socket)}
  def handle_info({:coins_changed}, socket), do: {:noreply, load(socket)}
  def handle_info(_unexpected, socket), do: {:noreply, socket}

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp percent(rate), do: "#{round(rate * 100)}%"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user} announcement={@announcement}>
      <h1 class="text-xl font-bold">Bảng xếp hạng</h1>
      <div role="tablist" class="tabs tabs-box w-fit">
        <.link
          patch={~p"/bang-xep-hang"}
          id="tab-wins"
          role="tab"
          class={["tab", @tab == :wins && "tab-active"]}
        >
          Về nhất
        </.link>
        <.link
          patch={~p"/bang-xep-hang?tab=giau"}
          id="tab-richest"
          role="tab"
          class={["tab", @tab == :richest && "tab-active"]}
        >
          Giàu nhất
        </.link>
      </div>

      <table :if={@tab == :richest} id="richest" class="table table-zebra">
        <thead>
          <tr>
            <th>#</th>
            <th>Người chơi</th>
            <th class="text-right">Coin</th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={row <- @richest}
            id={"rich-#{row.user_id}"}
            class={row.user_id == @current_user.id && "font-bold bg-primary/10"}
          >
            <td>{row.rank}</td>
            <td>
              {row.display_name} <span class="text-xs text-base-content/60">@{row.username}</span>
            </td>
            <td class="text-right tabular-nums">🪙 {Text.coins(row.coins)}</td>
          </tr>
        </tbody>
      </table>

      <div :if={@tab == :wins} class="space-y-4">
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
      </div>
    </Layouts.app>
    """
  end
end
