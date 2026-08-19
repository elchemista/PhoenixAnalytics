defmodule PhoenixAnalytics.Store.ETS.Aggregate do
  @moduledoc """
  Pure analytics folds over a list of request logs.

  These functions mirror, in Elixir, the exact semantics of the SQL queries in
  `PhoenixAnalytics.Queries.Analytics`: same filters, same grouping, same
  limits. They take plain lists, so they can be tested without ETS, without a
  database and without an application running.
  """

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Filters
  alias PhoenixAnalytics.Store
  alias PhoenixAnalytics.Store.Bucket
  alias PhoenixAnalytics.Store.Query

  @popular_limit 9
  @slowest_limit 6
  @session_stats [:views_per_visit, :visit_duration, :bounce_rate]

  @doc """
  Returns the single aggregated number of a stat card.

  ## Examples

      iex> logs = [%PhoenixAnalytics.Entities.RequestLog{remote_ip: "a"}]
      iex> PhoenixAnalytics.Store.ETS.Aggregate.stat(logs, :total_requests)
      1
  """
  @spec stat([RequestLog.t()], Store.stat_name()) :: number()
  def stat(logs, :unique_visitors) do
    logs
    |> Enum.map(& &1.remote_ip)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> length()
  end

  def stat(logs, :total_pageviews), do: Enum.count(logs, &Filters.pageview?/1)
  def stat(logs, :total_requests), do: length(logs)

  def stat(logs, :views_per_visit) do
    logs |> Enum.map(& &1.session_page_views) |> mean()
  end

  def stat(logs, :visit_duration) do
    logs |> sessions() |> Enum.map(&session_duration/1) |> mean()
  end

  def stat(logs, :bounce_rate), do: logs |> sessions() |> bounce_rate()

  @doc """
  Returns the per period series backing a stat card.

  Session based metrics ignore logs without a session, the same way the SQL
  subqueries filter out `NULL` session ids.
  """
  @spec stat_series([RequestLog.t()], Store.stat_name(), Query.t()) :: [Store.point()]
  def stat_series(logs, name, %Query{} = query) do
    logs
    |> Enum.filter(&series_log?(&1, name))
    |> group_by_period(query.interval)
    |> take(query.limit)
    |> Enum.map(fn {date, group} -> %{date: date, value: round2(series_value(group, name))} end)
  end

  @doc "Returns visits and unique visitors per period, assets excluded."
  @spec visits_per_period([RequestLog.t()], Query.t()) :: [Store.visits_row()]
  def visits_per_period(logs, %Query{} = query) do
    logs
    |> Enum.filter(&Filters.page_path?(&1.path))
    |> group_by_period(query.interval)
    |> Enum.map(fn {date, group} ->
      %{date: date, visits: length(group), unique_visitors: stat(group, :unique_visitors)}
    end)
  end

  @doc "Returns request counts per period."
  @spec requests_per_period([RequestLog.t()], Query.t()) :: [Store.requests_row()]
  def requests_per_period(logs, %Query{} = query) do
    logs
    |> group_by_period(query.interval)
    |> Enum.map(fn {date, group} -> %{date: date, hits: length(group)} end)
  end

  @doc "Returns status code families per period."
  @spec statuses_per_period([RequestLog.t()], Query.t()) :: [Store.statuses_row()]
  def statuses_per_period(logs, %Query{} = query) do
    logs
    |> group_by_period(query.interval)
    |> Enum.map(fn {date, group} ->
      %{
        date: date,
        ok_200s: count_status(group, 200..299),
        redirects_300s: count_status(group, 300..399),
        errors_400s: count_status(group, 400..499),
        fails_500s: count_status(group, 500..599)
      }
    end)
  end

  @doc "Returns request counts per device type, assets and dev paths excluded."
  @spec devices_usage([RequestLog.t()], Query.t()) :: [Store.device_row()]
  def devices_usage(logs, %Query{} = _query) do
    logs
    |> Enum.filter(&page?/1)
    |> count_by(& &1.device_type, :device, :count, nil)
  end

  @doc "Returns the most frequent sources of the given dimension."
  @spec popular([RequestLog.t()], Store.popular_kind(), String.t()) :: [Store.popular_row()]
  def popular(logs, :pages, _app_domain) do
    logs
    |> Enum.filter(&(&1.status_code == 200 and page?(&1)))
    |> count_by(& &1.path, :source, :visits, @popular_limit)
  end

  def popular(logs, :referers, app_domain) do
    logs
    |> Enum.filter(&Filters.external_referer?(&1.referer, app_domain))
    |> count_by(& &1.referer, :source, :visits, @popular_limit)
  end

  def popular(logs, :not_founds, _app_domain) do
    logs
    |> Enum.filter(&(&1.status_code == 404))
    |> count_by(& &1.path, :source, :visits, @popular_limit)
  end

  def popular(logs, :user_agents, _app_domain) do
    count_by(logs, & &1.user_agent, :source, :visits, @popular_limit)
  end

  def popular(logs, :device_types, _app_domain) do
    count_by(logs, & &1.device_type, :source, :visits, @popular_limit)
  end

  @doc "Returns the slowest paths by average duration."
  @spec slowest([RequestLog.t()], Store.slowest_kind()) :: [Store.slowest_row()]
  def slowest(logs, :pages) do
    logs
    |> Enum.filter(&(&1.status_code == 200 and page?(&1)))
    |> average_duration_by_path()
  end

  def slowest(logs, :resources) do
    logs
    |> Enum.filter(&(&1.status_code == 200 and resource?(&1)))
    |> average_duration_by_path()
  end

  @spec page?(RequestLog.t()) :: boolean()
  defp page?(log), do: Filters.page_path?(log.path) and not Filters.dev_path?(log.path)

  @spec resource?(RequestLog.t()) :: boolean()
  defp resource?(log), do: Filters.resource_path?(log.path) and not Filters.dev_path?(log.path)

  @spec series_log?(RequestLog.t(), Store.stat_name()) :: boolean()
  defp series_log?(log, name) when name in @session_stats, do: not is_nil(log.session_id)
  defp series_log?(_log, _name), do: true

  # Views per visit is averaged over rows for the card and over sessions for the
  # series, exactly like the two SQL queries behind them.
  @spec series_value([RequestLog.t()], Store.stat_name()) :: number()
  defp series_value(logs, :views_per_visit) do
    logs |> sessions() |> Enum.map(&session_page_views/1) |> mean()
  end

  defp series_value(logs, name), do: stat(logs, name)

  @spec group_by_period([RequestLog.t()], Query.interval()) :: [{String.t(), [RequestLog.t()]}]
  defp group_by_period(logs, interval) do
    logs
    |> Enum.group_by(&Bucket.key(&1.inserted_at, interval))
    |> Enum.sort_by(fn {period, _group} -> period end)
  end

  @spec count_status([RequestLog.t()], Range.t()) :: non_neg_integer()
  defp count_status(logs, range), do: Enum.count(logs, &(&1.status_code in range))

  # Ties are broken by key so the same data always renders in the same order.
  @spec count_by(
          [RequestLog.t()],
          (RequestLog.t() -> term()),
          atom(),
          atom(),
          pos_integer() | nil
        ) ::
          [map()]
  defp count_by(logs, key_fun, key_name, count_name, limit) do
    logs
    |> Enum.group_by(key_fun)
    |> Enum.map(fn {key, group} -> %{key_name => key, count_name => length(group)} end)
    |> Enum.sort_by(&{-Map.fetch!(&1, count_name), Map.fetch!(&1, key_name)})
    |> take(limit)
  end

  @spec average_duration_by_path([RequestLog.t()]) :: [Store.slowest_row()]
  defp average_duration_by_path(logs) do
    logs
    |> Enum.group_by(& &1.path)
    |> Enum.map(fn {path, group} ->
      %{path: path, duration: group |> Enum.map(& &1.duration_ms) |> mean() |> round2()}
    end)
    |> Enum.sort_by(&{-&1.duration, &1.path})
    |> take(@slowest_limit)
  end

  # `GROUP BY session_id` puts every log without a session in a single group,
  # which is what SQL does too.
  @spec sessions([RequestLog.t()]) :: [[RequestLog.t()]]
  defp sessions(logs), do: logs |> Enum.group_by(& &1.session_id) |> Map.values()

  @spec session_duration([RequestLog.t()]) :: integer()
  defp session_duration(logs) do
    timestamps = Enum.map(logs, & &1.inserted_at)
    first = Enum.min(timestamps, NaiveDateTime)
    last = Enum.max(timestamps, NaiveDateTime)

    NaiveDateTime.diff(last, first, :millisecond)
  end

  @spec session_page_views([RequestLog.t()]) :: non_neg_integer() | nil
  defp session_page_views(logs) do
    logs
    |> Enum.map(& &1.session_page_views)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> nil end)
  end

  @spec bounce_rate([[RequestLog.t()]]) :: number()
  defp bounce_rate([]), do: 0

  defp bounce_rate(sessions) do
    bounced = Enum.count(sessions, &(session_page_views(&1) == 1))

    round2(100.0 * bounced / length(sessions))
  end

  # `AVG` ignores NULL values and returns NULL for an empty set, which the
  # stores normalize to 0.
  @spec mean([number() | nil]) :: number()
  defp mean(values) do
    case Enum.reject(values, &is_nil/1) do
      [] -> 0
      numbers -> Enum.sum(numbers) / length(numbers)
    end
  end

  @spec round2(number()) :: number()
  defp round2(value) when is_float(value), do: Float.round(value, 2)
  defp round2(value), do: value

  @spec take([term()], pos_integer() | nil) :: [term()]
  defp take(list, nil), do: list
  defp take(list, limit), do: Enum.take(list, limit)
end
