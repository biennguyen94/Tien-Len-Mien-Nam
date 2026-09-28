defmodule TienLenWeb.CoinHistoryLive do
  @moduledoc "The player's coin ledger (T19–T25), newest first, live."

  use TienLenWeb, :live_view

  alias TienLen.Economy
  alias TienLenWeb.Text

  @vn_offset 7 * 3600

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(TienLen.PubSub, Economy.all_topic())
    {:ok, socket |> assign(:page_title, "Lịch sử coin") |> load()}
  end

  defp load(socket),
    do: assign(socket, :rows, Economy.history(socket.assigns.current_user.id, 100))

  @impl true
  def handle_info({:coins_changed}, socket), do: {:noreply, load(socket)}
  def handle_info(_unexpected, socket), do: {:noreply, socket}

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp vn_time(utc),
    do: utc |> DateTime.add(@vn_offset, :second) |> Calendar.strftime("%d/%m/%Y %H:%M")

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <h1 class="text-xl font-bold">Lịch sử coin</h1>
      <p class="text-sm text-base-content/70">
        Coin chỉ dùng trong game: không nạp, không rút, không chuyển cho người khác.
      </p>

      <table id="coin-history" class="table table-zebra">
        <thead>
          <tr>
            <th>Thời gian</th>
            <th>Nội dung</th>
            <th class="text-right">Coin</th>
            <th class="text-right">Số dư</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} id={"tx-#{row.id}"}>
            <td class="text-sm">{vn_time(row.inserted_at)}</td>
            <td>
              {Text.coin_reason(row.reason)}
              <span :if={row.counterparty} class="text-base-content/60">
                ({if row.amount > 0, do: "từ", else: "cho"} {row.counterparty})
              </span>
            </td>
            <td class={[
              "text-right tabular-nums",
              if(row.amount > 0, do: "text-success", else: "text-error")
            ]}>
              {Text.signed_coins(row.amount)}
            </td>
            <td class="text-right tabular-nums">{Text.coins(row.balance_after)}</td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end
end
