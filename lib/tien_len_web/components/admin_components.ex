defmodule TienLenWeb.AdminComponents do
  @moduledoc "Shared pieces of the admin pages (/quan-tri)."
  use TienLenWeb, :html

  @vn_offset 7 * 3600

  attr :active, :atom, required: true

  def admin_nav(assigns) do
    ~H"""
    <nav id="admin-nav" class="tabs tabs-box w-fit flex-wrap">
      <.link navigate={~p"/quan-tri"} class={["tab", @active == :dashboard && "tab-active"]}>
        Tổng quan
      </.link>
      <.link navigate={~p"/quan-tri/nguoi-choi"} class={["tab", @active == :users && "tab-active"]}>
        Người chơi
      </.link>
      <.link navigate={~p"/quan-tri/phong"} class={["tab", @active == :rooms && "tab-active"]}>
        Phòng
      </.link>
      <.link navigate={~p"/quan-tri/van"} class={["tab", @active == :games && "tab-active"]}>
        Ván
      </.link>
      <.link navigate={~p"/quan-tri/nhat-ky"} class={["tab", @active == :audit && "tab-active"]}>
        Nhật ký
      </.link>
      <.link navigate={~p"/quan-tri/cai-dat"} class={["tab", @active == :settings && "tab-active"]}>
        Cài đặt
      </.link>
    </nav>
    """
  end

  @doc "Date-time in Vietnam time (UTC+7)."
  def vn_time(nil), do: "—"

  def vn_time(%DateTime{} = utc),
    do: utc |> DateTime.add(@vn_offset, :second) |> Calendar.strftime("%d/%m/%Y %H:%M")

  def vn_time(%NaiveDateTime{} = naive), do: naive |> DateTime.from_naive!("Etc/UTC") |> vn_time()

  @actions %{
    "promote_server" => "Cấp quyền admin (lệnh server)",
    "set_admin" => "Cấp quyền admin",
    "remove_admin" => "Gỡ quyền admin",
    "lock" => "Khóa tài khoản",
    "unlock" => "Mở khóa",
    "rename" => "Đổi tên hiển thị",
    "reset_password" => "Đặt lại mật khẩu",
    "adjust_coins" => "Điều chỉnh coin",
    "close_room" => "Đóng phòng",
    "kick" => "Mời ra khỏi phòng",
    "update_settings" => "Đổi cài đặt kinh tế",
    "announce" => "Thông báo",
    "mute" => "Cấm chat",
    "unmute" => "Bỏ cấm chat",
    "delete_message" => "Xóa tin nhắn",
    "set_event" => "Đổi sự kiện theo mùa"
  }

  def action_label(action), do: Map.get(@actions, action, action)

  @doc "Message for an admin error."
  def error_text({:error, {:invalid_setting, key}}), do: "Giá trị không hợp lệ: #{key}"
  def error_text({:error, reason}), do: TienLenWeb.Text.reason(reason)
end
