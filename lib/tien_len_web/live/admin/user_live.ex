defmodule TienLenWeb.Admin.UserLive do
  @moduledoc "Admin: one user — details and actions (AD1, AD4, AD5, F1–F4)."
  use TienLenWeb, :live_view
  import TienLenWeb.AdminComponents
  alias TienLen.Admin
  alias TienLenWeb.Text

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Integer.parse(id) do
      {id, ""} ->
        {:ok, socket |> assign(id: id, temp_password: nil, page_title: "Người chơi") |> load()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, Text.reason(:not_found))
         |> push_navigate(to: ~p"/quan-tri/nguoi-choi")}
    end
  end

  defp load(socket) do
    case Admin.user_detail(socket.assigns.id) do
      nil ->
        socket
        |> put_flash(:error, Text.reason(:not_found))
        |> push_navigate(to: ~p"/quan-tri/nguoi-choi")

      detail ->
        assign(socket, :detail, detail)
    end
  end

  defp me(socket), do: socket.assigns.current_user.id

  defp result(socket, {:ok, _}, message),
    do: {:noreply, socket |> put_flash(:info, message) |> load()}

  defp result(socket, :ok, message), do: {:noreply, socket |> put_flash(:info, message) |> load()}

  defp result(socket, error, _message),
    do: {:noreply, put_flash(socket, :error, error_text(error))}

  @impl true
  def handle_event("lock", params, socket),
    do:
      result(
        socket,
        Admin.lock(me(socket), socket.assigns.id, params["reason"]),
        "Đã khóa tài khoản"
      )

  def handle_event("unlock", _params, socket),
    do: result(socket, Admin.unlock(me(socket), socket.assigns.id), "Đã mở khóa")

  def handle_event("set_admin", _params, socket),
    do: result(socket, Admin.set_admin(me(socket), socket.assigns.id, true), "Đã cấp quyền admin")

  def handle_event("remove_admin", _params, socket),
    do: result(socket, Admin.set_admin(me(socket), socket.assigns.id, false), "Đã gỡ quyền admin")

  def handle_event("mute", %{"minutes" => minutes}, socket) do
    minutes = String.to_integer(minutes)
    result(socket, Admin.mute(me(socket), socket.assigns.id, minutes), "Đã cấm chat")
  rescue
    ArgumentError -> {:noreply, put_flash(socket, :error, Text.reason(:invalid_duration))}
  end

  def handle_event("unmute", _params, socket),
    do: result(socket, Admin.unmute(me(socket), socket.assigns.id), "Đã bỏ cấm chat")

  def handle_event("rename", %{"name" => name}, socket),
    do: result(socket, Admin.rename(me(socket), socket.assigns.id, name), "Đã đổi tên")

  def handle_event("reset_password", _params, socket) do
    case Admin.reset_password(me(socket), socket.assigns.id) do
      {:ok, temp} ->
        {:noreply,
         socket |> assign(:temp_password, temp) |> put_flash(:info, "Đã đặt lại mật khẩu")}

      error ->
        {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event("adjust", %{"amount" => amount, "reason" => reason}, socket) do
    amount =
      case Integer.parse(String.trim(to_string(amount))) do
        {n, ""} -> n
        _ -> :invalid
      end

    result(
      socket,
      Admin.adjust_coins(me(socket), socket.assigns.id, amount, reason),
      "Đã điều chỉnh coin"
    )
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :u, assigns.detail.user)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
      wide
    >
      <.admin_nav active={:users} />
      <h1 class="text-xl font-bold">
        {@u.display_name} <span class="text-base-content/60">@{@u.username}</span>
        <span :if={@u.role == "admin"} class="badge badge-error">admin</span>
        <span :if={@u.locked_at} id="locked-badge" class="badge badge-warning">bị khóa</span>
        <span :if={TienLen.Accounts.User.muted?(@u)} id="muted-badge" class="badge badge-warning">
          cấm chat đến {vn_time(@u.muted_until)}
        </span>
      </h1>
      <p id="user-coins">
        🪙 {Text.coins(@u.coins)} coin · tạo lúc {vn_time(@u.inserted_at)}
        <span :if={@detail.standing}> · hạng {@detail.standing.rank}: về nhất {@detail.standing.wins}/{@detail.standing.games} ván</span>
      </p>

      <div class="grid gap-4 md:grid-cols-2">
        <section class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">Tài khoản</h2>
          <div class="flex flex-wrap gap-2">
            <button
              :if={!@u.locked_at}
              id="lock"
              phx-click="lock"
              class="btn btn-sm btn-warning"
              data-confirm="Khóa tài khoản này?"
            >Khóa</button>
            <button :if={@u.locked_at} id="unlock" phx-click="unlock" class="btn btn-sm">Mở khóa</button>
            <button
              :if={@u.role != "admin"}
              id="set-admin"
              phx-click="set_admin"
              class="btn btn-sm btn-error"
              data-confirm="Cấp quyền admin?"
            >Set admin</button>
            <button
              :if={@u.role == "admin"}
              id="remove-admin"
              phx-click="remove_admin"
              class="btn btn-sm"
              data-confirm="Gỡ quyền admin?"
            >Gỡ admin</button>
            <button
              id="reset-password"
              phx-click="reset_password"
              class="btn btn-sm"
              data-confirm="Đặt lại mật khẩu?"
            >Đặt lại mật khẩu</button>
          </div>
          <div id="mute" class="flex flex-wrap items-center gap-2 text-sm">
            <span>Cấm chat:</span>
            <button
              :for={{m, label} <- [{10, "10 phút"}, {60, "1 giờ"}, {1440, "24 giờ"}]}
              id={"mute-#{m}"}
              phx-click="mute"
              phx-value-minutes={m}
              class="btn btn-xs btn-warning"
            >{label}</button>
            <button
              :if={TienLen.Accounts.User.muted?(@u)}
              id="unmute"
              phx-click="unmute"
              class="btn btn-xs"
            >Bỏ cấm chat</button>
          </div>
          <p :if={@temp_password} id="temp-password" class="alert alert-warning">
            Mật khẩu tạm (chỉ hiện một lần): <code class="font-mono">{@temp_password}</code>
          </p>
          <form id="rename-form" phx-submit="rename" class="flex gap-2">
            <input
              name="name"
              value={@u.display_name}
              maxlength="20"
              class="input input-bordered input-sm flex-1"
            />
            <button class="btn btn-sm">Đổi tên</button>
          </form>
        </section>

        <section class="card bg-base-200 p-4 space-y-2">
          <h2 class="font-semibold">Điều chỉnh coin</h2>
          <form id="adjust-form" phx-submit="adjust" class="space-y-2">
            <input
              name="amount"
              type="number"
              step="1"
              placeholder="+500 hoặc -200"
              class="input input-bordered input-sm w-full"
            />
            <input
              name="reason"
              maxlength="200"
              placeholder="Lý do (bắt buộc)"
              class="input input-bordered input-sm w-full"
            />
            <button class="btn btn-sm btn-primary">Điều chỉnh</button>
          </form>
        </section>
      </div>

      <h2 class="font-semibold">Lịch sử coin</h2>
      <%!-- M3: a wide table scrolls inside its box on phones, never the page --%>
      <div class="overflow-x-auto">
        <table id="user-ledger" class="table table-sm table-zebra">
          <tbody>
            <tr :for={row <- @detail.ledger}>
              <td class="text-sm">{vn_time(row.inserted_at)}</td>
              <td>
                {Text.coin_reason(row.reason)}
                <span :if={row.ref && row.reason == "admin_adjust"} class="text-base-content/60">({row.ref})</span>
              </td>
              <td class="text-right tabular-nums">{Text.signed_coins(row.amount)}</td>
              <td class="text-right tabular-nums">{Text.coins(row.balance_after)}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h2 class="font-semibold">Ván gần đây</h2>
      <ul id="user-games" class="text-sm space-y-1">
        <li :for={g <- @detail.games}>
          {vn_time(g.finished_at)} · {g.player_count} người · hạng {g.place}{if g.won, do: " (Nhất)"}
        </li>
      </ul>
    </Layouts.app>
    """
  end
end
