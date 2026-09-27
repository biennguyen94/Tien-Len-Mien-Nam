defmodule TienLen.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TienLenWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:tien_len, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: TienLen.PubSub},
      # One TienLen.RoomServer per room, looked up by room id.
      {Registry, keys: :unique, name: TienLen.RoomRegistry},
      {DynamicSupervisor, name: TienLen.RoomSupervisor, strategy: :one_for_one},
      # Start to serve requests, typically the last entry
      TienLenWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: TienLen.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    TienLenWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
