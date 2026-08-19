defmodule PhoenixAnalytics.Web.Data do
  @moduledoc """
  Read model of the dashboard.

  LiveComponents are primary adapters: they render, they do not query. This
  module is the single place where a chart request is turned into a cache
  lookup, a store call and the JSON shape expected by the React components.

  Failures never reach the UI: they are reported through telemetry and replaced
  by a neutral default, and they are not cached, so the next render retries.
  """

  alias PhoenixAnalytics.Services.Cache
  alias PhoenixAnalytics.Services.Telemetry
  alias PhoenixAnalytics.Store
  alias PhoenixAnalytics.Store.Query

  @type date_range :: %{from: Query.date_input(), to: Query.date_input()}
  @type chart ::
          :visits
          | :requests
          | :statuses
          | :devices
          | {:popular, Store.popular_kind()}
          | {:slowest, Store.slowest_kind()}

  @series_limit 30

  @doc """
  Returns the single number rendered by a stat card.

  ## Examples

      iex> PhoenixAnalytics.Web.Data.stat(:total_requests, %{from: "2025-01-01", to: "2025-01-31"})
      0
  """
  @spec stat(Store.stat_name(), date_range()) :: number()
  def stat(name, %{from: from, to: to}) do
    cached("stat:#{name}:#{from}:#{to}", 0, fn ->
      Store.stat(name, Query.new(from, to))
    end)
  end

  @doc """
  Returns the sparkline series rendered under a stat card.

  ## Examples

      iex> PhoenixAnalytics.Web.Data.stat_series(:total_requests, %{from: "2025-01-01", to: "2025-01-31"})
      []
  """
  @spec stat_series(Store.stat_name(), date_range()) :: [map()]
  def stat_series(name, %{from: from, to: to}) do
    cached("stat_series:#{name}:#{from}:#{to}", [], fn ->
      with {:ok, points} <- Store.stat_series(name, Query.new(from, to, limit: @series_limit)) do
        {:ok, Enum.map(points, &%{"date" => &1.date, "hits" => &1.value})}
      end
    end)
  end

  @doc """
  Returns the data of a dashboard chart, already shaped for the frontend.

  ## Examples

      iex> PhoenixAnalytics.Web.Data.chart(:visits, %{from: "2025-01-01", to: "2025-01-31"}, "day")
      []
  """
  @spec chart(chart(), date_range(), Query.interval() | String.t()) :: [map()]
  def chart(chart, date_range, interval \\ :day)

  def chart(:visits, %{from: from, to: to}, interval) do
    cached("visits:#{interval}:#{from}:#{to}", [], fn ->
      with {:ok, rows} <- Store.visits_per_period(Query.new(from, to, interval: interval)) do
        {:ok,
         Enum.map(
           rows,
           &%{
             "date" => &1.date,
             "total_visits" => &1.visits,
             "unique_visits" => &1.unique_visitors
           }
         )}
      end
    end)
  end

  def chart(:requests, %{from: from, to: to}, interval) do
    cached("requests:#{interval}:#{from}:#{to}", [], fn ->
      with {:ok, rows} <- Store.requests_per_period(Query.new(from, to, interval: interval)) do
        {:ok, Enum.map(rows, &%{"date" => &1.date, "hits" => &1.hits})}
      end
    end)
  end

  def chart(:statuses, %{from: from, to: to}, interval) do
    cached("statuses:#{interval}:#{from}:#{to}", [], fn ->
      with {:ok, rows} <- Store.statuses_per_period(Query.new(from, to, interval: interval)) do
        {:ok,
         Enum.map(
           rows,
           &%{
             "date" => &1.date,
             "oks" => &1.ok_200s,
             "redirs" => &1.redirects_300s,
             "errors" => &1.errors_400s,
             "fails" => &1.fails_500s
           }
         )}
      end
    end)
  end

  def chart(:devices, %{from: from, to: to}, _interval) do
    cached("devices:#{from}:#{to}", [], fn ->
      with {:ok, rows} <- Store.devices_usage(Query.new(from, to)) do
        {:ok, Enum.map(rows, &%{"device" => &1.device, "visits" => &1.count})}
      end
    end)
  end

  def chart({:popular, kind}, %{from: from, to: to}, _interval) do
    cached("popular:#{kind}:#{from}:#{to}", [], fn ->
      with {:ok, rows} <- Store.popular(kind, Query.new(from, to)) do
        {:ok, Enum.map(rows, &%{"source" => &1.source, "visits" => &1.visits})}
      end
    end)
  end

  def chart({:slowest, kind}, %{from: from, to: to}, _interval) do
    cached("slowest:#{kind}:#{from}:#{to}", [], fn ->
      with {:ok, rows} <- Store.slowest(kind, Query.new(from, to)) do
        {:ok, Enum.map(rows, &%{"path" => &1.path, "duration" => &1.duration})}
      end
    end)
  end

  # A cache failure must not reach the dashboard as if it were data: without the
  # `:error` clause the reason itself, such as `:no_cache`, would be rendered.
  @spec cached(String.t(), term(), (-> {:ok, term()} | {:error, term()})) :: term()
  defp cached(key, default, read) do
    case Cache.fetch(key, fn -> run(read, default) end) do
      {:error, _reason} -> default
      {_status, %Cachex.Error{}} -> default
      {_status, value} -> value
    end
  end

  @spec run((-> {:ok, term()} | {:error, term()}), term()) :: term() | {:ignore, term()}
  defp run(read, default) do
    case read.() do
      {:ok, value} ->
        value

      {:error, reason} ->
        Telemetry.log_error(:fetch_data, reason)
        {:ignore, default}
    end
  rescue
    error ->
      Telemetry.log_error(:fetch_data, error)
      {:ignore, default}
  end
end
