defmodule FeedPug.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.get_env(:libcluster, :topologies, [])

    children =
      [
        FeedPugWeb.Telemetry,
        FeedPug.Repo,
        {DNSCluster, query: Application.get_env(:feed_pug, :dns_cluster_query) || :ignore}
      ] ++
        cluster_children(topologies) ++
        [
          {Phoenix.PubSub, name: FeedPug.PubSub},
          {Oban, Application.fetch_env!(:feed_pug, Oban)},
          # Start to serve requests, typically the last entry
          FeedPugWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FeedPug.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # libcluster only joins the supervision tree when a topology is configured
  # (prod, via runtime.exs). In dev/test the list is empty, so no Cluster
  # supervisor is started — distributed Erlang stays off.
  defp cluster_children([]), do: []

  defp cluster_children(topologies) do
    [{Cluster.Supervisor, [topologies, [name: FeedPug.ClusterSupervisor]]}]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FeedPugWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
