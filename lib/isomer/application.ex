defmodule Isomer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {DNSCluster, query: Application.get_env(:isomer, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Isomer.PubSub},
      IsomerWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Isomer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    IsomerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
