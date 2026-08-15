defmodule Isomer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        {DNSCluster, query: Application.get_env(:isomer, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Isomer.PubSub}
      ] ++ endpoint_children()

    opts = [strategy: :one_for_one, name: Isomer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Mix DB tasks (`Isomer.Mix.Boot.start_for_db!/0`) set `:start_endpoint` false
  # so CI/sync does not boot Bandit + live_reload/inotify. Releases and
  # `mix phx.server` leave the default true.
  defp endpoint_children do
    if Application.get_env(:isomer, :start_endpoint, true) do
      [IsomerWeb.Endpoint]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    if Process.whereis(IsomerWeb.Endpoint) do
      IsomerWeb.Endpoint.config_change(changed, removed)
    end

    :ok
  end
end
