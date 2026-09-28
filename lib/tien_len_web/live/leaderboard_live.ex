defmodule TienLenWeb.LeaderboardLive do
  @moduledoc """
  Leaderboards, updated live (Y8): by number of 1st places (A1, default tab), by coins
  ("Giàu nhất", `?tab=giau`, T19), and the weekly season ("Tuần này" `?tab=tuan`, "Tuần
  trước" `?tab=tuan-truoc`, S1–S3).
  """

  use TienLenWeb, :live_view

  alias TienLen.{Economy, Seasons, Stats}
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
    tab =
      case params["tab"] do
        "giau" -> :richest
        "tuan" -> :week
        "tuan-truoc" -> :last_week
        _ -> :wins
      end

    {:noreply, socket |> assign(:tab, tab) |> load()}
  end

  defp load(%{assigns: %{tab: tab}} = socket) when tab in [:week, :last_week] do
    monday = Seasons.week_start()
    monday = if tab == :week, do: monday, else: Date.add(monday, -7)

    socket
    |> assign(:monday, monday)
    |> assign(:rows, Seasons.standings(monday))
    |> assign(:rewards, Seasons.rewards())
    |> assign(:paid, if(tab == :last_week, do: Seasons.paid(monday), else: []))
    |> assign(:me, nil)
    |> assign(:richest, [])
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
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
    >
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
          patch={~p"/bang-xep-hang?tab=tuan"}
          id="tab-week"
          role="tab"
          class={["tab", @tab == :week && "tab-active"]}
        >
          Tuần này
        </.link>
        <.link
          patch={~p"/bang-xep-hang?tab=tuan-truoc"}
          id="tab-last-week"
          role="tab"
          class={["tab", @tab == :last_week && "tab-active"]}
        >
          Tuần trước
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

      <%!-- M3: a wide table scrolls inside its box on phones, never the page --%>
      <div :if={@tab == :richest} class="overflow-x-auto">
        <table id="richest" class="table table-zebra table-sm sm:table-md">
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
              <td><.player_link row={row} /></td>
              <td class="text-right tabular-nums">🪙 {Text.coins(row.coins)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        :if={@tab in [:week, :last_week]}
        id="season"
        class="card bg-base-200 p-3 space-y-1 text-sm"
      >
        <p>
          Mùa tuần <strong>{Seasons.label(@monday)}</strong>
          (thứ Hai 00:00 – Chủ nhật 24:00, giờ Việt Nam). Xếp theo số lần về nhất trong tuần.
        </p>
        <p>
          Thưởng cuối tuần cho 3 hạng đầu (cần ít nhất 1 lần về nhất):
          🥇 {Text.coins(Enum.at(@rewards, 0))} · 🥈 {Text.coins(Enum.at(@rewards, 1))} · 🥉 {Text.coins(
            Enum.at(@rewards, 2)
          )} coin.
        </p>
        <ul :if={@tab == :last_week and @paid != []} id="season-paid">
          <li :for={p <- @paid}>
            Đã trao: <strong>{p.display_name}</strong> +{Text.coins(p.amount)} coin
          </li>
        </ul>
        <p :if={@tab == :last_week and @paid == []} class="text-base-content/60">
          Chưa có phần thưởng nào được trao cho tuần này.
        </p>
      </div>

      <div :if={@tab != :richest} class="space-y-4">
        <p :if={@tab == :wins} class="text-sm text-base-content/70">Xếp theo số lần về nhất.</p>

        <p :if={@me && @tab == :wins} id="my-standing" class="card bg-base-200 p-3">
          Bạn đang hạng <strong>{@me.rank}</strong>: về nhất {@me.wins} lần / {@me.games} ván
          ({percent(@me.win_rate)}).
        </p>
        <p :if={!@me && @tab == :wins} id="my-standing" class="text-base-content/70">
          Bạn chưa chơi xong ván nào.
        </p>

        <p :if={@rows == []} id="no-rows" class="text-base-content/70">Chưa có ván nào được ghi.</p>

        <%!-- M3: a wide table scrolls inside its box on phones, never the page --%>
        <div :if={@rows != []} class="overflow-x-auto">
          <table id="leaderboard" class="table table-zebra table-sm sm:table-md">
            <thead>
              <tr>
                <th>#</th>
                <th>Người chơi</th>
                <th class="text-right">Về nhất</th>
                <th class="text-right hidden sm:table-cell">Số ván</th>
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
                <td><.player_link row={row} /></td>
                <td class="text-right tabular-nums">{row.wins}</td>
                <td class="text-right tabular-nums hidden sm:table-cell">{row.games}</td>
                <td class="text-right tabular-nums">{percent(row.win_rate)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :row, :map, required: true

  defp player_link(assigns) do
    ~H"""
    <.link navigate={~p"/nguoi-choi/#{@row.username}"} class="link link-hover">
      {Text.avatar(@row[:avatar])} {@row.display_name}
    </.link>
    <span class="text-xs text-base-content/60 block sm:inline">@{@row.username}</span>
    """
  end
end
