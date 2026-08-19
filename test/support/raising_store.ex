defmodule PhoenixAnalytics.Web.DataTest.RaisingStore do
  @moduledoc "Store adapter that raises, used to test the dashboard fallbacks."

  @behaviour PhoenixAnalytics.Store

  @impl PhoenixAnalytics.Store
  def insert_all(_logs, _opts), do: raise("boom")

  @impl PhoenixAnalytics.Store
  def stat(_name, _query, _opts), do: raise("boom")

  @impl PhoenixAnalytics.Store
  def stat_series(_name, _query, _opts), do: raise("boom")

  @impl PhoenixAnalytics.Store
  def visits_per_period(_query, _opts), do: raise("boom")

  @impl PhoenixAnalytics.Store
  def requests_per_period(_query, _opts), do: raise("boom")

  @impl PhoenixAnalytics.Store
  def statuses_per_period(_query, _opts), do: raise("boom")

  @impl PhoenixAnalytics.Store
  def devices_usage(_query, _opts), do: raise("boom")

  @impl PhoenixAnalytics.Store
  def popular(_kind, _query, _opts), do: raise("boom")

  @impl PhoenixAnalytics.Store
  def slowest(_kind, _query, _opts), do: raise("boom")
end
