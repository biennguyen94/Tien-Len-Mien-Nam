defmodule TienLenWeb.LobbyLive do
  @moduledoc """
  Lobby (RULES T13, decisions A2/A3).

  - Logged out: a register form ("Chào bạn! Bạn tên gì?", "Tài khoản", "Mật khẩu") validated
    live, and a login form. A successful registration submits the same credentials to
    `POST /dang-nhap` (`phx-trigger-action`) so the session is set by a controller.
  - Logged in: change display name, live room list, create or join a room.
  """

  use TienLenWeb, :live_view

  import TienLenWeb.ChatComponents

  alias TienLen.{Accounts, Chat, Economy, Lobby, Presence}
  alias TienLenWeb.Text

  @impl true
  def mount(params, _session, socket) do
    user = socket.assigns.current_user
    live? = connected?(socket) and user != nil

    if live? do
      Lobby.subscribe()
      Chat.subscribe_lobby()
      Presence.subscribe()
      Presence.move(self(), user, "lobby")
      # M1: mission progress follows recorded games
      TienLen.Stats.subscribe()
    end

    login_username = Phoenix.Flash.get(socket.assigns.flash, :login_username)

    {:ok,
     socket
     |> assign(:page_title, "Sảnh")
     # G10: where to go after logging in (a room link opened while logged out)
     |> assign(:next, TienLenWeb.UserAuth.safe_next(params["next"]))
     |> assign(:rooms, if(user, do: Lobby.public_rooms(), else: []))
     |> assign(:lobby_chat, if(live?, do: Chat.lobby_history(), else: []))
     |> assign(:chat_key, 0)
     |> assign(:online, if(live?, do: Presence.online_users(), else: []))
     |> assign(:editing_name, false)
     |> assign(:changing_password, false)
     |> assign(:trigger_submit, false)
     |> assign_register_form(Accounts.change_registration())
     |> assign(:login_form, to_form(%{"username" => login_username}, as: "user", id: "login"))
     |> assign(:name_form, to_form(%{"display_name" => user && user.display_name}, as: "profile"))
     |> assign(:room_form, to_form(%{"stake" => "0"}, as: "room"))
     |> assign_claimable()
     |> assign_missions()}
  end

  defp assign_missions(%{assigns: %{current_user: %{id: id}}} = socket),
    do: assign(socket, :missions, TienLen.Missions.today(id))

  defp assign_missions(socket), do: assign(socket, :missions, [])

  # What the player may claim today (E8); re-read after every claim and balance change.
  defp assign_claimable(%{assigns: %{current_user: %{id: id}}} = socket),
    do: assign(socket, :claimable, Economy.claimable(id))

  defp assign_claimable(socket),
    do: assign(socket, :claimable, %{daily_bonus: false, relief: false})

  # Parses the stake typed by the host (C3). Anything else is refused by the room server.
  defp parse_stake(%{"stake" => stake}) when is_binary(stake) do
    case Integer.parse(String.trim(stake)) do
      {n, ""} -> n
      _ -> :invalid
    end
  end

  defp parse_stake(_), do: 0

  defp assign_register_form(socket, changeset),
    do: assign(socket, :register_form, to_form(changeset, as: "user", id: "register"))

  # -- registration ---------------------------------------------------------------

  @impl true
  def handle_event("validate_register", %{"user" => params}, socket) do
    changeset =
      %Accounts.User{}
      |> Accounts.change_registration(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_register_form(socket, changeset)}
  end

  def handle_event("register", %{"user" => params}, socket) do
    case Accounts.register_user(params) do
      {:ok, _user} ->
        # keep the typed values in the form; the browser now posts them to /dang-nhap
        changeset = Accounts.change_registration(%Accounts.User{}, params)
        {:noreply, socket |> assign(:trigger_submit, true) |> assign_register_form(changeset)}

      {:error, changeset} ->
        {:noreply, assign_register_form(socket, changeset)}
    end
  end

  # -- logged-in lobby ------------------------------------------------------------

  def handle_event("create", params, %{assigns: %{current_user: %{}}} = socket) do
    room = params["room"] || %{}

    case Lobby.open_room(stake: parse_stake(room), private: room["private"] == "true") do
      {:ok, id} -> {:noreply, push_navigate(socket, to: ~p"/phong/#{id}")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
  end

  def handle_event("claim_daily", _params, %{assigns: %{current_user: %{id: id}}} = socket) do
    case Economy.claim_daily_bonus(id) do
      {:ok, _balance} ->
        {:noreply,
         socket
         |> put_flash(:info, "Đã nhận thưởng ngày +#{Text.coins(Economy.daily_bonus())} coin")
         |> assign_claimable()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Text.reason(reason)) |> assign_claimable()}
    end
  end

  def handle_event("claim_relief", _params, %{assigns: %{current_user: %{id: id}}} = socket) do
    case Economy.claim_relief(id) do
      {:ok, _balance} ->
        {:noreply,
         socket
         |> put_flash(:info, "Đã nhận cứu trợ +#{Text.coins(Economy.relief())} coin")
         |> assign_claimable()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Text.reason(reason)) |> assign_claimable()}
    end
  end

  # F3: players replace a temporary password (or any password) themselves.
  def handle_event("toggle_password", _params, socket),
    do: {:noreply, assign(socket, :changing_password, !socket.assigns.changing_password)}

  def handle_event(
        "change_password",
        %{"current" => current, "new" => new},
        %{assigns: %{current_user: %{} = user}} = socket
      ) do
    case Accounts.change_password(user, current, new) do
      {:ok, _user} ->
        {:noreply,
         socket |> assign(:changing_password, false) |> put_flash(:info, "Đã đổi mật khẩu")}

      {:error, :wrong_password} ->
        {:noreply, put_flash(socket, :error, Text.reason(:wrong_password))}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           cs.errors |> Keyword.values() |> Enum.map_join(", ", &elem(&1, 0))
         )}
    end
  end

  # G5: lobby chat
  def handle_event(
        "lobby_chat_send",
        %{"text" => text},
        %{assigns: %{current_user: %{id: id}}} = socket
      ) do
    case Chat.send_lobby(id, text) do
      :ok -> {:noreply, update(socket, :chat_key, &(&1 + 1))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
  end

  # G12: admins delete a lobby message (TienLen.Admin re-checks the role)
  def handle_event(
        "lobby_chat_delete",
        %{"id" => id},
        %{assigns: %{current_user: %{id: me}}} = socket
      ) do
    with {id, ""} <- Integer.parse(to_string(id)),
         :ok <- TienLen.Admin.delete_message(me, {:lobby, id}) do
      {:noreply, socket}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, Text.reason(reason))}
      _ -> {:noreply, socket}
    end
  end

  # M1: daily mission rewards (the server checks progress and pays once)
  def handle_event(
        "claim_mission",
        %{"key" => key},
        %{assigns: %{current_user: %{id: id}}} = socket
      ) do
    case TienLen.Missions.claim(id, key) do
      {:ok, _balance} ->
        {:noreply, socket |> put_flash(:info, "Đã nhận thưởng nhiệm vụ") |> assign_missions()}

      {:error, reason} ->
        {:noreply, socket |> put_flash(:error, Text.reason(reason)) |> assign_missions()}
    end
  end

  # G9: "Không nhận lời mời"
  def handle_event("toggle_invites", _params, %{assigns: %{current_user: %{} = user}} = socket) do
    {:ok, user} = Accounts.set_accept_invites(user, !user.accept_invites)
    {:noreply, assign(socket, :current_user, user)}
  end

  def handle_event("edit_name", _params, socket),
    do: {:noreply, assign(socket, :editing_name, true)}

  def handle_event(
        "save_name",
        %{"profile" => %{"display_name" => name}},
        %{assigns: %{current_user: %{} = user}} = socket
      ) do
    case Accounts.change_display_name(user, name) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(current_user: user, editing_name: false)
         |> assign(:name_form, to_form(%{"display_name" => user.display_name}, as: "profile"))
         |> put_flash(:info, "Đã đổi tên")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, Text.reason(:invalid_name))}
    end
  end

  # anything else (including logged-in actions while logged out) is ignored
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:lobby_updated, _id}, socket),
    do: {:noreply, assign(socket, :rooms, Lobby.public_rooms())}

  def handle_info({:room_closed, _id}, socket),
    do: {:noreply, assign(socket, :rooms, Lobby.public_rooms())}

  def handle_info({:lobby_chat, msg}, socket),
    do: {:noreply, update(socket, :lobby_chat, &Enum.take(&1 ++ [msg], -100))}

  def handle_info({:lobby_chat_deleted, id}, socket),
    do: {:noreply, update(socket, :lobby_chat, &Enum.reject(&1, fn m -> m.id == id end))}

  def handle_info({:stats_updated}, socket), do: {:noreply, assign_missions(socket)}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, :online, Presence.online_users())}

  def handle_info(_unexpected, socket), do: {:noreply, assign_claimable(socket)}

  # -- render ---------------------------------------------------------------------

  @impl true
  def render(%{current_user: nil} = assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
    >
      <div class="grid gap-4 md:grid-cols-2">
        <section id="register" class="card bg-base-200 p-6">
          <h1 class="text-xl font-bold mb-3">Đăng ký</h1>
          <.form
            for={@register_form}
            id="register-form"
            action={~p"/dang-nhap"}
            method="post"
            phx-change="validate_register"
            phx-submit="register"
            phx-trigger-action={@trigger_submit}
          >
            <input type="hidden" name="user[registered]" value="true" />
            <input :if={@next} type="hidden" name="user[next]" value={@next} />
            <.input
              field={@register_form[:display_name]}
              label="Chào bạn! Bạn tên gì?"
              maxlength="20"
              autocomplete="nickname"
              required
            />
            <.input
              field={@register_form[:username]}
              label="Tài khoản"
              maxlength="20"
              autocomplete="username"
              required
            />
            <.input
              field={@register_form[:password]}
              type="password"
              label="Mật khẩu"
              value={@register_form[:password].value}
              autocomplete="new-password"
              required
            />
            <button
              type="submit"
              class="btn btn-primary w-full mt-2"
              phx-disable-with="Đang đăng ký…"
            >
              Đăng ký
            </button>
          </.form>
        </section>

        <section id="login" class="card bg-base-200 p-6">
          <h2 class="text-xl font-bold mb-3">Đăng nhập</h2>
          <.form for={@login_form} id="login-form" action={~p"/dang-nhap"} method="post">
            <input :if={@next} type="hidden" name="user[next]" value={@next} />
            <.input
              field={@login_form[:username]}
              label="Tài khoản"
              autocomplete="username"
              required
            />
            <.input
              field={@login_form[:password]}
              type="password"
              label="Mật khẩu"
              autocomplete="current-password"
              required
            />
            <button type="submit" class="btn w-full mt-2">Đăng nhập</button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
    >
      <section :if={@editing_name} id="name-form" class="card bg-base-200 p-4">
        <.form
          for={@name_form}
          id="profile-form"
          phx-submit="save_name"
          class="flex items-end gap-2"
        >
          <div class="flex-1">
            <.input
              field={@name_form[:display_name]}
              label="Tên hiển thị"
              maxlength="20"
              required
            />
          </div>
          <button type="submit" class="btn btn-primary mb-2">Lưu</button>
        </.form>
      </section>

      <section class="space-y-4">
        <%!-- M3: greeting and account actions in one row that wraps, left-aligned --%>
        <div id="account" class="flex flex-wrap items-center gap-x-3 gap-y-1">
          <p class="min-w-0 truncate">
            Xin chào <strong id="player-name">{@current_user.display_name}</strong>
          </p>
          <button :if={!@editing_name} phx-click="edit_name" class="btn btn-ghost btn-xs px-1">
            đổi tên
          </button>
          <button id="toggle-password" phx-click="toggle_password" class="btn btn-ghost btn-xs px-1">
            đổi mật khẩu
          </button>
          <label class="label text-sm gap-1">
            <input
              id="toggle-invites"
              type="checkbox"
              class="checkbox checkbox-xs"
              checked={!@current_user.accept_invites}
              phx-click="toggle_invites"
            /> Không nhận lời mời
          </label>
        </div>
        <form
          :if={@changing_password}
          id="password-form"
          phx-submit="change_password"
          class="card bg-base-200 p-4 flex flex-col sm:flex-row sm:flex-wrap sm:items-end gap-2"
        >
          <input
            type="password"
            name="current"
            placeholder="Mật khẩu hiện tại"
            autocomplete="current-password"
            class="input input-bordered input-sm w-full sm:w-auto"
            required
          />
          <input
            type="password"
            name="new"
            placeholder="Mật khẩu mới (8–72)"
            autocomplete="new-password"
            class="input input-bordered input-sm w-full sm:w-auto"
            required
          />
          <button class="btn btn-sm btn-primary">Đổi mật khẩu</button>
        </form>

        <div id="coins" class="card bg-base-200 p-4 flex flex-row flex-wrap items-center gap-3">
          <span class="text-lg">🪙 <strong id="balance">{Text.coins(@current_user.coins)}</strong> coin</span>
          <button
            :if={@claimable.daily_bonus}
            id="claim-daily"
            phx-click="claim_daily"
            class="btn btn-sm btn-success"
          >
            Nhận thưởng ngày (+{Text.coins(Economy.daily_bonus())})
          </button>
          <button
            :if={@claimable.relief}
            id="claim-relief"
            phx-click="claim_relief"
            class="btn btn-sm btn-warning"
          >
            Nhận cứu trợ (+{Text.coins(Economy.relief())})
          </button>
          <.link navigate={~p"/lich-su-coin"} class="link text-sm">Lịch sử coin</.link>
        </div>

        <section id="missions" class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">Nhiệm vụ hôm nay</h2>
          <ul class="space-y-2">
            <li
              :for={m <- @missions}
              id={"mission-#{m.key}"}
              class="flex flex-wrap sm:flex-nowrap items-center gap-x-2 gap-y-1"
            >
              <span class="w-full sm:w-auto sm:flex-1">
                {m.title}
                <span class="text-xs text-base-content/60 whitespace-nowrap">
                  (+{Text.coins(m.reward)} coin)
                </span>
              </span>
              <progress
                class="progress progress-primary flex-1 sm:flex-none sm:w-20"
                value={m.progress}
                max={m.goal}
              />
              <span class="text-sm tabular-nums w-10 text-right">{m.progress}/{m.goal}</span>
              <button
                :if={m.done and not m.claimed}
                id={"claim-#{m.key}"}
                phx-click="claim_mission"
                phx-value-key={m.key}
                class="btn btn-xs btn-success"
              >
                Nhận
              </button>
              <span :if={m.claimed} class="text-success text-sm">✓ Đã nhận</span>
            </li>
          </ul>
          <p class="text-xs text-base-content/60">
            Tính các ván được ghi trong ngày (giờ Việt Nam); ván có máy chơi không tính.
          </p>
        </section>

        <%!-- M3: stacked on phones (label, input, private, button, note); one row from sm up --%>
        <.form
          for={@room_form}
          id="create-room-form"
          phx-submit="create"
          class="flex flex-col sm:flex-row sm:items-end gap-x-2"
        >
          <div class="w-full sm:w-44">
            <.input
              field={@room_form[:stake]}
              type="number"
              min="0"
              step="1"
              label="Tiền cược mỗi ván"
            />
          </div>
          <label class="label mb-3 text-sm gap-1 self-start sm:self-auto">
            <input type="hidden" name="room[private]" value="false" />
            <input
              id="room-private"
              type="checkbox"
              name="room[private]"
              value="true"
              class="checkbox checkbox-sm"
            /> Riêng tư
          </label>
          <button id="create-room" type="submit" class="btn btn-primary w-full sm:w-auto mb-2">
            Tạo phòng
          </button>
          <span class="text-xs text-base-content/60 sm:mb-3">
            Cược 0 = chơi vui, hoặc từ 10. Phòng riêng tư không hiện ở sảnh, chỉ vào bằng lời mời hoặc link.
          </span>
        </.form>

        <h2 class="text-lg font-semibold">Các phòng</h2>
        <p :if={@rooms == []} id="no-rooms" class="text-base-content/70">
          Chưa có phòng nào. Hãy tạo phòng mới!
        </p>

        <ul :if={@rooms != []} id="rooms" class="divide-y divide-base-300 rounded-box bg-base-200">
          <li
            :for={room <- @rooms}
            id={"room-#{room.id}"}
            class="flex flex-wrap items-center gap-x-3 gap-y-2 p-3"
          >
            <span class="font-mono text-sm">{room.id}</span>
            <span class="flex-1 min-w-32 truncate">Chủ phòng: {room.host_name || "—"}</span>
            <span class="tabular-nums">{room.players}/{room.max_players}</span>
            <span class="text-sm tabular-nums">
              {if room.stake == 0, do: "Chơi vui", else: "Cược " <> Text.coins(room.stake)}
            </span>
            <span class={[
              "badge",
              if(room.status == :playing, do: "badge-warning", else: "badge-success")
            ]}>
              {if room.status == :playing, do: "Đang chơi", else: "Đang chờ"}
            </span>
            <.link
              :if={room.joinable}
              navigate={~p"/phong/#{room.id}"}
              class="btn btn-sm btn-outline"
            >
              Vào
            </.link>
            <.link
              id={"watch-#{room.id}"}
              navigate={~p"/phong/#{room.id}/xem"}
              class="btn btn-sm btn-ghost"
            >
              Xem
            </.link>
          </li>
        </ul>

        <div class="grid gap-4 md:grid-cols-3">
          <div class="md:col-span-2">
            <.chat_box
              id="lobby-chat"
              title="Chat sảnh"
              messages={@lobby_chat}
              me={@current_user.id}
              send_event="lobby_chat_send"
              phrases
              key={@chat_key}
              delete_event={@current_user.role == "admin" && "lobby_chat_delete"}
            />
          </div>
          <section id="online" class="card bg-base-200 p-3 space-y-2">
            <h2 class="font-semibold text-sm">Đang online ({length(@online)})</h2>
            <ul class="max-h-64 overflow-y-auto divide-y divide-base-300 text-sm">
              <li :for={u <- @online} id={"online-#{u.id}"} class="py-1 flex items-center gap-2">
                <.link
                  navigate={~p"/nguoi-choi/#{u.username || ""}"}
                  class="flex-1 truncate link link-hover"
                >
                  {Text.avatar(u)} {u.name}
                </.link>
                <span class="text-xs text-base-content/60">
                  {TienLenWeb.Social.place_label(u.place)}
                </span>
                <button
                  :if={u.id != @current_user.id}
                  phx-click="social:open"
                  phx-value-id={u.id}
                  class="btn btn-xs"
                >
                  Nhắn
                </button>
              </li>
            </ul>
          </section>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
