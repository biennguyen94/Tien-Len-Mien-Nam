defmodule TienLenWeb.FriendsLive do
  @moduledoc "Friends (FR1–FR5): requests, the list with who is online, and a search to add people."
  use TienLenWeb, :live_view

  alias TienLen.{Accounts, Friends, Presence}
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Presence.subscribe()
    {:ok, socket |> assign(page_title: "Bạn bè", q: "", results: []) |> load()}
  end

  defp load(socket) do
    me = socket.assigns.current_user.id
    online = Map.new(Presence.online_users(), &{&1.id, &1})

    assign(socket,
      friends: Friends.friends(me),
      incoming: Friends.incoming(me),
      outgoing: Friends.outgoing(me),
      online: online
    )
    |> search(socket.assigns.q)
  end

  defp search(socket, q) do
    me = socket.assigns.current_user.id

    results =
      q
      |> Accounts.search()
      |> Enum.reject(&(&1.id == me))
      |> Enum.map(&{&1, Friends.relation(me, &1.id)})

    assign(socket, q: q, results: results)
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket), do: {:noreply, search(socket, q)}

  def handle_event("friend", %{"do" => action, "id" => id}, socket) do
    me = socket.assigns.current_user.id

    with {id, ""} <- Integer.parse(id) do
      result =
        case action do
          "request" -> Friends.request(me, id)
          "accept" -> Friends.accept(me, id)
          "decline" -> Friends.decline(me, id)
          "cancel" -> Friends.cancel(me, id)
          "remove" -> Friends.remove(me, id)
          _ -> {:error, :unknown_command}
        end

      case result do
        {:error, reason} -> {:noreply, socket |> put_flash(:error, Text.reason(reason)) |> load()}
        _ok -> {:noreply, load(socket)}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:friends_changed}, socket), do: {:noreply, load(socket)}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, :online, Map.new(Presence.online_users(), &{&1.id, &1}))}

  def handle_info(_msg, socket), do: {:noreply, socket}

  attr :user, :map, required: true

  defp who(assigns) do
    ~H"""
    <.link navigate={~p"/nguoi-choi/#{@user.username}"} class="link link-hover flex-1 truncate">
      {Text.avatar(@user)} {@user.display_name}
      <span class="text-xs text-base-content/60">@{@user.username}</span>
    </.link>
    """
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
      <h1 class="text-xl font-bold">Bạn bè</h1>

      <section :if={@incoming != []} id="incoming" class="card bg-base-200 p-3 space-y-2">
        <h2 class="font-semibold text-sm">Lời mời kết bạn</h2>
        <ul class="divide-y divide-base-300">
          <li :for={u <- @incoming} id={"incoming-#{u.id}"} class="py-2 flex items-center gap-2">
            <.who user={u} />
            <button
              phx-click="friend"
              phx-value-do="accept"
              phx-value-id={u.id}
              class="btn btn-xs btn-primary"
            >
              Đồng ý
            </button>
            <button phx-click="friend" phx-value-do="decline" phx-value-id={u.id} class="btn btn-xs">
              Từ chối
            </button>
          </li>
        </ul>
      </section>

      <section id="friends" class="card bg-base-200 p-3 space-y-2">
        <h2 class="font-semibold text-sm">Bạn bè ({length(@friends)})</h2>
        <p :if={@friends == []} class="text-sm text-base-content/60">
          Chưa có bạn bè. Tìm người chơi bên dưới hoặc mở hồ sơ của họ để kết bạn.
        </p>
        <ul class="divide-y divide-base-300">
          <li :for={u <- @friends} id={"friend-#{u.id}"} class="py-2 flex items-center gap-2">
            <.who user={u} />
            <span :if={@online[u.id]} class="badge badge-success badge-sm">
              {TienLenWeb.Social.place_label(@online[u.id].place)}
            </span>
            <span :if={!@online[u.id]} class="text-xs text-base-content/50">offline</span>
            <button :if={@online[u.id]} phx-click="social:open" phx-value-id={u.id} class="btn btn-xs">
              Nhắn
            </button>
            <button
              phx-click="friend"
              phx-value-do="remove"
              phx-value-id={u.id}
              class="btn btn-xs btn-ghost"
              data-confirm="Hủy kết bạn?"
            >
              ✕
            </button>
          </li>
        </ul>
      </section>

      <section :if={@outgoing != []} id="outgoing" class="card bg-base-200 p-3 space-y-2">
        <h2 class="font-semibold text-sm">Đang chờ trả lời</h2>
        <ul class="divide-y divide-base-300">
          <li :for={u <- @outgoing} id={"outgoing-#{u.id}"} class="py-2 flex items-center gap-2">
            <.who user={u} />
            <button phx-click="friend" phx-value-do="cancel" phx-value-id={u.id} class="btn btn-xs">
              Hủy
            </button>
          </li>
        </ul>
      </section>

      <section id="find" class="card bg-base-200 p-3 space-y-2">
        <h2 class="font-semibold text-sm">Tìm người chơi</h2>
        <form id="search-form" phx-change="search" phx-submit="search">
          <input
            name="q"
            value={@q}
            placeholder="Tên hoặc tài khoản (ít nhất 2 ký tự)"
            autocomplete="off"
            phx-debounce="300"
            class="input input-bordered input-sm w-full"
          />
        </form>
        <ul class="divide-y divide-base-300">
          <li :for={{u, rel} <- @results} id={"result-#{u.id}"} class="py-2 flex items-center gap-2">
            <.who user={u} />
            <button
              :if={rel in [:none, :incoming]}
              phx-click="friend"
              phx-value-do="request"
              phx-value-id={u.id}
              class="btn btn-xs btn-primary"
            >
              {if rel == :incoming, do: "Đồng ý kết bạn", else: "Kết bạn"}
            </button>
            <span :if={rel == :friends} class="badge badge-success badge-sm">Bạn bè</span>
            <span :if={rel == :outgoing} class="text-xs text-base-content/60">đã gửi lời mời</span>
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
