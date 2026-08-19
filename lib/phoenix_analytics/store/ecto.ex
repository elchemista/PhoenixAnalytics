defmodule PhoenixAnalytics.Store.Ecto do
  @moduledoc """
  Store adapter backed by the host application's Ecto repository.

  This is the default adapter and the one selected by the legacy
  `config :phoenix_analytics, repo: MyApp.Repo` setting. It supports
  PostgreSQL, SQLite3 and MySQL: the SQL dialect differences live in
  `PhoenixAnalytics.Queries.Analytics`, while this module executes those queries
  and normalizes their results into the shapes described by
  `PhoenixAnalytics.Store`.

  ## Options

    * `:repo` - the `Ecto.Repo` module holding the `requests` table. Required.
  """

  @behaviour PhoenixAnalytics.Store

  import Ecto.Query

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Queries.Analytics
  alias PhoenixAnalytics.Store
  alias PhoenixAnalytics.Store.Bucket
  alias PhoenixAnalytics.Store.Query

  @import_chunk_size 500
  @stream_max_rows 1_000

  @impl PhoenixAnalytics.Store
  def insert_all(logs, opts) do
    rows = Enum.map(logs, &to_row/1)
    repo!(opts).insert_all(RequestLog, rows, returning: false, on_conflict: :nothing)

    :ok
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def stat(name, %Query{} = query, opts) do
    {:ok, name |> stat_query(query) |> repo!(opts).one() |> to_number()}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def stat_series(name, %Query{} = query, opts) do
    {series_query, field} = stat_series_query(name, query)

    rows =
      series_query
      |> apply_limit(query.limit)
      |> repo!(opts).all()
      |> Enum.map(
        &%{date: Bucket.normalize(&1.date, :day), value: to_number(Map.fetch!(&1, field))}
      )

    {:ok, rows}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def visits_per_period(%Query{} = query, opts) do
    rows =
      query.from
      |> Analytics.visits_per_period(query.to, to_string(query.interval))
      |> apply_limit(query.limit)
      |> repo!(opts).all()
      |> Enum.map(fn row ->
        %{
          date: Bucket.normalize(row.date, query.interval),
          visits: to_number(row.visits),
          unique_visitors: to_number(row.unique_visitors)
        }
      end)

    {:ok, rows}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def requests_per_period(%Query{} = query, opts) do
    rows =
      query.from
      |> Analytics.total_requests_per_period(query.to, to_string(query.interval))
      |> apply_limit(query.limit)
      |> repo!(opts).all()
      |> Enum.map(&%{date: Bucket.normalize(&1.date, query.interval), hits: to_number(&1.hits)})

    {:ok, rows}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def statuses_per_period(%Query{} = query, opts) do
    rows =
      query.from
      |> Analytics.statuses_per_period(query.to, to_string(query.interval))
      |> apply_limit(query.limit)
      |> repo!(opts).all()
      |> Enum.map(fn row ->
        %{
          date: Bucket.normalize(row.date, query.interval),
          ok_200s: to_number(row.ok_200s),
          redirects_300s: to_number(row.redirects_300s),
          errors_400s: to_number(row.errors_400s),
          fails_500s: to_number(row.fails_500s)
        }
      end)

    {:ok, rows}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def devices_usage(%Query{} = query, opts) do
    rows =
      query.from
      |> Analytics.devices_usage(query.to)
      |> repo!(opts).all()
      |> Enum.map(&%{device: &1.device, count: to_number(&1.count)})

    {:ok, rows}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def popular(kind, %Query{} = query, opts) do
    rows =
      kind
      |> popular_query(query)
      |> repo!(opts).all()
      |> Enum.map(&%{source: &1.source, visits: to_number(&1.visits)})

    {:ok, rows}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def slowest(kind, %Query{} = query, opts) do
    rows =
      kind
      |> slowest_query(query)
      |> repo!(opts).all()
      |> Enum.map(&%{path: &1.path, duration: to_number(&1.duration)})

    {:ok, rows}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def export(%Query{from: from, to: to}, fun, opts) do
    repo = repo!(opts)

    logs =
      from(request in RequestLog,
        where: request.inserted_at >= ^from and request.inserted_at <= ^to,
        order_by: request.inserted_at
      )

    # The stream is only valid inside the transaction, hence the callback shape.
    repo.transaction(fn -> logs |> repo.stream(max_rows: @stream_max_rows) |> fun.() end,
      timeout: :infinity
    )
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def import_all(logs, opts) do
    repo = repo!(opts)

    count =
      logs
      |> Stream.chunk_every(@import_chunk_size)
      |> Enum.reduce(0, fn chunk, acc ->
        {inserted, _returned} =
          repo.insert_all(RequestLog, Enum.map(chunk, &to_row/1),
            returning: false,
            on_conflict: :nothing
          )

        acc + inserted
      end)

    {:ok, count}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def prune(%NaiveDateTime{} = point_in_time, opts) do
    {deleted, _returned} =
      repo!(opts).delete_all(
        from(request in RequestLog, where: request.inserted_at < ^point_in_time)
      )

    {:ok, deleted}
  rescue
    error -> {:error, error}
  end

  @impl PhoenixAnalytics.Store
  def info(opts) do
    %{count: repo!(opts).aggregate(RequestLog, :count)}
  end

  @doc """
  Returns the SQL dialect of the configured repository.

  Query modules use it to pick the right date functions.

  ## Examples

      iex> PhoenixAnalytics.Store.Ecto.database_type()
      :sqlite
  """
  @spec database_type() :: :postgres | :sqlite | :mysql
  def database_type, do: database_type(PhoenixAnalytics.Config.get_repo())

  @doc "Returns the SQL dialect of the given repository."
  @spec database_type(module()) :: :postgres | :sqlite | :mysql
  def database_type(repo) do
    case repo.__adapter__() do
      Ecto.Adapters.SQLite3 -> :sqlite
      Ecto.Adapters.MyXQL -> :mysql
      _adapter -> :postgres
    end
  end

  @spec stat_query(Store.stat_name(), Query.t()) :: Ecto.Query.t()
  defp stat_query(:unique_visitors, query), do: Analytics.unique_visitors(query.from, query.to)
  defp stat_query(:total_pageviews, query), do: Analytics.total_pageviews(query.from, query.to)
  defp stat_query(:total_requests, query), do: Analytics.total_requests(query.from, query.to)
  defp stat_query(:bounce_rate, query), do: Analytics.bounce_rate(query.from, query.to)

  defp stat_query(:views_per_visit, query) do
    Analytics.average_views_per_visit(query.from, query.to)
  end

  defp stat_query(:visit_duration, query) do
    Analytics.average_visit_duration(query.from, query.to)
  end

  @spec stat_series_query(Store.stat_name(), Query.t()) :: {Ecto.Query.t(), atom()}
  defp stat_series_query(:unique_visitors, query) do
    {Analytics.unique_visitors_per_period_limited(query.from, query.to), :unique_visitors}
  end

  defp stat_series_query(:total_pageviews, query) do
    {Analytics.total_pageviews_per_period_limited(query.from, query.to), :pageviews}
  end

  defp stat_series_query(:total_requests, query) do
    {Analytics.total_requests_per_period_limited(query.from, query.to), :hits}
  end

  defp stat_series_query(:views_per_visit, query) do
    {Analytics.views_per_visit_per_period_limited(query.from, query.to), :hits}
  end

  defp stat_series_query(:visit_duration, query) do
    {Analytics.visit_duration_per_period_limited(query.from, query.to), :hits}
  end

  defp stat_series_query(:bounce_rate, query) do
    {Analytics.bounce_rate_per_period_limited(query.from, query.to), :bounce_rate}
  end

  @spec popular_query(Store.popular_kind(), Query.t()) :: Ecto.Query.t()
  defp popular_query(:pages, query), do: Analytics.popular_pages(query.from, query.to)
  defp popular_query(:referers, query), do: Analytics.popular_referer(query.from, query.to)
  defp popular_query(:not_founds, query), do: Analytics.popular_not_found(query.from, query.to)

  defp popular_query(:user_agents, query) do
    Analytics.popular_user_agents(query.from, query.to)
  end

  defp popular_query(:device_types, query) do
    Analytics.popular_device_types(query.from, query.to)
  end

  @spec slowest_query(Store.slowest_kind(), Query.t()) :: Ecto.Query.t()
  defp slowest_query(:pages, query), do: Analytics.slowest_pages(query.from, query.to)
  defp slowest_query(:resources, query), do: Analytics.slowest_resources(query.from, query.to)

  @spec apply_limit(Ecto.Queryable.t(), pos_integer() | nil) :: Ecto.Queryable.t()
  defp apply_limit(query, nil), do: query
  defp apply_limit(query, limit), do: limit(query, ^limit)

  @spec repo!(keyword()) :: module()
  defp repo!(opts), do: Keyword.fetch!(opts, :repo)

  # `inserted_at` is preserved so snapshots can be imported back with their
  # original timestamp; only missing values fall back to the current time.
  @spec to_row(RequestLog.t()) :: map()
  defp to_row(%RequestLog{} = log) do
    log
    |> Map.from_struct()
    |> Map.drop([:__meta__])
    |> Map.put(:inserted_at, truncate(log.inserted_at))
  end

  @spec truncate(NaiveDateTime.t() | nil) :: NaiveDateTime.t()
  defp truncate(nil), do: NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
  defp truncate(%NaiveDateTime{} = date_time), do: NaiveDateTime.truncate(date_time, :second)

  @spec to_number(term()) :: number()
  defp to_number(nil), do: 0
  defp to_number(%Decimal{} = decimal), do: Decimal.to_float(decimal)
  defp to_number(%{bounce_rate: value}), do: to_number(value)
  defp to_number(value) when is_number(value), do: value
  defp to_number(_value), do: 0
end
