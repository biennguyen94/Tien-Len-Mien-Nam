defmodule TienLenWeb.ReplayLive do
  @moduledoc """
  Replay of a recorded game (V5, V6), step by step, with every hand shown. Only the players of
  that game and admins may open it.
  """

  use TienLenWeb, :live_view

  import TienLenWeb.CardComponents

  alias TienLen.{Card, Replay, Stats}
  alias TienLenWeb.Text

  @autoplay_ms 1_000

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    game_id =
      case Integer.parse(id) do
        {n, ""} -> n
        _ -> nil
      end

    case Stats.replay(game_id, socket.assigns.current_user) do
      {:ok, %{game: game, replay: replay}} ->
        {:ok,
         assign(socket,
           page_title: "Xem lại ván",
           game: game,
           names: Replay.names(replay),
           frames: Replay.frames(replay),
           step: 0,
           playing: false
         )}

      {:error, reason} ->
        message =
          if reason == :no_replay,
            do: "Ván này không có dữ liệu xem lại",
            else: Text.reason(if reason == :forbidden, do: :forbidden, else: :not_found)

        {:ok, socket |> put_flash(:error, message) |> push_navigate(to: ~p"/lich-su")}
    end
  end

  @impl true
  def handle_event("go", %{"to" => to}, socket), do: {:noreply, go(socket, to)}

  def handle_event("autoplay", _params, socket) do
    playing = !socket.assigns.playing
    if playing, do: Process.send_after(self(), :autoplay, @autoplay_ms)
    {:noreply, assign(socket, :playing, playing)}
  end

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:autoplay, %{assigns: %{playing: true}} = socket) do
    socket = go(socket, "next")

    if socket.assigns.step < last(socket) do
      Process.send_after(self(), :autoplay, @autoplay_ms)
      {:noreply, socket}
    else
      {:noreply, assign(socket, :playing, false)}
    end
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp last(socket), do: length(socket.assigns.frames) - 1

  defp go(socket, to) do
    step =
      case to do
        "first" -> 0
        "prev" -> socket.assigns.step - 1
        "next" -> socket.assigns.step + 1
        "last" -> last(socket)
        n -> String.to_integer(n)
      end

    assign(socket, :step, step |> max(0) |> min(last(socket)))
  rescue
    ArgumentError -> socket
  end

  # -- text -------------------------------------------------------------------------

  defp name(names, seat), do: Map.get(names, seat, "?")
  defp cards_text(cards), do: Enum.map_join(cards, " ", &Card.display/1)

  defp describe(%{type: :deal}, _names), do: "Chia bài"

  defp describe(%{type: :played} = e, names),
    do: "#{name(names, e.seat)} đánh #{Text.combo_type(e.combo)}: #{cards_text(e.cards)}"

  defp describe(%{type: :chopped} = e, names),
    do: "#{name(names, e.seat)} chặt ngoài lượt: #{cards_text(e.cards)}"

  defp describe(%{type: :passed} = e, names), do: "#{name(names, e.seat)} bỏ lượt"
  defp describe(%{type: :timed_out} = e, names), do: "#{name(names, e.seat)} hết giờ"
  defp describe(%{type: :removed} = e, names), do: "#{name(names, e.seat)} bị loại"
  defp describe(%{type: :round_ended} = e, names), do: "Hết vòng, #{name(names, e.seat)} đi đầu"
  defp describe(%{type: :lead_moved} = e, names), do: "#{name(names, e.seat)} được đi đầu"

  defp describe(%{type: :finished} = e, names),
    do: "#{name(names, e.seat)} hết bài (thứ #{e.place})"

  defp describe(%{type: :game_over}, _names), do: "Kết thúc ván"

  defp describe(%{type: :instant_win} = e, names),
    do:
      Enum.map_join(e.winners, ", ", fn {s, type} ->
        "#{name(names, s)} tới trắng (#{Text.instant(type)})"
      end)

  defp describe(%{type: :coins} = e, names),
    do:
      "Coin: " <>
        Enum.map_join(e.transfers, ", ", fn t ->
          "#{name(names, t["from"])} → #{name(names, t["to"])} #{Text.coins(t["amount"])}"
        end)

  defp describe(_e, _names), do: ""

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :frame, Enum.at(assigns.frames, assigns.step))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      announcement={@announcement}
      social={@social}
      wide
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h1 class="text-xl font-bold">Xem lại ván</h1>
        <.link navigate={~p"/lich-su"} class="link text-sm">← Lịch sử</.link>
      </div>

      <div id="replay-controls" class="flex flex-wrap items-center gap-2">
        <button id="replay-first" phx-click="go" phx-value-to="first" class="btn btn-sm">⏮</button>
        <button id="replay-prev" phx-click="go" phx-value-to="prev" class="btn btn-sm">◀</button>
        <button id="replay-autoplay" phx-click="autoplay" class="btn btn-sm btn-primary">
          {if @playing, do: "⏸ Dừng", else: "▶ Tự chạy"}
        </button>
        <button id="replay-next" phx-click="go" phx-value-to="next" class="btn btn-sm">▶</button>
        <button id="replay-last" phx-click="go" phx-value-to="last" class="btn btn-sm">⏭</button>
        <span id="replay-step" class="text-sm tabular-nums">
          Bước {@step}/{length(@frames) - 1}
        </span>
      </div>

      <p id="replay-event" class="alert alert-info">{describe(@frame.event, @names)}</p>

      <div
        id="replay-centre"
        class="min-h-24 rounded-box bg-success/15 p-3 flex flex-col items-center justify-center gap-1"
      >
        <%= if @frame.centre do %>
          <div class="flex flex-wrap justify-center gap-1">
            <.card :for={c <- @frame.centre.cards} card={c} class="w-10 sm:w-12" />
          </div>
          <p class="text-sm">
            {Text.combo_type(@frame.centre.type)} · {name(@names, @frame.centre.seat)}
            <span :if={@frame.centre.chop} class="badge badge-error badge-sm">chặt</span>
          </p>
        <% else %>
          <p class="text-base-content/60">Bàn trống</p>
        <% end %>
      </div>

      <ul id="replay-hands" class="space-y-2">
        <li
          :for={{seat, hand} <- Enum.sort(@frame.hands)}
          id={"replay-seat-#{seat}"}
          class={[
            "card bg-base-200 p-2",
            @frame.event[:seat] == seat && "ring-2 ring-primary"
          ]}
        >
          <p class="text-sm font-semibold">
            {name(@names, seat)}
            <span class="text-xs text-base-content/60">({length(hand)} lá)</span>
            <span :if={seat in @frame.passed} class="badge badge-sm">bỏ lượt</span>
            <span :if={seat in @frame.finished} class="badge badge-success badge-sm">
              hết bài (thứ {Enum.find_index(@frame.finished, &(&1 == seat)) + 1})
            </span>
            <span :if={seat in @frame.removed} class="badge badge-ghost badge-sm">bị loại</span>
          </p>
          <div class="flex flex-wrap gap-0.5 mt-1">
            <.card :for={c <- hand} card={c} class="w-8 sm:w-10" />
          </div>
        </li>
      </ul>

      <details id="replay-log" class="card bg-base-200 p-3">
        <summary class="cursor-pointer text-sm font-semibold">Tất cả các bước</summary>
        <ol class="text-sm space-y-0.5 mt-2">
          <li :for={{f, i} <- Enum.with_index(@frames)}>
            <button
              phx-click="go"
              phx-value-to={i}
              class={["link link-hover text-left", i == @step && "font-bold"]}
            >
              {i}. {describe(f.event, @names)}
            </button>
          </li>
        </ol>
      </details>
    </Layouts.app>
    """
  end
end
