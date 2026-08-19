defmodule PhoenixAnalytics.Store.ETS do
  @moduledoc """
  In-memory store backed by an ETS ordered set.

  Reads and writes never leave the node, which makes it the fastest option and
  the only one that needs no database at all. In exchange the data is volatile
  and node local:

    * a restart loses whatever has not been snapshotted yet, so pair it with
      `PhoenixAnalytics.Snapshot` for durability and restore;
    * with several nodes each one only sees its own traffic, because
      `PhoenixAnalytics.Services.PubSub` broadcasts locally.

  Memory grows with traffic, roughly 0.5-1 KB per request. `:retention_days`
  and `:max_entries` bound it, and `info/1` reports the current usage.

  Logs are keyed by timestamp and request id, where the Ecto store keys them by
  request id alone. Re-importing a snapshot is therefore idempotent, since the
  timestamp is preserved, but the same request id stored under two different
  timestamps would be kept twice.

  ## Options

    * `:table` - name of the ETS table. Defaults to `:phoenix_analytics_requests`.
    * `:retention_days` - how long logs are kept. Defaults to `30`.
    * `:max_entries` - hard cap on stored logs, oldest first. Defaults to `nil`.
    * `:prune_interval_ms` - how often retention runs. Defaults to one hour.
    * `:compressed` - trade CPU for memory in the ETS table. Defaults to `false`.

  ## Example

      config :phoenix_analytics,
        store: {PhoenixAnalytics.Store.ETS, retention_days: 30, max_entries: 2_000_000},
        cache_ttl: 0
  """

  @behaviour PhoenixAnalytics.Store

  use GenServer

  alias PhoenixAnalytics.Config
  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Store.ETS.Aggregate
  alias PhoenixAnalytics.Store.ETS.Table
  alias PhoenixAnalytics.Store.Query

  @default_table :phoenix_analytics_requests

  @defaults [
    table: @default_table,
    retention_days: 30,
    max_entries: nil,
    prune_interval_ms: :timer.hours(1),
    compressed: false
  ]

  @type state :: %{
          table: atom(),
          retention_days: pos_integer(),
          max_entries: pos_integer() | nil,
          prune_interval_ms: pos_integer(),
          compressed: boolean()
        }

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    options = Keyword.merge(@defaults, opts)

    GenServer.start_link(__MODULE__, options, name: Keyword.get(options, :name, __MODULE__))
  end

  @doc false
  @impl GenServer
  def init(opts) do
    state = Map.new(opts)
    Table.create(state.table, compressed: state.compressed)
    schedule_prune(state)

    {:ok, state}
  end

  @doc false
  @impl GenServer
  def handle_info(:prune, state) do
    cutoff = NaiveDateTime.add(NaiveDateTime.utc_now(), -state.retention_days, :day)
    Table.delete_before(state.table, cutoff)
    trim(state)
    schedule_prune(state)

    {:noreply, state}
  end

  # Writes and reads run in the caller process: the table is public, so the
  # owner process is never a bottleneck.

  @impl PhoenixAnalytics.Store
  def insert_all(logs, opts), do: Table.insert(table(opts), Enum.map(logs, &with_timestamp/1))

  @impl PhoenixAnalytics.Store
  def stat(name, %Query{} = query, opts) do
    {:ok, query |> logs(opts) |> Aggregate.stat(name)}
  end

  @impl PhoenixAnalytics.Store
  def stat_series(name, %Query{} = query, opts) do
    {:ok, query |> logs(opts) |> Aggregate.stat_series(name, query)}
  end

  @impl PhoenixAnalytics.Store
  def visits_per_period(%Query{} = query, opts) do
    {:ok, query |> logs(opts) |> Aggregate.visits_per_period(query)}
  end

  @impl PhoenixAnalytics.Store
  def requests_per_period(%Query{} = query, opts) do
    {:ok, query |> logs(opts) |> Aggregate.requests_per_period(query)}
  end

  @impl PhoenixAnalytics.Store
  def statuses_per_period(%Query{} = query, opts) do
    {:ok, query |> logs(opts) |> Aggregate.statuses_per_period(query)}
  end

  @impl PhoenixAnalytics.Store
  def devices_usage(%Query{} = query, opts) do
    {:ok, query |> logs(opts) |> Aggregate.devices_usage(query)}
  end

  @impl PhoenixAnalytics.Store
  def popular(kind, %Query{} = query, opts) do
    {:ok, query |> logs(opts) |> Aggregate.popular(kind, Config.get_app_domain())}
  end

  @impl PhoenixAnalytics.Store
  def slowest(kind, %Query{} = query, opts) do
    {:ok, query |> logs(opts) |> Aggregate.slowest(kind)}
  end

  @impl PhoenixAnalytics.Store
  def export(%Query{from: from, to: to}, fun, opts) do
    {:ok, fun.(Table.stream(table(opts), from, to))}
  end

  @impl PhoenixAnalytics.Store
  def import_all(logs, opts) do
    name = table(opts)

    count =
      logs
      |> Stream.chunk_every(1_000)
      |> Enum.reduce(0, fn chunk, acc ->
        Table.insert(name, Enum.map(chunk, &with_timestamp/1))
        acc + length(chunk)
      end)

    {:ok, count}
  end

  @impl PhoenixAnalytics.Store
  def prune(%NaiveDateTime{} = point_in_time, opts) do
    {:ok, Table.delete_before(table(opts), point_in_time)}
  end

  @impl PhoenixAnalytics.Store
  def info(opts), do: Table.info(table(opts))

  @spec logs(Query.t(), keyword()) :: [RequestLog.t()]
  defp logs(%Query{from: from, to: to}, opts), do: Table.range(table(opts), from, to)

  @spec table(keyword()) :: atom()
  defp table(opts), do: Keyword.get(opts, :table, @default_table)

  # Logs restored from a snapshot keep their timestamp; only fresh ones without
  # it fall back to the current time, since the timestamp is part of the key.
  @spec with_timestamp(RequestLog.t()) :: RequestLog.t()
  defp with_timestamp(%RequestLog{inserted_at: nil} = log) do
    %{log | inserted_at: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)}
  end

  defp with_timestamp(%RequestLog{} = log), do: log

  @spec trim(state()) :: non_neg_integer()
  defp trim(%{max_entries: nil}), do: 0
  defp trim(%{max_entries: max_entries} = state), do: Table.trim(state.table, max_entries)

  @spec schedule_prune(state()) :: reference()
  defp schedule_prune(state), do: Process.send_after(self(), :prune, state.prune_interval_ms)
end
