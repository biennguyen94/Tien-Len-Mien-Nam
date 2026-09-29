defmodule TienLenWeb.ChatComponents do
  @moduledoc """
  Chat box shared by the table (G4), the lobby (G5) and the admin watch view (G12). Lines of
  the commentator (`system: true`, BL1) are shown in italics.
  """
  use TienLenWeb, :html

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :messages, :list, required: true
  attr :me, :integer, default: nil, doc: "the viewer's user id (own lines are highlighted)"
  attr :send_event, :string, default: nil, doc: "nil = read only"
  attr :phrases, :boolean, default: false
  attr :delete_event, :string, default: nil, doc: "admins: event to delete a message"
  attr :key, :integer, default: 0, doc: "bump after a send to clear the input"

  def chat_box(assigns) do
    ~H"""
    <section id={@id} class="card bg-base-200 p-3 space-y-2">
      <h2 class="font-semibold text-sm">{@title}</h2>
      <ol
        id={"#{@id}-messages"}
        phx-hook="ChatScroll"
        class="max-h-56 overflow-y-auto space-y-1 text-sm break-words"
      >
        <li :if={@messages == []} class="text-base-content/50">Chưa có tin nhắn.</li>
        <li :for={m <- @messages} id={"#{@id}-msg-#{m.id}"} class="flex gap-1 items-start">
          <span class="text-xs text-base-content/50 tabular-nums shrink-0">{hhmm(m.at)}</span>
          <span class={[
            "font-semibold shrink-0",
            m.user_id && m.user_id == @me && "text-primary",
            Map.get(m, :system) && "text-warning",
            Map.get(m, :bot) && "text-info"
          ]}>
            {m.name}:
          </span>
          <span class={["flex-1", Map.get(m, :system) && "italic"]}>{m.text}</span>
          <button
            :if={@delete_event}
            phx-click={@delete_event}
            phx-value-id={m.id}
            class="btn btn-ghost btn-xs text-error"
            title="Xóa tin nhắn"
            data-confirm="Xóa tin nhắn này?"
          >✕</button>
        </li>
      </ol>
      <div :if={@send_event && @phrases} class="flex flex-wrap gap-1">
        <button
          :for={p <- TienLen.Chat.phrases()}
          type="button"
          phx-click={@send_event}
          phx-value-text={p}
          class="btn btn-xs btn-outline"
        >{p}</button>
      </div>
      <form
        :if={@send_event}
        id={"#{@id}-form"}
        phx-submit={@send_event}
        class="flex gap-2"
      >
        <input
          id={"#{@id}-input-#{@key}"}
          name="text"
          maxlength="200"
          autocomplete="off"
          placeholder="Nhắn tin…"
          class="input input-bordered input-sm flex-1 min-w-0"
        />
        <button class="btn btn-sm btn-primary">Gửi</button>
      </form>
    </section>
    """
  end

  @doc "HH:MM in Vietnam time (UTC+7)."
  def hhmm(%DateTime{} = at),
    do: at |> DateTime.add(7 * 3600, :second) |> Calendar.strftime("%H:%M")
end
