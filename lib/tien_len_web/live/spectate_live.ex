defmodule TienLenWeb.SpectateLive do
  @moduledoc """
  Watching a room without a seat (decisions V1–V4). Spectators get the **public** view only:
  names, card counts, the centre, whose turn, results. No hand is ever sent (the view is built
  with `Room.view(room, nil)`), and the room chat stays with the seated players (V3).
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
        now: now()
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

  def handle_info({:room_updated, _id, _v, _events}, socket) do
    case RoomServer.spectator_view(socket.assigns.room_id) do
      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Phòng đã đóng") |> push_navigate(to: ~p"/")}

      view ->
        {:noreply, put_view(socket, view)}
    end
  end

  def handle_info(:tick, socket), do: {:noreply, assign(socket, :now, now())}
  # room chat, reactions and anything else are not for spectators
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

      <div id="watch-table" class="grid grid-cols-3 gap-3 items-center">
        <div class="col-start-2 justify-self-center">
          <.wseat view={@view} seat={2} secs={@secs} />
        </div>
        <div class="col-start-1 row-start-2 justify-self-start">
          <.wseat view={@view} seat={3} secs={@secs} />
        </div>
        <div
          id="centre"
          class="col-start-2 row-start-2 min-h-32 rounded-box bg-success/15 p-3 flex flex-col items-center justify-center gap-2"
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
        <div class="col-start-3 row-start-2 justify-self-end">
          <.wseat view={@view} seat={1} secs={@secs} />
        </div>
        <div class="col-span-3 row-start-3 justify-self-center">
          <.wseat view={@view} seat={0} secs={@secs} />
        </div>
      </div>

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

  defp wseat(assigns) do
    assigns = assign(assigns, player: player(assigns.view, assigns.seat), game: assigns.view.game)

    ~H"""
    <div
      id={"watch-seat-#{@seat}"}
      class={[
        "rounded-box border px-2 py-1 min-w-24 text-center text-sm",
        @game && @view.status == :playing && @game.current == @seat && "border-primary bg-primary/10"
      ]}
    >
      <p :if={!@player} class="text-base-content/50">Trống</p>
      <div :if={@player}>
        <p class="font-semibold truncate max-w-40">
          <span :if={@player.host}>👑</span> {Text.avatar(@player)} {@player.name}
        </p>
        <div :if={@game && @seat in @game.seats} class="flex items-center justify-center gap-2">
          <.card_backs count={@game.card_counts[@seat]} />
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
