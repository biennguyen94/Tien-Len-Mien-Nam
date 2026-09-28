defmodule TienLen.Chat.Private do
  @moduledoc """
  Private chat, short version (CH1, G1, G7): per pair of players the last 20 lines and the
  unread counts, in memory. A conversation is dropped after 1 hour without messages, and
  everything is lost on restart. There is no inbox for offline players (`TienLen.Chat` refuses
  to send to them).

  Each new line is sent as `{:private_msg, msg, to_id}` on the user topic of both players
  (`TienLen.Admin.user_topic/1`), so it reaches every open page of both.
  """

  use GenServer

  @keep 20
  @ttl :timer.hours(1)
  @sweep_every :timer.minutes(1)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Adds a prepared message from `msg.user_id` to `to_id` (named `to_name`)."
  def post(to_id, to_name, msg), do: GenServer.call(__MODULE__, {:post, to_id, to_name, msg})

  @doc "Lines between two players, oldest first."
  def conversation(user_id, peer_id), do: GenServer.call(__MODULE__, {:lines, user_id, peer_id})

  @doc "Conversations of a player: `[%{peer_id, name, unread}]`, most recent first."
  def conversations(user_id), do: GenServer.call(__MODULE__, {:conversations, user_id})

  @doc "The player has read the conversation with `peer_id`."
  def mark_read(user_id, peer_id), do: GenServer.cast(__MODULE__, {:read, user_id, peer_id})

  @doc false
  def sweep(now), do: GenServer.call(__MODULE__, {:sweep, now})

  @impl true
  def init(_opts) do
    Process.send_after(self(), :sweep, @sweep_every)
    # pair => %{lines (newest first), names: %{id => name}, last: ms}; {to, from} => unread
    {:ok, %{convs: %{}, unread: %{}}}
  end

  @impl true
  def handle_call({:post, to_id, to_name, msg}, _from, state) do
    pair = pair(msg.user_id, to_id)

    conv =
      Map.get(state.convs, pair, %{lines: [], names: %{}, last: 0})
      |> Map.update!(:lines, &Enum.take([msg | &1], @keep))
      |> Map.update!(:names, &(&1 |> Map.put(msg.user_id, msg.name) |> Map.put(to_id, to_name)))
      |> Map.put(:last, now())

    state = %{
      state
      | convs: Map.put(state.convs, pair, conv),
        unread: Map.update(state.unread, {to_id, msg.user_id}, 1, &(&1 + 1))
    }

    for id <- [msg.user_id, to_id] do
      Phoenix.PubSub.broadcast(
        TienLen.PubSub,
        TienLen.Admin.user_topic(id),
        {:private_msg, msg, to_id}
      )
    end

    {:reply, :ok, state}
  end

  def handle_call({:lines, a, b}, _from, state) do
    lines = state.convs |> Map.get(pair(a, b), %{lines: []}) |> Map.fetch!(:lines)
    {:reply, Enum.reverse(lines), state}
  end

  def handle_call({:conversations, user_id}, _from, state) do
    list =
      for {{a, b} = _pair, conv} <- state.convs, user_id in [a, b] do
        peer = if a == user_id, do: b, else: a

        %{
          peer_id: peer,
          name: Map.get(conv.names, peer, "?"),
          unread: Map.get(state.unread, {user_id, peer}, 0),
          last: conv.last
        }
      end
      |> Enum.sort_by(& &1.last, :desc)

    {:reply, list, state}
  end

  def handle_call({:sweep, now}, _from, state), do: {:reply, :ok, do_sweep(state, now)}

  @impl true
  def handle_cast({:read, user_id, peer_id}, state),
    do: {:noreply, %{state | unread: Map.delete(state.unread, {user_id, peer_id})}}

  @impl true
  def handle_info(:sweep, state) do
    Process.send_after(self(), :sweep, @sweep_every)
    {:noreply, do_sweep(state, now())}
  end

  defp do_sweep(state, now) do
    {old, kept} = Enum.split_with(state.convs, fn {_pair, conv} -> conv.last < now - @ttl end)

    unread =
      Enum.reduce(old, state.unread, fn {{a, b}, _}, acc ->
        acc |> Map.delete({a, b}) |> Map.delete({b, a})
      end)

    %{state | convs: Map.new(kept), unread: unread}
  end

  defp pair(a, b), do: if(a <= b, do: {a, b}, else: {b, a})
  defp now, do: System.monotonic_time(:millisecond)
end
