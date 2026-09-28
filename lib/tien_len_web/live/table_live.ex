defmodule TienLenWeb.TableLive do
  @moduledoc """
  The game table for one seated player (RULES T13, T14).

  - Joins the room from this LiveView process (so the room server monitors it: closing the tab
    starts the disconnect timer, T15).
  - Renders only the player's own projection (`TienLen.RoomServer.view/2`): own hand, public
    state, card counts. There are no spectators: anyone who cannot be seated is sent back to
    the lobby (#17).
  - Card selection lives only in this LiveView (never broadcast). Button labels come from
    server-side dry runs (`TienLen.RoomServer.check/3`), not from client code (D1).
  - Seats are drawn relative to the viewer: me at the bottom, the next seat (turn order) to
    the right, then top, then left, i.e. counter-clockwise.
  """

  use TienLenWeb, :live_view

  import TienLenWeb.CardComponents
  import TienLenWeb.ChatComponents

  alias TienLen.{Card, Chat, Invites, Lobby, Presence, RoomServer}
  alias TienLenWeb.Text

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      socket
      |> assign(:room_id, id)
      |> assign(:page_title, "Phòng #{id}")
      |> assign(:view, nil)
      |> assign(:selected, MapSet.new())
      |> assign(:checks, %{})
      |> assign(:deadline, nil)
      |> assign(:now, now())
      # room chat (G4), invite list (G8)
      |> assign(:chat, [])
      |> assign(:chat_key, 0)
      |> assign(:inviting, false)
      |> assign(:candidates, [])
      |> assign(:place, nil)
      # H1 hints (cycled by the button) and the hand order (M2), both local to this page
      |> assign(:hint_i, 0)
      # R1: seat => {emoji, shown until (ms)}
      |> assign(:reactions, %{})
      |> assign(:sort, :rank)

    cond do
      not connected?(socket) ->
        {:ok, socket}

      true ->
        RoomServer.subscribe(id)

        case Lobby.join_room(
               id,
               socket.assigns.player_id,
               socket.assigns.player_name,
               socket.assigns.current_user.avatar
             ) do
          {:ok, _seat} ->
            :timer.send_interval(1_000, :tick)

            chat =
              case Chat.room_history(id, socket.assigns.player_id) do
                {:ok, msgs} -> msgs
                _ -> []
              end

            {:ok, socket |> assign(:chat, chat) |> load()}

          {:error, reason} ->
            {:ok, socket |> put_flash(:error, Text.reason(reason)) |> push_navigate(to: ~p"/")}
        end
    end
  end

  # -- events -------------------------------------------------------------------

  @impl true
  def handle_event("toggle", %{"card" => code}, socket) do
    with {:ok, card} <- Card.parse(code),
         true <- card in my_hand(socket) do
      selected = socket.assigns.selected

      selected =
        if card in selected, do: MapSet.delete(selected, card), else: MapSet.put(selected, card)

      {:noreply, socket |> assign(:selected, selected) |> refresh_checks()}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("clear", _params, socket),
    do: {:noreply, socket |> assign(:selected, MapSet.new()) |> refresh_checks()}

  def handle_event("play", _params, socket),
    do: act(socket, &RoomServer.play(&1, &2, selected_list(socket)))

  def handle_event("chop", _params, socket),
    do: act(socket, &RoomServer.chop(&1, &2, selected_list(socket)))

  def handle_event("pass", _params, socket), do: act(socket, &RoomServer.pass/2)
  def handle_event("start", _params, socket), do: act(socket, &Lobby.start_game/2)

  # The host proposes a stake; the room server validates it (host only, between games, C3).
  def handle_event("set_stake", %{"stake" => stake}, socket) do
    stake =
      case Integer.parse(to_string(stake) |> String.trim()) do
        {n, ""} -> n
        _ -> :invalid
      end

    act(socket, &RoomServer.set_stake(&1, &2, stake))
  end

  # G4: room chat, also during a game (CH4)
  def handle_event("chat_send", %{"text" => text}, socket) do
    case Chat.send_room(socket.assigns.room_id, socket.assigns.player_id, text) do
      :ok -> {:noreply, update(socket, :chat_key, &(&1 + 1))}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
  end

  # G8: the invite list
  def handle_event("toggle_invite", _params, socket) do
    inviting = !socket.assigns.inviting

    {:noreply,
     socket
     |> assign(:inviting, inviting)
     |> assign(
       :candidates,
       if(inviting, do: Invites.candidates(socket.assigns.player_id), else: [])
     )}
  end

  def handle_event("invite", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(to_string(id)),
         {:ok, invite} <- Invites.invite(socket.assigns.player_id, id, socket.assigns.room_id) do
      {:noreply, put_flash(socket, :info, "Đã mời #{invite.to_name}")}
    else
      {:error, reason} -> {:noreply, put_flash(socket, :error, Text.reason(reason))}
      _ -> {:noreply, socket}
    end
  end

  # B1: the host adds / removes bots (the room server checks host, waiting, stake 0)
  def handle_event("add_bot", %{"level" => level}, socket) when level in ["easy", "normal"],
    do: act(socket, &RoomServer.add_bot(&1, &2, String.to_existing_atom(level)))

  def handle_event("remove_bot", %{"seat" => seat}, socket) do
    case Integer.parse(to_string(seat)) do
      {seat, ""} -> act(socket, &RoomServer.remove_bot(&1, &2, seat))
      _ -> {:noreply, socket}
    end
  end

  # H1: each click selects the next legal play, weakest first
  def handle_event("hint", _params, socket) do
    case RoomServer.hints(socket.assigns.room_id, socket.assigns.player_id) do
      [] ->
        {:noreply, put_flash(socket, :error, "Không có bài nào đánh được, hãy bỏ lượt")}

      hints ->
        i = rem(socket.assigns.hint_i, length(hints))

        {:noreply,
         socket
         |> assign(selected: MapSet.new(Enum.at(hints, i)), hint_i: i + 1)
         |> refresh_checks()}
    end
  end

  # R1: an emoji on my seat for everyone (3 per 5 s; ignored when too fast)
  def handle_event("react", %{"emoji" => emoji}, socket) do
    if TienLen.RateLimit.hit({:react, socket.assigns.player_id}, 3, 5_000) == :ok do
      RoomServer.react(socket.assigns.room_id, socket.assigns.player_id, emoji)
    end

    {:noreply, socket}
  end

  # M2: hand order, by rank (default) or by suit
  def handle_event("sort", _params, socket),
    do:
      {:noreply, assign(socket, :sort, if(socket.assigns.sort == :rank, do: :suit, else: :rank))}

  # G11: the host hides the room from the lobby list, or shows it again
  def handle_event("toggle_private", _params, socket) do
    private? = !(socket.assigns.view && socket.assigns.view.private)
    act(socket, &RoomServer.set_private(&1, &2, private?))
  end

  def handle_event("leave", _params, socket) do
    Lobby.leave_room(socket.assigns.room_id, socket.assigns.player_id)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  # Unknown or malformed events (e.g. from a tampered client) are ignored.
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp act(socket, fun) do
    case fun.(socket.assigns.room_id, socket.assigns.player_id) do
      :ok -> {:noreply, socket |> assign(:selected, MapSet.new()) |> load()}
      {:error, reason} -> {:noreply, put_flash(socket, :error, Text.reason(reason))}
    end
  end

  # -- updates ------------------------------------------------------------------

  @impl true
  # AD6 / F5: an admin closed the room (a running game is cancelled).
  def handle_info({:room_updated, _id, _version, [{:closed_by_admin}]}, socket) do
    {:noreply,
     socket
     |> put_flash(
       :error,
       "Phòng đã bị quản trị viên đóng. Ván đang chơi (nếu có) bị hủy, không tính coin."
     )
     |> push_navigate(to: ~p"/")}
  end

  def handle_info({:room_updated, _id, _version, _events}, socket), do: {:noreply, load(socket)}

  def handle_info({:room_chat, _id, msg}, socket) do
    # only a seated player (who has a view) reads the room chat (G4)
    if socket.assigns.view,
      do: {:noreply, update(socket, :chat, &Enum.take(&1 ++ [msg], -50))},
      else: {:noreply, socket}
  end

  def handle_info({:room_chat_deleted, _id, msg_id}, socket),
    do: {:noreply, update(socket, :chat, &Enum.reject(&1, fn m -> m.id == msg_id end))}

  def handle_info({:reaction, _id, seat, emoji}, socket),
    do: {:noreply, update(socket, :reactions, &Map.put(&1, seat, {emoji, now() + 3_000}))}

  def handle_info(:tick, socket) do
    t = now()

    {:noreply,
     socket
     |> assign(:now, t)
     |> update(:reactions, fn r -> Map.reject(r, fn {_seat, {_e, until}} -> until <= t end) end)}
  end

  def handle_info(_unexpected, socket), do: {:noreply, socket}

  defp load(socket) do
    case RoomServer.view(socket.assigns.room_id, socket.assigns.player_id) do
      {:error, reason} ->
        socket |> put_flash(:error, Text.reason(reason)) |> push_navigate(to: ~p"/")

      view ->
        hand = (view.game && view.game.hand) || []
        selected = MapSet.filter(socket.assigns.selected, &(&1 in hand))
        deadline = view.turn_ms_left && now() + view.turn_ms_left

        socket
        |> assign(view: view, selected: selected, deadline: deadline, now: now(), hint_i: 0)
        |> refresh_checks()
        |> track_place(view)
    end
  end

  # G6: where this player is, for the online list (only when it changes)
  defp track_place(socket, view) do
    place = if view.status == :playing, do: "playing", else: "room"

    if place != socket.assigns.place do
      Presence.move(self(), socket.assigns.current_user, place, socket.assigns.room_id)
    end

    assign(socket, :place, place)
  end

  # Server-side dry runs for the buttons (no rule logic in the browser).
  defp refresh_checks(%{assigns: %{view: %{status: :playing}}} = socket) do
    %{room_id: id, player_id: pid} = socket.assigns
    cards = selected_list(socket)

    checks = %{
      play:
        if(cards == [], do: {:error, :empty}, else: RoomServer.check(id, pid, {:play, cards})),
      pass: RoomServer.check(id, pid, :pass),
      chop:
        if(length(cards) == 8,
          do: RoomServer.check(id, pid, {:chop, cards}),
          else: {:error, :not_four_pair}
        )
    }

    assign(socket, :checks, checks)
  end

  defp refresh_checks(socket), do: assign(socket, :checks, %{})

  defp my_hand(socket),
    do: (socket.assigns.view && socket.assigns.view.game && socket.assigns.view.game.hand) || []

  defp sorted_hand(hand, :rank), do: Card.sort(hand)
  defp sorted_hand(hand, :suit), do: Enum.sort_by(hand, &{Card.suit_index(&1.suit), &1.rank})

  defp selected_list(socket), do: socket.assigns.selected |> MapSet.to_list() |> Card.sort()
  defp now, do: System.monotonic_time(:millisecond)

  # -- rendering helpers ----------------------------------------------------------

  # Seat shown at a table position (0 = me/bottom, 1 = right, 2 = top, 3 = left).
  defp seat_at(view, pos), do: rem(view.me + pos, 4)

  defp player(view, seat), do: Enum.find(view.players, &(&1.seat == seat))

  defp seconds_left(assigns) do
    case assigns.deadline do
      nil -> nil
      deadline -> max(div(deadline - assigns.now + 999, 1000), 0)
    end
  end

  defp place_of(view, seat) do
    case view.game && view.game.ranking do
      nil ->
        nil

      ranking ->
        n = length(ranking)

        Enum.find_value(Enum.with_index(ranking, 1), fn {group, i} ->
          if seat in group, do: {i, n}
        end)
    end
  end

  defp medal(1), do: "🥇"
  defp medal(2), do: "🥈"
  defp medal(3), do: "🥉"
  defp medal(_), do: ""

  # -- render -------------------------------------------------------------------

  @impl true
  def render(%{view: nil} = assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
    >
      <p id="joining" class="text-center text-base-content/70">Đang vào phòng…</p>
    </Layouts.app>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :secs, seconds_left(assigns))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
      wide
      action_bar
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <p>
          Phòng <span id="room-code" class="font-mono font-semibold">{@room_id}</span>
          <span class="text-base-content/60">· ván đã chơi: {@view.games_played}</span>
          <span id="stake" class="badge badge-outline">
            {if @view.stake == 0,
              do: "Chơi vui",
              else: "Cược #{Text.coins(@view.stake)} (cần #{Text.coins(@view.min_balance)} coin)"}
          </span>
        </p>
        <div class="flex items-center gap-1">
          <span :if={@view.private} id="private-badge" class="badge badge-info">Riêng tư</span>
          <span
            :if={(@view[:spectators] || 0) > 0}
            id="spectator-count"
            class="badge badge-ghost"
            title="Người đang xem"
          >
            👀 {@view.spectators}
          </span>
          <button
            id="copy-link"
            phx-hook="CopyLink"
            data-url={url(~p"/phong/#{@room_id}")}
            class="btn btn-ghost btn-sm"
          >
            Chép link
          </button>
          <button
            id="leave"
            phx-click="leave"
            class="btn btn-ghost btn-sm"
            data-confirm="Rời phòng?"
          >
            Rời phòng
          </button>
        </div>
      </div>

      <%!-- M3: phones put the three opponents in one row (left, top, right) above a full-width
           centre; from sm up the classic cross layout --%>
      <div
        id="table"
        class="grid grid-cols-3 sm:grid-rows-[auto_1fr_auto] gap-2 sm:gap-3 items-center"
      >
        <div class="col-start-2 row-start-1 min-w-0 sm:justify-self-center">
          <.seat view={@view} seat={seat_at(@view, 2)} secs={@secs} reactions={@reactions} />
        </div>
        <div class="col-start-1 row-start-1 sm:row-start-2 min-w-0 sm:justify-self-start">
          <.seat view={@view} seat={seat_at(@view, 3)} secs={@secs} reactions={@reactions} />
        </div>
        <div class="col-start-3 row-start-1 sm:row-start-2 min-w-0 sm:justify-self-end">
          <.seat view={@view} seat={seat_at(@view, 1)} secs={@secs} reactions={@reactions} />
        </div>

        <div
          id="centre"
          class="col-span-3 row-start-2 sm:col-span-1 sm:col-start-2 min-h-32 sm:min-h-40 rounded-box bg-success/15 p-3 flex flex-col items-center justify-center gap-2"
        >
          <.centre view={@view} />
        </div>

        <div class="col-span-3 row-start-3 justify-self-center">
          <.seat view={@view} seat={@view.me} secs={@secs} reactions={@reactions} />
        </div>
      </div>

      <.results :if={@view.status == :waiting and @view.game} view={@view} />
      <.waiting
        :if={@view.status == :waiting}
        view={@view}
        inviting={@inviting}
        candidates={@candidates}
      />

      <section :if={@view.status == :playing} class="space-y-3">
        <p
          :if={@view.game.must_include}
          id="must-include"
          class="text-center text-warning font-semibold"
        >
          Nước đầu phải có {Text.card(@view.game.must_include)}
        </p>

        <%!-- M4: one row at every width. Each card slot shrinks to share the free space
             (the last card keeps its full width), so cards overlap only when they must and
             by as little as possible; the card image overflows under the next slot.
             Every slot is `relative`: a lifted (translated) card would otherwise be painted
             above its right-hand neighbour and hide its corner. The selection ring is on
             the image, not on the (narrow) slot. --%>
        <div id="hand" class="flex w-full justify-center pt-4 px-1">
          <button
            :for={card <- sorted_hand(@view.game.hand, @sort)}
            id={"card-" <> Card.to_code(card)}
            phx-click="toggle"
            phx-value-card={Card.to_code(card)}
            class={[
              "relative min-w-0 basis-0 flex-1 max-w-[52px] sm:max-w-[68px] text-left",
              "last:flex-none last:basis-auto last:w-12 sm:last:w-16",
              "transition-transform",
              card in @selected && "-translate-y-3"
            ]}
            aria-pressed={to_string(card in @selected)}
          >
            <.card
              card={card}
              class={
                "w-12 sm:w-16 max-w-none " <>
                  if(card in @selected, do: "ring-2 ring-primary ring-offset-1", else: "")
              }
            />
          </button>
        </div>

        <div
          id="actions"
          class="sticky bottom-0 z-30 bg-base-100/95 py-2 flex flex-wrap justify-center gap-2"
        >
          <button id="hint" phx-click="hint" class="btn btn-outline btn-sm sm:btn-md">Gợi ý</button>
          <button id="sort" phx-click="sort" class="btn btn-ghost btn-sm sm:btn-md">
            {if @sort == :rank, do: "Xếp theo chất", else: "Xếp theo số"}
          </button>
          <button
            id="play"
            phx-click="play"
            class="btn btn-primary"
            disabled={@checks[:play] != :ok}
          >
            {if @checks[:play] == :ok, do: "Đánh", else: Text.reason(@checks[:play])}
          </button>
          <button :if={@checks[:pass] == :ok} id="pass" phx-click="pass" class="btn">Bỏ lượt</button>
          <button
            :if={@checks[:chop] == :ok and @view.game.current != @view.me}
            id="chop"
            phx-click="chop"
            class="btn btn-error"
          >
            Chặt ngoài lượt!
          </button>
          <button :if={MapSet.size(@selected) > 0} id="clear" phx-click="clear" class="btn btn-ghost">
            Bỏ chọn
          </button>
        </div>
      </section>

      <div id="reactions" class="flex justify-center gap-1">
        <button
          :for={e <- TienLen.Chat.reactions()}
          phx-click="react"
          phx-value-emoji={e}
          class="btn btn-ghost btn-sm text-xl"
          title="Biểu cảm"
        >
          {e}
        </button>
      </div>

      <.chat_box
        id="room-chat"
        title="Chat phòng"
        messages={@chat}
        me={@player_id}
        send_event="chat_send"
        phrases
        key={@chat_key}
      />
    </Layouts.app>
    """
  end

  attr :view, :map, required: true
  attr :seat, :integer, required: true
  attr :secs, :integer, default: nil
  attr :reactions, :map, default: %{}

  defp seat(assigns) do
    assigns =
      assigns
      |> assign(:player, player(assigns.view, assigns.seat))
      |> assign(:game, assigns.view.game)

    ~H"""
    <div
      id={"seat-#{@seat}"}
      class={[
        "rounded-box border px-2 py-1 sm:px-3 sm:py-2 w-full sm:w-auto sm:min-w-32 text-center text-sm sm:text-base",
        @game && @game.current == @seat && @view.status == :playing && "border-primary bg-primary/10",
        !(@game && @game.current == @seat && @view.status == :playing) && "border-base-300"
      ]}
    >
      <p :if={@player == nil} class="text-base-content/50">Trống</p>
      <div :if={@player} class="relative">
        <span
          :if={@reactions[@seat]}
          id={"reaction-#{@seat}"}
          class="absolute -top-6 left-1/2 -translate-x-1/2 text-3xl animate-bounce"
        >
          {elem(@reactions[@seat], 0)}
        </span>
        <p class="font-semibold truncate max-w-40">
          <span :if={@player.host} title="Chủ phòng">👑</span>
          {TienLenWeb.Text.avatar(@player)} {@player.name}
          <span :if={@seat == @view.me} class="text-xs text-base-content/60">(bạn)</span>
          <span :if={@player.bot} class="badge badge-info badge-xs" title="Máy chơi">🤖</span>
          <span :if={!@player.connected} class="badge badge-ghost badge-xs">mất kết nối</span>
        </p>
        <button
          :if={@player.bot && @view.host == @view.me && @view.status == :waiting}
          id={"remove-bot-#{@seat}"}
          phx-click="remove_bot"
          phx-value-seat={@seat}
          class="btn btn-ghost btn-xs"
        >
          Bỏ máy
        </button>
        <p :if={@view.balances[@seat]} class="text-xs tabular-nums">
          🪙 {Text.coins(@view.balances[@seat])}
          <span
            :if={(@view.coin_deltas[@seat] || 0) != 0}
            id={"delta-#{@seat}"}
            class={[
              "badge badge-xs",
              if(@view.coin_deltas[@seat] > 0, do: "badge-success", else: "badge-error")
            ]}
          >
            {Text.signed_coins(@view.coin_deltas[@seat])}
          </span>
        </p>
        <div
          :if={@game && @seat in @game.seats}
          class="flex items-center justify-center gap-2 text-sm"
        >
          <.card_backs count={@game.card_counts[@seat]} />
          <span :if={@seat in @game.passed} class="badge badge-sm">Bỏ lượt</span>
          <span :if={@seat in @game.removed} class="badge badge-sm badge-ghost">Bị loại</span>
          <span :if={place_of(@view, @seat)} class="text-sm">
            {medal(elem(place_of(@view, @seat), 0))} {Text.place(
              elem(place_of(@view, @seat), 0),
              elem(place_of(@view, @seat), 1)
            )}
          </span>
          <span
            :if={@game.current == @seat and @view.status == :playing and @secs}
            id={"timer-#{@seat}"}
            class="badge badge-primary tabular-nums"
          >
            {@secs}s
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :view, :map, required: true

  defp centre(assigns) do
    ~H"""
    <%= cond do %>
      <% @view.game && @view.game.centre -> %>
        <div class="flex flex-wrap justify-center gap-1">
          <.card :for={card <- @view.game.centre.cards} card={card} class="w-10 sm:w-14" />
        </div>
        <p class="text-sm">
          {Text.combo_type(@view.game.centre.type)} · {player(@view, @view.game.centre.owner).name}
          <span
            :if={@view.game.centre.chop_context}
            id="chop-context"
            class="badge badge-error badge-sm"
          >
            chặt
          </span>
        </p>
      <% @view.status == :playing -> %>
        <p class="text-base-content/70">
          Bàn trống — {player(@view, @view.game.current).name} đi trước
        </p>
      <% true -> %>
        <p class="text-base-content/70">Chưa bắt đầu</p>
    <% end %>
    """
  end

  attr :view, :map, required: true
  attr :inviting, :boolean, default: false
  attr :candidates, :list, default: []

  defp waiting(assigns) do
    assigns = assign(assigns, :connected, Enum.count(assigns.view.players, & &1.connected))

    ~H"""
    <section id="waiting" class="text-center space-y-2">
      <button
        :if={@view.host == @view.me}
        id="start"
        phx-click="start"
        class="btn btn-primary"
        disabled={@connected < 2}
      >
        {if @view.game, do: "Ván mới", else: "Bắt đầu ván"}
      </button>
      <p :if={@view.host == @view.me and @connected < 2} class="text-sm text-base-content/70">
        Cần ít nhất 2 người. Gửi mã phòng <span class="font-mono">{@view.id}</span> cho bạn bè.
      </p>
      <p :if={@view.host != @view.me} class="text-base-content/70">Chờ chủ phòng bắt đầu…</p>

      <form
        :if={@view.host == @view.me}
        id="stake-form"
        phx-submit="set_stake"
        class="flex items-center justify-center gap-2"
      >
        <input
          type="number"
          name="stake"
          min="0"
          step="1"
          value={@view.stake}
          class="input input-bordered input-sm w-32"
        />
        <button type="submit" class="btn btn-sm">Đổi cược</button>
      </form>

      <div class="flex flex-wrap justify-center gap-2">
        <button
          :if={length(@view.players) < 4}
          id="toggle-invite"
          phx-click="toggle_invite"
          class="btn btn-sm btn-outline"
        >
          {if @inviting, do: "Đóng danh sách mời", else: "Mời người chơi"}
        </button>
        <button
          :if={@view.host == @view.me}
          id="toggle-private"
          phx-click="toggle_private"
          class="btn btn-sm btn-ghost"
        >
          {if @view.private, do: "Hiện phòng trong sảnh", else: "Chuyển sang riêng tư"}
        </button>
      </div>

      <div
        :if={@view.host == @view.me and length(@view.players) < 4}
        id="bots"
        class="flex flex-wrap justify-center items-center gap-2"
      >
        <%= if @view.stake == 0 do %>
          <button
            :for={{level, label} <- TienLen.Bot.levels()}
            id={"add-bot-#{level}"}
            phx-click="add_bot"
            phx-value-level={level}
            class="btn btn-sm btn-outline btn-info"
          >
            + Máy ({label})
          </button>
        <% else %>
          <span class="text-xs text-base-content/60">
            Chỉ thêm máy được ở phòng chơi vui (cược 0).
          </span>
        <% end %>
      </div>
      <p :if={Enum.any?(@view.players, & &1.bot)} class="text-xs text-base-content/60">
        Ván có máy chơi không tính coin và không vào bảng xếp hạng.
      </p>

      <ul
        :if={@inviting}
        id="invite-list"
        class="mx-auto max-w-sm divide-y divide-base-300 rounded-box bg-base-200 text-left"
      >
        <li :if={@candidates == []} class="p-2 text-sm text-base-content/60">
          Không có ai đang rảnh để mời. Hãy gửi link phòng (nút "Chép link").
        </li>
        <li :for={c <- @candidates} id={"candidate-#{c.id}"} class="p-2 flex items-center gap-2">
          <span class={["flex-1 truncate", c.invites_off && "text-base-content/40"]}>
            <span :if={c.friend} title="Bạn bè">⭐</span> {Text.avatar(c)} {c.name}
          </span>
          <span :if={c.invites_off} class="text-xs text-base-content/50">không nhận lời mời</span>
          <button
            :if={!c.invites_off}
            phx-click="invite"
            phx-value-id={c.id}
            class="btn btn-xs btn-primary"
          >
            Mời
          </button>
        </li>
      </ul>

      <p
        :if={@view.stake > 0 and (@view.balances[@view.me] || 0) < @view.min_balance}
        id="not-eligible"
        class="text-sm text-warning"
      >
        Bạn cần ít nhất {Text.coins(@view.min_balance)} coin để được chia bài ở mức cược này.
      </p>
    </section>
    """
  end

  attr :view, :map, required: true

  defp results(assigns) do
    ~H"""
    <section id="results" class="card bg-base-200 p-4 space-y-3">
      <h2 class="text-lg font-bold">Kết quả ván {@view.games_played}</h2>

      <div :for={w <- @view.game.instant_winners} id={"instant-#{w.seat}"} class="space-y-1">
        <p>
          <strong>{player(@view, w.seat).name}</strong> tới trắng: {Text.instant(w.type)}
        </p>
        <div class="flex flex-wrap gap-1">
          <.card :for={card <- w.hand} card={card} class="w-10" />
        </div>
      </div>

      <ul :if={@view.coin_deltas != %{}} id="coin-results" class="space-y-1">
        <li :for={{seat, delta} <- Enum.sort(@view.coin_deltas)}>
          🪙 {(player(@view, seat) || %{name: "?"}).name}:
          <span class={if(delta > 0, do: "text-success", else: "text-error")}>
            {Text.signed_coins(delta)}
          </span>
        </li>
      </ul>

      <ol id="ranking" class="space-y-1">
        <li :for={{group, i} <- Enum.with_index(@view.game.ranking || [], 1)}>
          {medal(i)} {Text.place(i, length(@view.game.ranking))}: {group
          |> Enum.map(&(player(@view, &1) || %{name: "?"}).name)
          |> Enum.join(", ")}
        </li>
      </ol>
    </section>
    """
  end
end
