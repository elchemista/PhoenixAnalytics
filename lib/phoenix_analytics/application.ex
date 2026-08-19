defmodule PhoenixAnalytics.Application do
  @moduledoc false

  use Application

  alias PhoenixAnalytics.Config
  alias PhoenixAnalytics.Services.Batcher
  alias PhoenixAnalytics.Services.Cache
  alias PhoenixAnalytics.Services.PubSub
  alias PhoenixAnalytics.Snapshot.Scheduler

  @task_supervisor PhoenixAnalytics.TaskSupervisor

  @doc false
  @impl Application
  def start(_type, _args) do
    children =
      [
        {Phoenix.PubSub, name: PubSub.name()},
        {Cachex, name: Cache.name()},
        {Task.Supervisor, name: @task_supervisor}
      ] ++
        store_children(Config.fetch_store()) ++
        [Batcher] ++
        snapshot_children(Config.snapshot())

    Supervisor.start_link(children, strategy: :one_for_one, name: __MODULE__)
  end

  @doc "Name of the task supervisor used for background snapshot work."
  @spec task_supervisor() :: atom()
  def task_supervisor, do: @task_supervisor

  # Stateful stores must be running before the batcher starts writing to them.
  # An unconfigured store is not an error here: the host application still
  # boots, and the missing configuration is reported on first use.
  @spec store_children({:ok, {module(), keyword()}} | :error) :: [{module(), keyword()}]
  defp store_children(:error), do: []

  defp store_children({:ok, {store, opts}}) do
    if Code.ensure_loaded?(store) and function_exported?(store, :child_spec, 1) do
      [{store, opts}]
    else
      []
    end
  end

  @spec snapshot_children(keyword() | nil) :: [{module(), keyword()}]
  defp snapshot_children(nil), do: []
  defp snapshot_children(opts), do: [{Scheduler, opts}]
end
