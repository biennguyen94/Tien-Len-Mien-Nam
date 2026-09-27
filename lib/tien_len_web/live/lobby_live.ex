defmodule TienLenWeb.LobbyLive do
  @moduledoc """
  Lobby (RULES T13, decisions A2/A3).

  - Logged out: a register form ("Chào bạn! Bạn tên gì?", "Tài khoản", "Mật khẩu") validated
    live, and a login form. A successful registration submits the same credentials to
    `POST /dang-nhap` (`phx-trigger-action`) so the session is set by a controller.
  - Logged in: change display name, live room list, create or join a room.
  """

  use TienLenWeb, :live_view

  alias TienLen.{Accounts, Lobby}
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_user
    if connected?(socket) and user, do: Lobby.subscribe()
    login_username = Phoenix.Flash.get(socket.assigns.flash, :login_username)

    {:ok,
     socket
     |> assign(:page_title, "Sảnh")
     |> assign(:rooms, if(user, do: Lobby.list_rooms(), else: []))
     |> assign(:editing_name, false)
     |> assign(:trigger_submit, false)
     |> assign_register_form(Accounts.change_registration())
     |> assign(:login_form, to_form(%{"username" => login_username}, as: "user", id: "login"))
     |> assign(:name_form, to_form(%{"display_name" => user && user.display_name}, as: "profile"))}
  end

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

  def handle_event("create", _params, %{assigns: %{current_user: %{}}} = socket) do
    case Lobby.open_room() do
      {:ok, id} -> {:noreply, push_navigate(socket, to: ~p"/phong/#{id}")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
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
    do: {:noreply, assign(socket, :rooms, Lobby.list_rooms())}

  def handle_info({:room_closed, _id}, socket),
    do: {:noreply, assign(socket, :rooms, Lobby.list_rooms())}

  def handle_info(_unexpected, socket), do: {:noreply, socket}

  # -- render ---------------------------------------------------------------------

  @impl true
  def render(%{current_user: nil} = assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
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
    <Layouts.app flash={@flash} current_user={@current_user}>
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
        <div class="flex items-center justify-between gap-2">
          <p>
            Xin chào <strong id="player-name">{@current_user.display_name}</strong>
            <button :if={!@editing_name} phx-click="edit_name" class="btn btn-ghost btn-xs">
              đổi tên
            </button>
          </p>
          <button id="create-room" phx-click="create" class="btn btn-primary">Tạo phòng</button>
        </div>

        <h2 class="text-lg font-semibold">Các phòng</h2>
        <p :if={@rooms == []} id="no-rooms" class="text-base-content/70">
          Chưa có phòng nào. Hãy tạo phòng mới!
        </p>

        <ul :if={@rooms != []} id="rooms" class="divide-y divide-base-300 rounded-box bg-base-200">
          <li :for={room <- @rooms} id={"room-#{room.id}"} class="flex items-center gap-3 p-3">
            <span class="font-mono text-sm">{room.id}</span>
            <span class="flex-1 truncate">Chủ phòng: {room.host_name || "—"}</span>
            <span class="tabular-nums">{room.players}/{room.max_players}</span>
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
          </li>
        </ul>
      </section>
    </Layouts.app>
    """
  end
end
