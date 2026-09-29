defmodule TienLenWeb.ShameLive do
  @moduledoc """
  "Tường xấu hổ" (XH1–XH3): the top 3 of each shame title for this week (default) or last
  week (`?tab=tuan-truoc`), updated live when a game is recorded.
  """

  use TienLenWeb, :live_view

  alias TienLen.{Seasons, Shame, Stats}
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Stats.subscribe()
    {:ok, assign(socket, :page_title, "Tường xấu hổ")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] == "tuan-truoc", do: :last_week, else: :week
    {:noreply, socket |> assign(:tab, tab) |> load()}
  end

  defp load(socket) do
    monday = Seasons.week_start()
    monday = if socket.assigns.tab == :week, do: monday, else: Date.add(monday, -7)
    assign(socket, monday: monday, standings: Shame.standings(monday))
  end

  @impl true
  def handle_info({:stats_updated}, socket), do: {:noreply, load(socket)}
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp value(%{id: "pass"}, row), do: "#{row.value}% (#{row.games} ván)"
  defp value(title, row), do: "#{row.value} #{title.unit}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h1 class="text-xl font-bold">🙈 Tường xấu hổ</h1>
        <.link navigate={~p"/bang-xep-hang"} class="link text-sm">← Bảng xếp hạng</.link>
      </div>
      <p class="text-sm text-base-content/70">
        Danh hiệu "vinh dự" tuần {Seasons.label(@monday)}, tính từ các ván đã ghi (không tính ván có máy).
        Người đứng đầu mỗi danh hiệu được đeo nó cạnh tên ở bàn chơi cả tuần. Chỉ để vui, không mất coin.
      </p>
      <div role="tablist" class="tabs tabs-box w-fit">
        <.link
          patch={~p"/tuong-xau-ho"}
          id="tab-week"
          role="tab"
          class={["tab", @tab == :week && "tab-active"]}
        >
          Tuần này
        </.link>
        <.link
          patch={~p"/tuong-xau-ho?tab=tuan-truoc"}
          id="tab-last-week"
          role="tab"
          class={["tab", @tab == :last_week && "tab-active"]}
        >
          Tuần trước
        </.link>
      </div>

      <div class="grid gap-3 sm:grid-cols-2">
        <section
          :for={{title, rows} <- @standings}
          id={"title-#{title.id}"}
          class="card bg-base-200 p-3 space-y-2"
        >
          <h2 class="font-bold">
            <span class="text-2xl">{title.emoji}</span> {title.name}
          </h2>
          <p class="text-xs text-base-content/60">
            {String.capitalize(title.what)}{if title.id == "pass",
              do: " (ít nhất #{Shame.min_moves()} lượt đi trong tuần)"}
          </p>
          <p :if={rows == []} class="text-sm text-base-content/50">Chưa ai "đủ trình".</p>
          <ol :if={rows != []} class="space-y-1 text-sm">
            <li :for={{row, i} <- Enum.with_index(rows, 1)} class="flex items-center gap-2">
              <span class="w-5 text-right tabular-nums">{i}.</span>
              <.link navigate={~p"/nguoi-choi/#{row.username}"} class="link flex-1 min-w-0 truncate">
                {Text.avatar(row)} {row.display_name}
              </.link>
              <span class="tabular-nums whitespace-nowrap">{value(title, row)}</span>
            </li>
          </ol>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
