defmodule Schedulix.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SchedulixWeb.Telemetry,
      Schedulix.Repo,
      {DNSCluster, query: Application.get_env(:schedulix, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Schedulix.PubSub},
      # Start a worker by calling: Schedulix.Worker.start_link(arg)
      # {Schedulix.Worker, arg},
      # Start to serve requests, typically the last entry
      SchedulixWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Schedulix.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SchedulixWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
