defmodule TienLenWeb.Social do
  @moduledoc """
  Things that follow a logged-in player on every page (G6–G8): presence tracking, the private
  chat panel and the invite popup.

  `attach/1` is called from `TienLenWeb.UserAuth` for every LiveView. It tracks the page in
  `TienLen.Presence` (place `"other"`; the lobby and the table move it) and attaches hooks for
  the `"social:*"` events and the private-chat / invite messages on the user topic. The layout
  renders `panel/1` from the `@social` assign.
  """

  use TienLenWeb, :html

  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, put_flash: 3, push_navigate: 2]

  alias TienLen.{Chat, Invites, Presence}
  alias TienLenWeb.Text

  @doc "Assigns `@social` and, when connected, tracks the page and attaches the hooks."
  def attach(%{assigns: %{current_user: %{id: _} = user}} = socket) do
    social = %{
      open: false,
      tab: :chats,
      peer: nil,
      lines: [],
      convs: [],
      online: [],
      invite: nil,
      sent: 0
    }

    if connected?(socket) do
      Presence.track_page(self(), user)
      social = %{social | convs: Chat.conversations(user.id), invite: Invites.pending(user.id)}

      socket
      |> assign(:social, social)
      |> attach_hook(:social_events, :handle_event, &event/3)
      |> attach_hook(:social_info, :handle_info, &info/2)
    else
      assign(socket, :social, social)
    end
  end

  def attach(socket), do: assign(socket, :social, nil)

  # -- events -----------------------------------------------------------------------

  defp event("social:toggle", _params, socket) do
    open = !socket.assigns.social.open
    {:halt, socket |> put_social(open: open) |> refresh()}
  end

  defp event("social:tab", %{"tab" => tab}, socket) do
    tab = if tab == "online", do: :online, else: :chats
    {:halt, socket |> put_social(tab: tab, peer: nil) |> refresh()}
  end

  defp event("social:open", %{"id" => id} = params, socket) do
    with {id, ""} <- Integer.parse(to_string(id)),
         true <- id != me(socket) do
      name = peer_name(socket, id) || params["name"] || "?"
      Chat.mark_read(me(socket), id)

      {:halt,
       socket
       |> put_social(open: true, tab: :chats, peer: %{id: id, name: name})
       |> put_social(lines: Chat.conversation(me(socket), id))
       |> refresh()}
    else
      _ -> {:halt, socket}
    end
  end

  defp event("social:back", _params, socket),
    do: {:halt, socket |> put_social(peer: nil) |> refresh()}

  defp event("social:send", %{"text" => text}, socket) do
    case socket.assigns.social.peer do
      nil ->
        {:halt, socket}

      peer ->
        case Chat.send_private(me(socket), peer.id, text) do
          :ok -> {:halt, put_social(socket, sent: socket.assigns.social.sent + 1)}
          {:error, reason} -> {:halt, put_flash(socket, :error, Text.reason(reason))}
        end
    end
  end

  defp event("social:accept", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(to_string(id)),
         {:ok, room_id} <- Invites.accept(me(socket), id) do
      {:halt, socket |> put_social(invite: nil) |> push_navigate(to: ~p"/phong/#{room_id}")}
    else
      {:error, reason} ->
        {:halt, socket |> put_social(invite: nil) |> put_flash(:error, Text.reason(reason))}

      _ ->
        {:halt, socket}
    end
  end

  defp event("social:decline", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(to_string(id)), do: Invites.decline(me(socket), id)
    {:halt, put_social(socket, invite: nil)}
  end

  defp event("social:" <> _, _params, socket), do: {:halt, socket}
  defp event(_event, _params, socket), do: {:cont, socket}

  # -- messages ---------------------------------------------------------------------

  defp info({:private_msg, msg, to_id}, socket) do
    me = me(socket)
    peer_id = if msg.user_id == me, do: to_id, else: msg.user_id
    social = socket.assigns.social

    socket =
      if (social.open and social.peer) && social.peer.id == peer_id do
        if msg.user_id != me, do: Chat.mark_read(me, peer_id)
        put_social(socket, lines: social.lines ++ [msg])
      else
        socket
      end

    {:halt, put_social(socket, convs: conversations_after(me, peer_id, socket))}
  end

  defp info({:invite, invite}, socket), do: {:halt, put_social(socket, invite: invite)}

  defp info({:invite_gone, id}, socket) do
    case socket.assigns.social.invite do
      %{id: ^id} -> {:halt, put_social(socket, invite: nil)}
      _ -> {:halt, socket}
    end
  end

  defp info({:invite_answer, answer, name}, socket) do
    {kind, text} =
      case answer do
        :accepted -> {:info, "#{name} đã nhận lời mời"}
        :declined -> {:error, "#{name} đã từ chối lời mời"}
        :expired -> {:error, "Lời mời #{name} đã hết hạn"}
      end

    {:halt, put_flash(socket, kind, text)}
  end

  defp info(_msg, socket), do: {:cont, socket}

  # -- helpers ----------------------------------------------------------------------

  defp me(socket), do: socket.assigns.current_user.id

  defp put_social(socket, changes),
    do: assign(socket, :social, Map.merge(socket.assigns.social, Map.new(changes)))

  defp refresh(socket) do
    social = socket.assigns.social

    cond do
      not social.open -> socket
      social.tab == :online -> put_social(socket, online: online_except(me(socket)))
      true -> put_social(socket, convs: Chat.conversations(me(socket)))
    end
  end

  # the conversation being read has no unread lines (mark_read is a cast)
  defp conversations_after(me, peer_id, socket) do
    peer = socket.assigns.social.peer

    Chat.conversations(me)
    |> Enum.map(fn c ->
      if ((socket.assigns.social.open and peer) && peer.id == c.peer_id) and c.peer_id == peer_id,
        do: %{c | unread: 0},
        else: c
    end)
  end

  defp online_except(me), do: Enum.reject(Presence.online_users(), &(&1.id == me))

  defp peer_name(socket, id) do
    Enum.find_value(socket.assigns.social.convs, &(&1.peer_id == id && &1.name)) ||
      case Presence.get_user(id) do
        nil -> nil
        u -> u.name
      end
  end

  @doc "Human label of a presence place (G6)."
  def place_label("lobby"), do: "Ở sảnh"
  def place_label("room"), do: "Trong phòng"
  def place_label("playing"), do: "Đang chơi"
  def place_label(_), do: "Online"

  # -- rendering --------------------------------------------------------------------

  attr :social, :map, required: true

  def panel(assigns) do
    assigns = assign(assigns, :unread, Enum.sum_by(assigns.social.convs, & &1.unread))

    ~H"""
    <div
      :if={@social.invite}
      id="invite-popup"
      class="fixed top-20 left-1/2 -translate-x-1/2 z-50 card bg-base-100 shadow-xl border border-primary p-4 space-y-2 w-80"
    >
      <p>
        <strong>{@social.invite.from_name}</strong>
        mời bạn vào phòng <span class="font-mono">{@social.invite.room_id}</span>
        <span class="badge badge-outline">
          {if @social.invite.stake == 0,
            do: "Chơi vui",
            else: "Cược " <> Text.coins(@social.invite.stake)}
        </span>
      </p>
      <p class="text-xs text-base-content/60">Lời mời hết hạn sau 60 giây.</p>
      <div class="flex gap-2 justify-end">
        <button
          id="invite-decline"
          phx-click="social:decline"
          phx-value-id={@social.invite.id}
          class="btn btn-sm"
        >
          Từ chối
        </button>
        <button
          id="invite-accept"
          phx-click="social:accept"
          phx-value-id={@social.invite.id}
          class="btn btn-sm btn-primary"
        >
          Vào
        </button>
      </div>
    </div>

    <div id="social" class="fixed bottom-4 right-4 z-40 flex flex-col items-end gap-2">
      <div
        :if={@social.open}
        id="social-panel"
        class="card bg-base-100 shadow-xl border w-80 p-3 space-y-2"
      >
        <div :if={@social.peer == nil} class="tabs tabs-box tabs-sm">
          <button
            phx-click="social:tab"
            phx-value-tab="chats"
            class={["tab", @social.tab == :chats && "tab-active"]}
          >
            Trò chuyện
          </button>
          <button
            id="social-online-tab"
            phx-click="social:tab"
            phx-value-tab="online"
            class={["tab", @social.tab == :online && "tab-active"]}
          >
            Đang online
          </button>
        </div>

        <%= cond do %>
          <% @social.peer -> %>
            <div class="flex items-center gap-2">
              <button phx-click="social:back" class="btn btn-ghost btn-xs">←</button>
              <strong id="social-peer">{@social.peer.name}</strong>
            </div>
            <ol
              id="private-lines"
              phx-hook="ChatScroll"
              class="max-h-60 overflow-y-auto space-y-1 text-sm break-words"
            >
              <li :if={@social.lines == []} class="text-base-content/50">Chưa có tin nhắn.</li>
              <li :for={m <- @social.lines} id={"pm-#{m.id}"}>
                <span class="text-xs text-base-content/50">
                  {TienLenWeb.ChatComponents.hhmm(m.at)}
                </span>
                <span class="font-semibold">{m.name}:</span> {m.text}
              </li>
            </ol>
            <form id="private-form" phx-submit="social:send" class="flex gap-2">
              <input
                id={"private-input-#{@social.sent}"}
                name="text"
                maxlength="200"
                autocomplete="off"
                placeholder="Nhắn riêng…"
                class="input input-bordered input-sm flex-1"
              />
              <button class="btn btn-sm btn-primary">Gửi</button>
            </form>
            <p class="text-xs text-base-content/50">
              Tin nhắn riêng không được lưu, tự xóa sau 1 giờ.
            </p>
          <% @social.tab == :online -> %>
            <ul id="social-online" class="max-h-60 overflow-y-auto divide-y divide-base-300 text-sm">
              <li :if={@social.online == []} class="py-1 text-base-content/50">
                Không có ai khác online.
              </li>
              <li :for={u <- @social.online} class="py-1 flex items-center gap-2">
                <span class="flex-1 truncate">{u.name}</span>
                <span class="text-xs text-base-content/60">{place_label(u.place)}</span>
                <button phx-click="social:open" phx-value-id={u.id} class="btn btn-xs">Nhắn</button>
              </li>
            </ul>
          <% true -> %>
            <ul id="social-convs" class="max-h-60 overflow-y-auto divide-y divide-base-300 text-sm">
              <li :if={@social.convs == []} class="py-1 text-base-content/50">
                Chưa có cuộc trò chuyện. Chọn "Đang online" để nhắn cho ai đó.
              </li>
              <li :for={c <- @social.convs} id={"conv-#{c.peer_id}"}>
                <button
                  phx-click="social:open"
                  phx-value-id={c.peer_id}
                  class="w-full text-left py-1 flex items-center gap-2"
                >
                  <span class="flex-1 truncate">{c.name}</span>
                  <span :if={c.unread > 0} class="badge badge-error badge-sm">{c.unread}</span>
                </button>
              </li>
            </ul>
        <% end %>
      </div>

      <button id="social-toggle" phx-click="social:toggle" class="btn btn-primary btn-sm shadow">
        💬 Tin nhắn
        <span :if={@unread > 0} id="social-unread" class="badge badge-error badge-sm">{@unread}</span>
      </button>
    </div>
    """
  end
end
