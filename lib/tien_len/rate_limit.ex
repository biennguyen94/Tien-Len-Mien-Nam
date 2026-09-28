defmodule TienLen.RateLimit do
  @moduledoc """
  Sliding-window rate limits in ETS (G2 chat, G8 invites). Keys are any term, e.g.
  `{:chat, user_id}`. In memory: counters reset on restart.
  """

  use GenServer

  @table __MODULE__
  @sweep_every :timer.minutes(5)
  @keep :timer.hours(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Records one hit for `key` unless `limit` hits already happened within `window_ms`:
  `:ok` or `{:error, :rate_limited}` (the refused hit is not recorded).
  """
  def hit(key, limit, window_ms, now \\ System.monotonic_time(:millisecond)) do
    recent =
      case :ets.lookup(@table, key) do
        [{^key, times}] -> Enum.filter(times, &(&1 > now - window_ms))
        [] -> []
      end

    if length(recent) >= limit do
      {:error, :rate_limited}
    else
      :ets.insert(@table, {key, [now | recent]})
      :ok
    end
  end

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    Process.send_after(self(), :sweep, @sweep_every)
    {:ok, nil}
  end

  @impl true
  def handle_info(:sweep, state) do
    cutoff = System.monotonic_time(:millisecond) - @keep

    for {key, [latest | _]} <- :ets.tab2list(@table),
        latest < cutoff,
        do: :ets.delete(@table, key)

    Process.send_after(self(), :sweep, @sweep_every)
    {:noreply, state}
  end
end
