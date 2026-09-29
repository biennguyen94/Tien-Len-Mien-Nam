defmodule TienLenWeb.ProfileLive do
  @moduledoc """
  A player's profile (P1–P4): avatar, numbers from recorded games, standings, and the friend
  button (FR1). On your own profile you pick your avatar.
  """

  use TienLenWeb, :live_view

  alias TienLen.{Accounts, Friends, Presence, Seasons, Stats}
  alias TienLenWeb.Text

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_by_username(username) do
      %{locked_at: nil} = user ->
        if connected?(socket), do: Presence.subscribe()
        {:ok, socket |> assign(user: user, page_title: user.display_name) |> load()}

      _ ->
        {:ok, socket |> put_flash(:error, Text.reason(:not_found)) |> push_navigate(to: ~p"/")}
    end
  end

  defp load(socket) do
    user = socket.assigns.user
    me = socket.assigns.current_user
    week = Seasons.week_start() |> Seasons.standings(1_000) |> Enum.find(&(&1.user_id == user.id))

    assign(socket,
      stats: Stats.profile(user.id),
      standing: Stats.user_standing(user.id),
      week: week,
      relation: Friends.relation(me.id, user.id),
      online: Presence.get_user(user.id),
      coins: TienLen.Economy.balance(user.id),
      # XH3
      titles: TienLen.Shame.titles_of(user.id)
    )
  end

  @impl true
  def handle_event("avatar", %{"avatar" => avatar}, %{assigns: %{relation: :self}} = socket) do
    case Accounts.set_avatar(socket.assigns.current_user, avatar) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(current_user: user, user: user)
         |> put_flash(:info, "Đã đổi ảnh đại diện")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
  end

  def handle_event("friend", %{"do" => action}, socket) do
    me = socket.assigns.current_user.id
    other = socket.assigns.user.id

    result =
      case action do
        "request" -> Friends.request(me, other)
        "accept" -> Friends.accept(me, other)
        "decline" -> Friends.decline(me, other)
        "cancel" -> Friends.cancel(me, other)
        "remove" -> Friends.remove(me, other)
        _ -> {:error, :unknown_command}
      end

    case result do
      {:error, reason} -> {:noreply, socket |> put_flash(:error, Text.reason(reason)) |> load()}
      _ok -> {:noreply, load(socket)}
    end
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:friends_changed}, socket), do: {:noreply, load(socket)}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, assign(socket, :online, Presence.get_user(socket.assigns.user.id))}

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp percent(rate), do: "#{round(rate * 100)}%"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
    >
      <section id="profile" class="card bg-base-200 p-4 flex flex-row items-center gap-4">
        <span id="profile-avatar" class="text-6xl">
          {Text.avatar(@user)}<span
            :if={TienLen.Shop.charm_icon(@user.charm)}
            id="profile-charm"
            class="text-3xl"
            title="Bùa may mắn"
          >{TienLen.Shop.charm_icon(@user.charm)}</span>
        </span>
        <div class="flex-1 min-w-0">
          <h1 class="text-xl font-bold truncate">{@user.display_name}</h1>
          <p class="text-sm text-base-content/60">
            @{@user.username} · tham gia {Calendar.strftime(@user.inserted_at, "%d/%m/%Y")}
          </p>
          <p class="text-sm">
            <span :if={@online} id="profile-online" class="badge badge-success badge-sm">
              {TienLenWeb.Social.place_label(@online.place)}
            </span>
            <span :if={!@online} class="badge badge-ghost badge-sm">Offline</span>
            <span class="ml-1">🪙 {Text.coins(@coins)}</span>
          </p>
          <p :if={@titles != []} id="profile-titles" class="text-sm flex flex-wrap gap-1 mt-1">
            <.link
              :for={t <- @titles}
              navigate={~p"/tuong-xau-ho"}
              class="badge badge-warning badge-sm"
            >
              {t.emoji} {t.name}
            </.link>
          </p>
        </div>
      </section>

      <div :if={@relation != :self} id="friend-actions" class="flex flex-wrap gap-2">
        <button
          :if={@relation == :none}
          id="friend-request"
          phx-click="friend"
          phx-value-do="request"
          class="btn btn-sm btn-primary"
        >
          Kết bạn
        </button>
        <span :if={@relation == :outgoing} class="flex items-center gap-2 text-sm">
          Đã gửi lời mời kết bạn
          <button id="friend-cancel" phx-click="friend" phx-value-do="cancel" class="btn btn-xs">Hủy</button>
        </span>
        <span :if={@relation == :incoming} class="flex items-center gap-2 text-sm">
          {@user.display_name} muốn kết bạn với bạn
          <button
            id="friend-accept"
            phx-click="friend"
            phx-value-do="accept"
            class="btn btn-xs btn-primary"
          >
            Đồng ý
          </button>
          <button id="friend-decline" phx-click="friend" phx-value-do="decline" class="btn btn-xs">Từ chối</button>
        </span>
        <span :if={@relation == :friends} class="flex items-center gap-2 text-sm">
          <span class="badge badge-success">Bạn bè</span>
          <button
            id="friend-remove"
            phx-click="friend"
            phx-value-do="remove"
            class="btn btn-xs btn-ghost"
            data-confirm="Hủy kết bạn?"
          >
            Hủy kết bạn
          </button>
        </span>
        <button :if={@online} phx-click="social:open" phx-value-id={@user.id} class="btn btn-sm">
          Nhắn tin
        </button>
      </div>

      <div id="profile-stats" class="stats stats-vertical sm:stats-horizontal shadow w-full">
        <div class="stat">
          <div class="stat-title">Số ván</div>
          <div id="stat-games" class="stat-value text-2xl">{@stats.games}</div>
          <div class="stat-desc">hạng trung bình {@stats.avg_place || "—"}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Về nhất</div>
          <div id="stat-wins" class="stat-value text-2xl">{@stats.wins}</div>
          <div class="stat-desc">tỉ lệ {percent(@stats.win_rate)}</div>
        </div>
        <div class="stat">
          <div class="stat-title">Chặt heo</div>
          <div id="stat-chops" class="stat-value text-2xl">{@stats.chops}</div>
          <div class="stat-desc">tới trắng {@stats.instant_wins} lần</div>
        </div>
        <div class="stat">
          <div class="stat-title">Coin từ các ván</div>
          <div id="stat-coins" class="stat-value text-2xl">{Text.signed_coins(@stats.coins)}</div>
          <div class="stat-desc">thắng nhiều nhất một ván: {Text.coins(@stats.best_coins)}</div>
        </div>
      </div>

      <p id="profile-ranks" class="text-sm">
        Bảng xếp hạng: {if @standing, do: "hạng #{@standing.rank}", else: "chưa có ván nào"} · Tuần này: {if @week,
          do: "hạng #{@week.rank} (#{@week.wins} lần về nhất)",
          else: "chưa chơi"}
      </p>
      <p class="text-xs text-base-content/60">
        Chỉ tính các ván được ghi lại (ván có máy chơi không tính).
      </p>

      <section :if={@relation == :self} id="avatar-picker" class="card bg-base-200 p-4 space-y-2">
        <h2 class="font-semibold">Chọn ảnh đại diện</h2>
        <div class="flex flex-wrap gap-2">
          <button
            :for={a <- TienLen.Accounts.avatars()}
            phx-click="avatar"
            phx-value-avatar={a}
            class={["btn btn-square text-2xl", a == @user.avatar && "btn-primary"]}
          >
            {a}
          </button>
        </div>
      </section>
    </Layouts.app>
    """
  end
end
