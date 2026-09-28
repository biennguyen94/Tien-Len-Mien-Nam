defmodule TienLenWeb.Admin.AuditLive do
  @moduledoc "Admin: the audit log (AD2)."
  use TienLenWeb, :live_view
  import TienLenWeb.AdminComponents

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Nhật ký", actions: TienLen.Admin.actions(200))}

  @impl true
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
      <h1 class="text-xl font-bold">Nhật ký quản trị</h1>
      <.admin_nav active={:audit} />
      <%!-- M3: a wide table scrolls inside its box on phones, never the page --%>
      <div class="overflow-x-auto">
        <table id="audit" class="table table-sm table-zebra">
          <thead>
            <tr>
              <th>Thời gian</th><th>Admin</th><th>Hành động</th><th>Đối tượng</th><th>Chi tiết</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={a <- @actions} id={"audit-#{a.id}"}>
              <td>{vn_time(a.inserted_at)}</td>
              <td>{if a.admin, do: "@" <> a.admin, else: "(server)"}</td>
              <td>{action_label(a.action)}</td>
              <td>{if a.target, do: "@" <> a.target}</td>
              <td class="text-xs">{if a.details != %{}, do: Jason.encode!(a.details)} {a.reason}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
