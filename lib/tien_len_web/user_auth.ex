defmodule TienLenWeb.UserAuth do
  @moduledoc """
  Session-based authentication (decisions A2, A3; interpretations Y2–Y4).

  - The signed session cookie holds `"user_id"` and a random `"live_socket_id"` for this
    browser session. Login renews the session (no fixation); logout clears it and disconnects
    the LiveViews of **this** browser session only (Y3).
  - Controllers get `@current_user` from `fetch_current_user/2` (in the `:browser` pipeline).
  - LiveViews use `on_mount {TienLenWeb.UserAuth, :mount_current_user}` (lobby: logged in or
    not) or `:require_user` (rooms). Both assign `:current_user`; `:require_user` also assigns
    `:player_id` (the user id, Y4) and `:player_name` (the display name).
  - Also lets LiveView processes join the test database sandbox (tests only).
  """

  use TienLenWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias TienLen.Accounts

  # -- controllers ----------------------------------------------------------------

  @doc "Plug: assigns `:current_user` from the session (or `nil`)."
  def fetch_current_user(conn, _opts) do
    # a locked account's session counts as logged out (F2)
    user = conn |> get_session("user_id") |> Accounts.get_active_user()
    assign(conn, :current_user, user)
  end

  @doc "Logs the user in: renews the session and redirects to the lobby."
  def log_in_user(conn, user) do
    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_session("user_id", user.id)
    |> put_session("live_socket_id", "user_sessions:" <> random_id())
    |> redirect(to: ~p"/")
  end

  @doc "Logs out: disconnects this session's LiveViews, clears the session."
  def log_out_user(conn) do
    if live_socket_id = get_session(conn, "live_socket_id") do
      TienLenWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> redirect(to: ~p"/")
  end

  defp random_id, do: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

  # -- LiveViews ------------------------------------------------------------------

  def on_mount(:mount_current_user, _params, session, socket) do
    allow_ecto_sandbox(socket)
    {:cont, socket |> mount_current_user(session) |> common()}
  end

  # AD1: admin pages. The role is read from the database at mount; every admin action is
  # re-authorized by TienLen.Admin as well, and a role change sends the page away at once.
  def on_mount(:require_admin, _params, session, socket) do
    allow_ecto_sandbox(socket)
    socket = mount_current_user(socket, session)

    if TienLen.Accounts.User.admin?(socket.assigns.current_user) do
      {:cont, socket |> Phoenix.Component.assign(:admin_area, true) |> common()}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "Chỉ quản trị viên mới vào được trang này")
       |> Phoenix.LiveView.redirect(to: ~p"/")}
    end
  end

  def on_mount(:require_user, _params, session, socket) do
    allow_ecto_sandbox(socket)
    socket = mount_current_user(socket, session)

    case socket.assigns.current_user do
      nil ->
        {:halt,
         socket
         |> Phoenix.LiveView.put_flash(:error, "Hãy đăng nhập để vào phòng")
         |> Phoenix.LiveView.redirect(to: ~p"/")}

      user ->
        {:cont,
         socket
         |> Phoenix.Component.assign(:player_id, user.id)
         |> Phoenix.Component.assign(:player_name, user.display_name)
         |> common()}
    end
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      Accounts.get_active_user(session["user_id"])
    end)
  end

  # Shared by every page: the announcement banner (AD9), live account events (F2, F1) and the
  # header balance.
  defp common(socket) do
    socket
    |> Phoenix.Component.assign(:announcement, TienLen.Settings.announcement())
    |> Phoenix.Component.assign_new(:admin_area, fn -> false end)
    |> track_announcement()
    |> track_account()
    |> track_coins()
  end

  defp track_announcement(socket) do
    if Phoenix.LiveView.connected?(socket) do
      TienLen.Settings.subscribe()

      Phoenix.LiveView.attach_hook(socket, :announcement, :handle_info, fn
        {:settings_changed, "announcement", text}, socket ->
          {:halt, Phoenix.Component.assign(socket, :announcement, text)}

        {:settings_changed, _key, _value}, socket ->
          {:halt, socket}

        _other, socket ->
          {:cont, socket}
      end)
    else
      socket
    end
  end

  # F2: a locked account is sent to the (logged-out) lobby at once; F1: losing the admin role
  # sends admin pages away.
  defp track_account(%{assigns: %{current_user: %{id: id}}} = socket) do
    if Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.subscribe(TienLen.PubSub, TienLen.Admin.user_topic(id))

      Phoenix.LiveView.attach_hook(socket, :account, :handle_info, fn
        {:force_logout}, socket ->
          {:halt,
           socket
           |> Phoenix.LiveView.put_flash(:error, "Tài khoản đã bị khóa")
           |> Phoenix.LiveView.redirect(to: ~p"/")}

        {:role_changed, role}, socket ->
          socket =
            Phoenix.Component.assign(socket, :current_user, %{
              socket.assigns.current_user
              | role: role
            })

          if socket.assigns.admin_area and role != "admin",
            do: {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/")},
            else: {:halt, socket}

        _other, socket ->
          {:cont, socket}
      end)
    else
      socket
    end
  end

  defp track_account(socket), do: socket

  # Keeps `@current_user.coins` (shown in the header) up to date on every page.
  defp track_coins(%{assigns: %{current_user: %{id: id}}} = socket) do
    if Phoenix.LiveView.connected?(socket) do
      TienLen.Economy.subscribe(id)

      Phoenix.LiveView.attach_hook(socket, :coins, :handle_info, fn
        {:coins_updated, ^id, balance}, socket ->
          user = %{socket.assigns.current_user | coins: balance}
          {:cont, Phoenix.Component.assign(socket, :current_user, user)}

        _other, socket ->
          {:cont, socket}
      end)
    else
      socket
    end
  end

  defp track_coins(socket), do: socket

  # Tests only: LiveView processes join the database sandbox of the test that mounted them.
  defp allow_ecto_sandbox(socket) do
    if Application.get_env(:tien_len, :sql_sandbox) && Phoenix.LiveView.connected?(socket) do
      socket
      |> Phoenix.LiveView.get_connect_info(:user_agent)
      |> Phoenix.Ecto.SQL.Sandbox.allow(Ecto.Adapters.SQL.Sandbox)
    end
  end
end
