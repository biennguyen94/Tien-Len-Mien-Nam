defmodule TienLenWeb.Admin.SettingsLive do
  @moduledoc "Admin: economy settings and the lobby announcement (AD9, F7)."
  use TienLenWeb, :live_view
  import TienLenWeb.AdminComponents
  alias TienLen.Settings

  @labels [
    {"starting_coins", "Coin tặng khi đăng ký"},
    {"daily_bonus", "Thưởng ngày"},
    {"relief", "Cứu trợ"},
    {"relief_below", "Cứu trợ khi dưới"},
    {"max_rooms", "Số phòng tối đa"},
    {"mission_play_reward", "Nhiệm vụ: chơi 5 ván"},
    {"mission_win_reward", "Nhiệm vụ: về nhất 2 ván"},
    {"mission_chop_reward", "Nhiệm vụ: chặt heo 1 lần"},
    {"season_reward_1", "Thưởng tuần: hạng 1"},
    {"season_reward_2", "Thưởng tuần: hạng 2"},
    {"season_reward_3", "Thưởng tuần: hạng 3"}
  ]

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, socket |> assign(page_title: "Cài đặt", labels: @labels) |> load()}

  defp load(socket) do
    assign(socket,
      values: Map.new(@labels, fn {k, _} -> {k, Settings.int(k)} end),
      text: Settings.announcement() || "",
      event: Settings.event() || "none"
    )
  end

  @impl true
  def handle_event("save", %{"settings" => params}, socket) do
    case TienLen.Admin.update_settings(socket.assigns.current_user.id, params) do
      {:ok, _} -> {:noreply, socket |> put_flash(:info, "Đã lưu cài đặt") |> load()}
      error -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event("announce", %{"text" => text}, socket) do
    case TienLen.Admin.announce(socket.assigns.current_user.id, text) do
      :ok -> {:noreply, socket |> put_flash(:info, "Đã cập nhật thông báo") |> load()}
      error -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

  def handle_event("set_event", %{"event" => event}, socket) do
    case TienLen.Admin.set_event(socket.assigns.current_user.id, event) do
      :ok -> {:noreply, socket |> put_flash(:info, "Đã cập nhật sự kiện") |> load()}
      error -> {:noreply, put_flash(socket, :error, error_text(error))}
    end
  end

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
      <h1 class="text-xl font-bold">Cài đặt</h1>
      <.admin_nav active={:settings} />
      <form
        id="settings-form"
        phx-submit="save"
        class="card bg-base-200 p-4 grid gap-2 sm:grid-cols-2"
      >
        <label :for={{key, label} <- @labels} class="flex items-center justify-between gap-2">
          <span>{label}</span>
          <input
            type="number"
            min="0"
            step="1"
            name={"settings[#{key}]"}
            value={@values[key]}
            class="input input-bordered input-sm w-40"
          />
        </label>
        <button class="btn btn-primary btn-sm sm:col-span-2">Lưu</button>
      </form>
      <form id="event-form" phx-submit="set_event" class="card bg-base-200 p-4 space-y-2">
        <label for="event-select">Sự kiện theo mùa</label>
        <div class="flex flex-wrap items-center gap-2">
          <select id="event-select" name="event" class="select select-bordered select-sm">
            <option value="none" selected={@event == "none"}>Không có</option>
            <option value="tet" selected={@event == "tet"}>🧧 Tết (ván về nhất nhận lì xì)</option>
            <option value="trung_thu" selected={@event == "trung_thu"}>
              🏮 Trung thu (avatar đội đèn lồng)
            </option>
          </select>
          <button class="btn btn-sm">Lưu sự kiện</button>
        </div>
        <p class="text-xs text-base-content/60">
          Lì xì Tết: 8–168 coin mỗi lần về nhất (ván không có máy), tối đa 10 lần mỗi người mỗi ngày.
        </p>
      </form>
      <form id="announce-form" phx-submit="announce" class="card bg-base-200 p-4 space-y-2">
        <label>Thông báo trên sảnh (để trống để tắt)</label>
        <textarea name="text" maxlength="300" class="textarea textarea-bordered w-full">{@text}</textarea>
        <button class="btn btn-sm">Cập nhật thông báo</button>
      </form>
    </Layouts.app>
    """
  end
end
