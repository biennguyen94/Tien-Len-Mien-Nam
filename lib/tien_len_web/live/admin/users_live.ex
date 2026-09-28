defmodule TienLenWeb.Admin.UsersLive do
  @moduledoc "Admin: search users (AD4)."
  use TienLenWeb, :live_view
  import TienLenWeb.AdminComponents
  alias TienLenWeb.Text

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Người chơi")}

  @impl true
  def handle_params(params, _uri, socket) do
    q = params["q"] || ""
    {:noreply, assign(socket, q: q, users: TienLen.Admin.search_users(q))}
  end

  @impl true
  def handle_event("search", %{"q" => q}, socket),
    do: {:noreply, push_patch(socket, to: ~p"/quan-tri/nguoi-choi?#{[q: q]}")}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
      wide
    >
      <h1 class="text-xl font-bold">Người chơi</h1>
      <.admin_nav active={:users} />
      <form id="user-search" phx-submit="search" class="flex gap-2">
        <input
          type="search"
          name="q"
          value={@q}
          placeholder="Tài khoản hoặc tên"
          class="input input-bordered flex-1"
        />
        <button class="btn">Tìm</button>
      </form>
      <table id="users" class="table table-zebra">
        <thead>
          <tr>
            <th>Tài khoản</th><th>Tên</th><th class="text-right">Coin</th><th>Vai trò</th><th>
              Trạng thái
            </th><th>Tạo lúc</th>
          </tr>
        </thead>
        <tbody>
          <tr :for={u <- @users} id={"user-#{u.id}"}>
            <td>
              <.link navigate={~p"/quan-tri/nguoi-choi/#{u.id}"} class="link">@{u.username}</.link>
            </td>
            <td>{u.display_name}</td>
            <td class="text-right tabular-nums">{Text.coins(u.coins)}</td>
            <td><span :if={u.role == "admin"} class="badge badge-error">admin</span></td>
            <td><span :if={u.locked_at} class="badge badge-warning">bị khóa</span></td>
            <td class="text-sm">{vn_time(u.inserted_at)}</td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end
end
