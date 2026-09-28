defmodule TienLen.LoginThrottle do
  @moduledoc """
  Login rate limiting (AD9, F8): after #{5} failed logins for the same username **or** the same
  IP within 15 minutes, further logins from them are refused until the oldest of those failures
  is 15 minutes old. Counters live in memory (ETS) and reset on restart.

  `now` (milliseconds) can be passed explicitly so tests do not sleep.
  """

  use GenServer

  @table __MODULE__
  @max_failures 5
  @window_ms 15 * 60 * 1000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    {:ok, nil}
  end

  @doc "`:ok` or `{:error, :throttled}` for this username / IP."
  def check(username, ip, now \\ now()) do
    if Enum.any?(keys(username, ip), &(recent(&1, now) >= @max_failures)),
      do: {:error, :throttled},
      else: :ok
  end

  @doc "Records a failed login."
  def failure(username, ip, now \\ now()) do
    for key <- keys(username, ip) do
      times = [now | recent_times(key, now)]
      :ets.insert(@table, {key, times})
    end

    :ok
  end

  @doc "Clears the username's counter after a successful login (the IP counter stays)."
  def success(username), do: :ets.delete(@table, {:user, normalize(username)})

  @doc "Clears everything (tests)."
  def reset, do: :ets.delete_all_objects(@table)

  # ip = nil means "do not count by IP" (the web layer passes nil when IP limiting is off)
  defp keys(username, nil), do: [{:user, normalize(username)}]
  defp keys(username, ip), do: [{:user, normalize(username)}, {:ip, ip}]

  defp normalize(username) when is_binary(username),
    do: username |> String.trim() |> String.downcase()

  defp normalize(other), do: inspect(other)

  defp recent(key, now), do: length(recent_times(key, now))

  defp recent_times(key, now) do
    case :ets.lookup(@table, key) do
      [{^key, times}] -> Enum.filter(times, &(now - &1 < @window_ms))
      [] -> []
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end
