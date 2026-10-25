defmodule VerdictUI.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      VerdictUIWeb.Telemetry,
      VerdictUI.Repo,
      {DNSCluster, query: Application.get_env(:verdict_ui, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: VerdictUI.PubSub},
      # Start a worker by calling: VerdictUI.Worker.start_link(arg)
      # {VerdictUI.Worker, arg},
      # Start to serve requests, typically the last entry
      VerdictUIWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: VerdictUI.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    VerdictUIWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
