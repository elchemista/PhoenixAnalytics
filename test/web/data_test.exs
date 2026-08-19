defmodule PhoenixAnalytics.Web.DataTest do
  use ExUnit.Case, async: false

  alias PhoenixAnalytics.Fixtures
  alias PhoenixAnalytics.Services.Cache
  alias PhoenixAnalytics.Store
  alias PhoenixAnalytics.Web.Data

  @table :phoenix_analytics_data_test
  @range %{from: "2025-01-14 00:00:00", to: "2025-01-15 23:59:59"}

  setup do
    start_supervised!(
      {PhoenixAnalytics.Store.ETS, table: @table, prune_interval_ms: :timer.hours(24)}
    )

    previous = Application.get_env(:phoenix_analytics, :store)
    Application.put_env(:phoenix_analytics, :store, {PhoenixAnalytics.Store.ETS, table: @table})
    Cachex.clear(Cache.name())
    on_exit(fn -> restore_env(previous) end)

    :ok = Store.insert_all(Fixtures.request_logs())
    :ok
  end

  describe "stat/2" do
    test "returns the aggregated number" do
      assert Data.stat(:total_requests, @range) == 5
      assert Data.stat(:unique_visitors, @range) == 3
    end

    test "falls back to zero when the store fails" do
      Application.put_env(:phoenix_analytics, :store, {__MODULE__.BrokenStore, []})

      assert Data.stat(:total_requests, %{from: "2020-01-01", to: "2020-01-02"}) == 0
    end
  end

  describe "stat_series/2" do
    test "returns sparkline points keyed for the frontend" do
      assert Data.stat_series(:total_requests, @range) == [
               %{"date" => "2025-01-14", "hits" => 2},
               %{"date" => "2025-01-15", "hits" => 3}
             ]
    end
  end

  describe "chart/3" do
    test "visits" do
      assert Data.chart(:visits, @range, "day") == [
               %{"date" => "2025-01-14", "total_visits" => 2, "unique_visits" => 1},
               %{"date" => "2025-01-15", "total_visits" => 3, "unique_visits" => 2}
             ]
    end

    test "requests" do
      assert Data.chart(:requests, @range, "day") == [
               %{"date" => "2025-01-14", "hits" => 2},
               %{"date" => "2025-01-15", "hits" => 3}
             ]
    end

    test "statuses" do
      assert Data.chart(:statuses, @range, "day") == [
               %{
                 "date" => "2025-01-14",
                 "oks" => 1,
                 "redirs" => 0,
                 "errors" => 1,
                 "fails" => 0
               },
               %{"date" => "2025-01-15", "oks" => 3, "redirs" => 0, "errors" => 0, "fails" => 0}
             ]
    end

    test "devices" do
      assert Data.chart(:devices, @range) == [
               %{"device" => "desktop", "visits" => 4},
               %{"device" => "mobile", "visits" => 1}
             ]
    end

    test "popular pages" do
      rows = Data.chart({:popular, :pages}, @range)

      assert Enum.map(rows, & &1["source"]) == ["/about", "/contact", "/home", "/products"]
      assert Enum.all?(rows, &(&1["visits"] == 1))
    end

    test "slowest pages" do
      assert Data.chart({:slowest, :pages}, @range) == [
               %{"path" => "/products", "duration" => 200.0},
               %{"path" => "/about", "duration" => 150.0},
               %{"path" => "/contact", "duration" => 120.0},
               %{"path" => "/home", "duration" => 100.0}
             ]
    end

    test "falls back to an empty list when the store fails" do
      Application.put_env(:phoenix_analytics, :store, {__MODULE__.BrokenStore, []})

      assert Data.chart(:visits, %{from: "2020-01-01", to: "2020-01-02"}, "day") == []
    end
  end

  @spec restore_env(term()) :: :ok
  defp restore_env(nil), do: Application.delete_env(:phoenix_analytics, :store)
  defp restore_env(previous), do: Application.put_env(:phoenix_analytics, :store, previous)
end
