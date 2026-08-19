defmodule PhoenixAnalytics.Store do
  @moduledoc """
  Behaviour implemented by analytics storage adapters, and facade towards the
  configured one.

  A store owns both the write path (`c:insert_all/2`) and the read path used by
  the dashboard. Callbacks describe *analytics operations*, not queries, so an
  adapter is free to answer them with SQL, with in-memory folds, or with a
  remote API.

  ## Configuration

      config :phoenix_analytics, store: {PhoenixAnalytics.Store.Ecto, repo: MyApp.Repo}
      config :phoenix_analytics, store: {PhoenixAnalytics.Store.ETS, retention_days: 30}

  The legacy `config :phoenix_analytics, repo: MyApp.Repo` keeps working and
  selects `PhoenixAnalytics.Store.Ecto`.

  ## Optional callbacks

  `c:child_spec/1` is used to supervise stateful adapters, while `c:export/3`,
  `c:import_all/2`, `c:prune/2` and `c:info/1` back snapshots and retention.
  Use `supports?/1` before calling them on an unknown adapter.
  """

  alias PhoenixAnalytics.Config
  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Store.Query

  @type opts :: keyword()

  @type stat_name ::
          :unique_visitors
          | :total_pageviews
          | :total_requests
          | :views_per_visit
          | :visit_duration
          | :bounce_rate

  @type popular_kind :: :pages | :referers | :not_founds | :user_agents | :device_types
  @type slowest_kind :: :pages | :resources

  @type point :: %{date: String.t(), value: number()}
  @type visits_row :: %{date: String.t(), visits: integer(), unique_visitors: integer()}
  @type requests_row :: %{date: String.t(), hits: integer()}
  @type statuses_row :: %{
          date: String.t(),
          ok_200s: integer(),
          redirects_300s: integer(),
          errors_400s: integer(),
          fails_500s: integer()
        }
  @type device_row :: %{device: String.t() | nil, count: integer()}
  @type popular_row :: %{source: String.t() | nil, visits: integer()}
  @type slowest_row :: %{path: String.t(), duration: number()}

  @doc "Persists a batch of request logs."
  @callback insert_all([RequestLog.t()], opts()) :: :ok | {:error, term()}

  @doc "Returns a single aggregated number for the stat cards."
  @callback stat(stat_name(), Query.t(), opts()) :: {:ok, number()} | {:error, term()}

  @doc "Returns the sparkline series backing a stat card."
  @callback stat_series(stat_name(), Query.t(), opts()) :: {:ok, [point()]} | {:error, term()}

  @doc "Returns visits and unique visitors bucketed by the query interval."
  @callback visits_per_period(Query.t(), opts()) :: {:ok, [visits_row()]} | {:error, term()}

  @doc "Returns request counts bucketed by the query interval."
  @callback requests_per_period(Query.t(), opts()) :: {:ok, [requests_row()]} | {:error, term()}

  @doc "Returns status code families bucketed by the query interval."
  @callback statuses_per_period(Query.t(), opts()) :: {:ok, [statuses_row()]} | {:error, term()}

  @doc "Returns request counts grouped by device type."
  @callback devices_usage(Query.t(), opts()) :: {:ok, [device_row()]} | {:error, term()}

  @doc "Returns the most frequent sources for the given dimension."
  @callback popular(popular_kind(), Query.t(), opts()) ::
              {:ok, [popular_row()]} | {:error, term()}

  @doc "Returns the slowest paths by average duration."
  @callback slowest(slowest_kind(), Query.t(), opts()) ::
              {:ok, [slowest_row()]} | {:error, term()}

  @doc "Child specification for adapters that need supervision."
  @callback child_spec(opts()) :: Supervisor.child_spec()

  @doc """
  Streams the raw logs of a period into `fun` and returns its result.

  The callback shape lets adapters keep the stream alive only while it is
  consumed, which is required for `Ecto.Repo.stream` inside a transaction.
  """
  @callback export(Query.t(), (Enumerable.t() -> result), opts()) ::
              {:ok, result} | {:error, term()}
            when result: term()

  @doc """
  Inserts previously exported logs back into the store, idempotently.

  Returns how many logs were imported, counting those the store already held,
  so the number is the same on every adapter and on every replay.
  """
  @callback import_all(Enumerable.t(), opts()) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc "Deletes every log older than the given point in time."
  @callback prune(NaiveDateTime.t(), opts()) :: {:ok, non_neg_integer()} | {:error, term()}

  @doc "Returns adapter statistics such as record count and memory usage."
  @callback info(opts()) :: map()

  @optional_callbacks child_spec: 1, export: 3, import_all: 2, prune: 2, info: 1

  @optional_arities %{child_spec: 1, export: 3, import_all: 2, prune: 2, info: 1}

  @doc """
  Returns the configured adapter and its options.

  ## Examples

      iex> {module, opts} = PhoenixAnalytics.Store.adapter()
      iex> {module, Keyword.keys(opts)}
      {PhoenixAnalytics.Store.Ecto, [:repo]}
  """
  @spec adapter() :: {module(), opts()}
  def adapter, do: Config.store()

  @doc """
  Returns true when the configured adapter implements an optional callback.

  ## Examples

      iex> PhoenixAnalytics.Store.supports?(:export)
      true
  """
  @spec supports?(:child_spec | :export | :import_all | :prune | :info) :: boolean()
  def supports?(callback) do
    {module, _opts} = adapter()
    arity = Map.fetch!(@optional_arities, callback)

    Code.ensure_loaded?(module) and function_exported?(module, callback, arity)
  end

  @doc "Persists a batch of request logs through the configured adapter."
  @spec insert_all([RequestLog.t()]) :: :ok | {:error, term()}
  def insert_all(logs), do: dispatch(:insert_all, [logs])

  @doc "Returns a single aggregated number for the stat cards."
  @spec stat(stat_name(), Query.t()) :: {:ok, number()} | {:error, term()}
  def stat(name, %Query{} = query), do: dispatch(:stat, [name, query])

  @doc "Returns the sparkline series backing a stat card."
  @spec stat_series(stat_name(), Query.t()) :: {:ok, [point()]} | {:error, term()}
  def stat_series(name, %Query{} = query), do: dispatch(:stat_series, [name, query])

  @doc "Returns visits and unique visitors bucketed by the query interval."
  @spec visits_per_period(Query.t()) :: {:ok, [visits_row()]} | {:error, term()}
  def visits_per_period(%Query{} = query), do: dispatch(:visits_per_period, [query])

  @doc "Returns request counts bucketed by the query interval."
  @spec requests_per_period(Query.t()) :: {:ok, [requests_row()]} | {:error, term()}
  def requests_per_period(%Query{} = query), do: dispatch(:requests_per_period, [query])

  @doc "Returns status code families bucketed by the query interval."
  @spec statuses_per_period(Query.t()) :: {:ok, [statuses_row()]} | {:error, term()}
  def statuses_per_period(%Query{} = query), do: dispatch(:statuses_per_period, [query])

  @doc "Returns request counts grouped by device type."
  @spec devices_usage(Query.t()) :: {:ok, [device_row()]} | {:error, term()}
  def devices_usage(%Query{} = query), do: dispatch(:devices_usage, [query])

  @doc "Returns the most frequent sources for the given dimension."
  @spec popular(popular_kind(), Query.t()) :: {:ok, [popular_row()]} | {:error, term()}
  def popular(kind, %Query{} = query), do: dispatch(:popular, [kind, query])

  @doc "Returns the slowest paths by average duration."
  @spec slowest(slowest_kind(), Query.t()) :: {:ok, [slowest_row()]} | {:error, term()}
  def slowest(kind, %Query{} = query), do: dispatch(:slowest, [kind, query])

  @doc "Streams the raw logs of a period into `fun` and returns its result."
  @spec export(Query.t(), (Enumerable.t() -> result)) :: {:ok, result} | {:error, term()}
        when result: term()
  def export(%Query{} = query, fun) when is_function(fun, 1), do: dispatch(:export, [query, fun])

  @doc "Inserts previously exported logs back into the store."
  @spec import_all(Enumerable.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def import_all(logs), do: dispatch(:import_all, [logs])

  @doc "Deletes every log older than the given point in time."
  @spec prune(NaiveDateTime.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def prune(%NaiveDateTime{} = point_in_time), do: dispatch(:prune, [point_in_time])

  @doc "Returns adapter statistics such as record count and memory usage."
  @spec info() :: map()
  def info, do: dispatch(:info, [])

  @spec dispatch(atom(), list()) :: term()
  defp dispatch(callback, args) do
    {module, opts} = adapter()
    apply(module, callback, args ++ [opts])
  end
end
