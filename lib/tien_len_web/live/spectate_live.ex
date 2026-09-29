defmodule TienLenWeb.SpectateLive do
  @moduledoc """
  Watching a room without a seat (decisions V1–V4). Spectators get the **public** view only:
  names, card counts, the centre, whose turn, results. No hand is ever sent (the view is built
  with `Room.view(room, nil)`), and the room chat stays with the seated players (V3); only the
  commentator's latest line is shown (BL3). Throws and card backs are visible too (TH3, SH1).
  A player seated in the room is sent to the table instead.
  """

  use TienLenWeb, :live_view

  import TienLenWeb.CardComponents

  alias TienLen.{Presence, RoomServer}
  alias TienLenWeb.Text

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    socket =
      assign(socket,
        room_id: id,
        page_title: "Xem phòng #{id}",
        view: nil,
        deadline: nil,
        now: now(),
        # batch 14: throw marks, runaway slippers, the commentator's latest line
        marks: %{},
        runaways: %{},
        ticker: nil
      )

    cond do
      not connected?(socket) ->
        {:ok, socket}

      RoomServer.seated?(id, socket.assigns.current_user.id) == true ->
        {:ok, push_navigate(socket, to: ~p"/phong/#{id}")}

      true ->
        RoomServer.subscribe(id)

        case RoomServer.watch(id) do
          {:ok, view} ->
            Presence.move(self(), socket.assigns.current_user, "watching", id)
            :timer.send_interval(1_000, :tick)
            {:ok, put_view(socket, view)}

          {:error, reason} ->
            {:ok, socket |> put_flash(:error, Text.reason(reason)) |> push_navigate(to: ~p"/")}
        end
    end
  end

  defp put_view(socket, view) do
    assign(socket,
      view: view,
      deadline: view.turn_ms_left && now() + view.turn_ms_left,
      now: now()
    )
  end

  @impl true
  def handle_info({:room_updated, _id, _v, [{:closed_by_admin}]}, socket),
    do: {:noreply, socket |> put_flash(:error, "Phòng đã bị đóng") |> push_navigate(to: ~p"/")}

  def handle_info({:room_updated, _id, _v, events}, socket) do
    ran = for {:removed, seat} <- events, {:left, seat} in events, do: seat

    socket =
      update(
        socket,
        :runaways,
        &Enum.reduce(ran, &1, fn s, acc -> Map.put(acc, s, now() + 4_000) end)
      )

    case RoomServer.spectator_view(socket.assigns.room_id) do
      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Phòng đã đóng") |> push_navigate(to: ~p"/")}

      view ->
        {:noreply, put_view(socket, view)}
    end
  end

  # TH1: spectators see throws (they cannot throw)
  def handle_info({:thrown, _id, from, to, item_id}, socket) do
    case TienLen.Throws.item(item_id) do
      nil ->
        {:noreply, socket}

      item ->
        {:noreply,
         socket
         |> push_event("throw", %{
           from: "watch-seat-#{from}",
           to: "watch-seat-#{to}",
           emoji: item.emoji
         })
         |> update(
           :marks,
           &Map.put(
             &1,
             to,
             {item.emoji <> item.mark, now() + 3_700, System.unique_integer([:positive])}
           )
         )}
    end
  end

  # BL3: only the commentator's lines, as a ticker (the room chat stays with the players, V3)
  def handle_info({:room_chat, _id, %{system: true, text: text}}, socket),
    do: {:noreply, assign(socket, :ticker, {text, now() + 5_000})}

  def handle_info(:tick, socket) do
    t = now()

    {:noreply,
     socket
     |> assign(:now, t)
     |> update(:marks, fn m -> Map.reject(m, fn {_s, {_e, until, _n}} -> until <= t end) end)
     |> update(:runaways, fn r -> Map.reject(r, fn {_s, until} -> until <= t end) end)
     |> update(:ticker, fn
       {_text, until} when until <= t -> nil
       ticker -> ticker
     end)}
  end

  # player chat, reactions and anything else are not for spectators
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp now, do: System.monotonic_time(:millisecond)
  defp player(view, seat), do: Enum.find(view.players, &(&1.seat == seat))

  defp secs(%{deadline: nil}), do: nil
  defp secs(%{deadline: d, now: now}), do: max(div(d - now + 999, 1000), 0)

  @impl true
  def render(%{view: nil} = assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
    >
      <p class="text-center text-base-content/70">Đang vào xem…</p>
    </Layouts.app>
    """
  end

  def render(assigns) do
    assigns = assign(assigns, :secs, secs(assigns))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
      wide
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <p>
          👀 Đang xem phòng <span class="font-mono font-semibold">{@room_id}</span>
          <span id="spectators" class="badge badge-ghost">{@view.spectators} người xem</span>
          <span class="badge badge-outline">
            {if @view.stake == 0, do: "Chơi vui", else: "Cược #{Text.coins(@view.stake)}"}
          </span>
        </p>
        <div class="flex gap-1">
          <.link
            :if={@view.status == :waiting and length(@view.players) < 4}
            id="join-from-watch"
            navigate={~p"/phong/#{@room_id}"}
            class="btn btn-sm btn-primary"
          >
            Vào chơi
          </.link>
          <.link navigate={~p"/"} class="btn btn-sm btn-ghost">Về sảnh</.link>
        </div>
      </div>

      <%!-- M3: same phone layout as the table: opponents in one row, full-width centre --%>
      <div
        id="watch-table"
        phx-hook="Throws"
        class="grid grid-cols-3 gap-2 sm:gap-3 items-center"
      >
        <div class="col-start-2 row-start-1 min-w-0 sm:justify-self-center">
          <.wseat view={@view} seat={2} secs={@secs} marks={@marks} runaways={@runaways} />
        </div>
        <div class="col-start-1 row-start-1 sm:row-start-2 min-w-0 sm:justify-self-start">
          <.wseat view={@view} seat={3} secs={@secs} marks={@marks} runaways={@runaways} />
        </div>
        <div
          id="centre"
          class="col-span-3 row-start-2 sm:col-span-1 sm:col-start-2 min-h-32 rounded-box bg-success/15 p-3 flex flex-col items-center justify-center gap-2"
        >
          <%= cond do %>
            <% @view.game && @view.game.centre -> %>
              <div class="flex flex-wrap justify-center gap-1">
                <.card :for={c <- @view.game.centre.cards} card={c} class="w-10 sm:w-14" />
              </div>
              <p class="text-sm">
                {Text.combo_type(@view.game.centre.type)} · {(player(@view, @view.game.centre.owner) ||
                                                                %{name: "?"}).name}
              </p>
            <% @view.status == :playing -> %>
              <p class="text-base-content/70">Bàn trống</p>
            <% true -> %>
              <p class="text-base-content/70">Chờ ván mới</p>
          <% end %>
        </div>
        <div class="col-start-3 row-start-1 sm:row-start-2 min-w-0 sm:justify-self-end">
          <.wseat view={@view} seat={1} secs={@secs} marks={@marks} runaways={@runaways} />
        </div>
        <div class="col-span-3 row-start-3 justify-self-center">
          <.wseat view={@view} seat={0} secs={@secs} marks={@marks} runaways={@runaways} />
        </div>
      </div>

      <p
        :if={@ticker}
        id="commentary"
        class="ticker text-center text-sm font-semibold text-warning"
        aria-live="polite"
      >
        {elem(@ticker, 0)}
      </p>

      <section
        :if={@view.status == :waiting and @view.game}
        id="watch-results"
        class="card bg-base-200 p-3 space-y-1 text-sm"
      >
        <h2 class="font-semibold">Kết quả ván {@view.games_played}</h2>
        <p :for={w <- @view.game.instant_winners}>
          {(player(@view, w.seat) || %{name: "?"}).name} tới trắng: {Text.instant(w.type)}
        </p>
        <p :for={{group, i} <- Enum.with_index(@view.game.ranking || [], 1)}>
          {Text.place(i, length(@view.game.ranking))}: {Enum.map_join(
            group,
            ", ",
            &(player(@view, &1) || %{name: "?"}).name
          )}
        </p>
      </section>
    </Layouts.app>
    """
  end

  attr :view, :map, required: true
  attr :seat, :integer, required: true
  attr :secs, :integer, default: nil
  attr :marks, :map, default: %{}
  attr :runaways, :map, default: %{}

  defp wseat(assigns) do
    assigns = assign(assigns, player: player(assigns.view, assigns.seat), game: assigns.view.game)

    ~H"""
    <div
      id={"watch-seat-#{@seat}"}
      class={[
        "relative rounded-box border px-2 py-1 w-full sm:w-auto sm:min-w-24 text-center text-sm",
        @game && @view.status == :playing && @game.current == @seat && "border-primary bg-primary/10"
      ]}
    >
      <p :if={!@player} class="text-base-content/50">
        Trống <span :if={@runaways[@seat]} class="slipper-drop text-2xl">🩴</span>
      </p>
      <span
        :if={@player && @marks[@seat]}
        id={"watch-mark-#{@seat}-#{elem(@marks[@seat], 2)}"}
        class="throw-mark absolute inset-0 z-20 flex items-center justify-center text-3xl pointer-events-none"
        aria-hidden="true"
      >
        {elem(@marks[@seat], 0)}
      </span>
      <div :if={@player}>
        <p class="font-semibold truncate max-w-40">
          <span :if={@player.host}>👑</span> {Text.avatar(@player)} {@player.name}
        </p>
        <div :if={@game && @seat in @game.seats} class="flex items-center justify-center gap-2">
          <.card_backs count={@game.card_counts[@seat]} back={@player.card_back} />
          <span :if={@seat in @game.passed} class="badge badge-sm">Bỏ lượt</span>
          <span
            :if={@view.status == :playing and @game.current == @seat and @secs}
            class="badge badge-primary tabular-nums"
          >
            {@secs}s
          </span>
        </div>
      </div>
    </div>
    """
  end
end
