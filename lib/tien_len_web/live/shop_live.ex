defmodule TienLenWeb.ShopLive do
  @moduledoc """
  The shop (SH1–SH3): card backs and table themes, bought once with coins and equipped for
  free. Prices, ownership and the balance are all checked by `TienLen.Shop`; this page only
  sends item ids.
  """

  use TienLenWeb, :live_view

  import TienLenWeb.CardComponents

  alias TienLen.Shop
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:page_title, "Cửa hàng") |> load()}
  end

  defp load(socket),
    do: assign(socket, :owned, Shop.owned(socket.assigns.current_user.id))

  @impl true
  def handle_event("buy", %{"id" => id}, socket) do
    case Shop.buy(socket.assigns.current_user.id, id) do
      {:ok, _balance} ->
        # a new item is equipped right away
        socket = load(socket)
        equip(socket, id, "Đã mua và dùng #{Shop.item(id).name}")

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
  end

  def handle_event("equip", %{"id" => id}, socket),
    do: equip(socket, id, "Đang dùng #{(Shop.item(id) || %{name: "?"}).name}")

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp equip(socket, id, message) do
    case Shop.equip(socket.assigns.current_user, id) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:current_user, %{user | coins: socket.assigns.current_user.coins})
         |> put_flash(:info, message)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
    >
      <h1 class="text-xl font-bold">🛍️ Cửa hàng</h1>
      <p class="text-sm text-base-content/70">
        Mua một lần, dùng mãi. Chỉ để trang trí, không giúp thắng ván nào. Không hoàn tiền.
      </p>

      <section id="shop-backs" class="space-y-2">
        <h2 class="font-semibold">Mặt sau lá bài</h2>
        <p class="text-xs text-base-content/60">Mọi người trong phòng (và người xem) đều thấy.</p>
        <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
          <.item_card
            :for={item <- Shop.items(:card_back)}
            item={item}
            owned={MapSet.member?(@owned, item.id)}
            equipped={Shop.equipped(@current_user, :card_back) == item.id}
            coins={@current_user.coins}
          >
            <.card_back back={item.id} class="w-12 rounded-md shadow text-xl" />
          </.item_card>
        </div>
      </section>

      <section id="shop-tables" class="space-y-2">
        <h2 class="font-semibold">Bàn chơi</h2>
        <p class="text-xs text-base-content/60">Chỉ bạn thấy bàn của mình.</p>
        <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
          <.item_card
            :for={item <- Shop.items(:table)}
            item={item}
            owned={MapSet.member?(@owned, item.id)}
            equipped={Shop.equipped(@current_user, :table) == item.id}
            coins={@current_user.coins}
          >
            <div class={[
              "relative w-full h-16 rounded-box flex items-center justify-center text-sm font-semibold",
              "felt-" <> item.id,
              item.price > 0 && "felt-custom"
            ]}>
              <p>{item.icon}</p>
            </div>
          </.item_card>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :item, :map, required: true
  attr :owned, :boolean, required: true
  attr :equipped, :boolean, required: true
  attr :coins, :integer, required: true
  slot :inner_block, required: true

  defp item_card(assigns) do
    ~H"""
    <div
      id={"item-#{@item.id}"}
      class={[
        "card bg-base-200 p-2 flex flex-col items-center gap-2 text-center",
        @equipped && "ring-2 ring-primary"
      ]}
    >
      {render_slot(@inner_block)}
      <p class="text-sm font-semibold leading-tight">{@item.name}</p>
      <%= cond do %>
        <% @equipped -> %>
          <span class="badge badge-primary">Đang dùng</span>
        <% @owned -> %>
          <button phx-click="equip" phx-value-id={@item.id} class="btn btn-sm btn-outline">
            Dùng
          </button>
        <% true -> %>
          <button
            phx-click="buy"
            phx-value-id={@item.id}
            class="btn btn-sm btn-warning whitespace-nowrap"
            disabled={@coins < @item.price}
            data-confirm={"Mua #{@item.name} với #{Text.coins(@item.price)} coin?"}
          >
            🪙 {Text.coins(@item.price)}
          </button>
      <% end %>
    </div>
    """
  end
end
