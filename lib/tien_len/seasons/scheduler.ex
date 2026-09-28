defmodule TienLen.Seasons.Scheduler do
  @moduledoc "Pays finished seasons (S2): shortly after start, then every hour. Off in tests."
  use GenServer
  require Logger

  @every :timer.hours(1)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    Process.send_after(self(), :tick, :timer.seconds(10))
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    try do
      TienLen.Seasons.payout_due()
    rescue
      error -> Logger.error("season payout failed: #{Exception.message(error)}")
    end

    Process.send_after(self(), :tick, @every)
    {:noreply, state}
  end
end
