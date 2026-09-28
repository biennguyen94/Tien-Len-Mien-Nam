defmodule TienLen.Chat.Lobby do
  @moduledoc """
  The lobby chat (G5): the last 100 messages, in memory (lost on restart, CH2). Broadcasts
  `{:lobby_chat, msg}` and `{:lobby_chat_deleted, id}` on `topic/0`.
  """

  use GenServer

  @keep 100

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def topic, do: "lobby_chat"

  @doc "Adds a prepared message (`TienLen.Chat.prepare/2`)."
  def post(msg), do: GenServer.call(__MODULE__, {:post, msg})

  @doc "Messages, oldest first."
  def history, do: GenServer.call(__MODULE__, :history)

  @doc "Removes a message (admin, G12). `{:ok, msg}` or `{:error, :not_found}`."
  def delete(id), do: GenServer.call(__MODULE__, {:delete, id})

  @impl true
  def init(nil), do: {:ok, []}

  @impl true
  def handle_call({:post, msg}, _from, msgs) do
    broadcast({:lobby_chat, msg})
    {:reply, :ok, Enum.take([msg | msgs], @keep)}
  end

  def handle_call(:history, _from, msgs), do: {:reply, Enum.reverse(msgs), msgs}

  def handle_call({:delete, id}, _from, msgs) do
    case Enum.find(msgs, &(&1.id == id)) do
      nil ->
        {:reply, {:error, :not_found}, msgs}

      msg ->
        broadcast({:lobby_chat_deleted, id})
        {:reply, {:ok, msg}, Enum.reject(msgs, &(&1.id == id))}
    end
  end

  defp broadcast(event), do: Phoenix.PubSub.broadcast(TienLen.PubSub, topic(), event)
end
