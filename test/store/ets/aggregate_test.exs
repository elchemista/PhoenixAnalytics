defmodule PhoenixAnalytics.Store.ETS.AggregateTest do
  use ExUnit.Case, async: true

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Store.ETS.Aggregate
  alias PhoenixAnalytics.Store.Query

  @query Query.new(~D[2025-01-15], ~D[2025-01-15])

  describe "stat/2" do
    test "unique visitors ignore missing addresses" do
      logs = [log(remote_ip: "a"), log(remote_ip: "a"), log(remote_ip: "b"), log(remote_ip: nil)]

      assert Aggregate.stat(logs, :unique_visitors) == 2
    end

    test "views per visit averages over requests and ignores nil" do
      logs = [
        log(session_page_views: 1),
        log(session_page_views: 3),
        log(session_page_views: nil)
      ]

      assert Aggregate.stat(logs, :views_per_visit) == 2.0
    end

    test "averages of an empty set are zero" do
      assert Aggregate.stat([], :views_per_visit) == 0
      assert Aggregate.stat([], :visit_duration) == 0
      assert Aggregate.stat([], :bounce_rate) == 0
    end

    test "visit duration spans the session" do
      logs = [
        log(session_id: "a", inserted_at: ~N[2025-01-15 12:00:00]),
        log(session_id: "a", inserted_at: ~N[2025-01-15 12:00:10])
      ]

      assert Aggregate.stat(logs, :visit_duration) == 10_000.0
    end

    test "bounce rate counts sessions with a single page view" do
      logs = [
        log(session_id: "a", session_page_views: 1),
        log(session_id: "b", session_page_views: 1),
        log(session_id: "b", session_page_views: 2),
        log(session_id: "c", session_page_views: 1)
      ]

      assert Aggregate.stat(logs, :bounce_rate) == 66.67
    end

    test "a session whose page views are all missing does not bounce" do
      assert Aggregate.stat([log(session_id: "a", session_page_views: nil)], :bounce_rate) == 0.0
    end
  end

  describe "stat_series/3" do
    test "views per visit averages sessions, not requests" do
      logs = [
        log(session_id: "a", session_page_views: 1),
        log(session_id: "a", session_page_views: 3),
        log(session_id: "b", session_page_views: 2)
      ]

      # Per session maxima are 3 and 2, so the daily average is 2.5, while the
      # stat card averages the three raw values instead.
      assert Aggregate.stat_series(logs, :views_per_visit, @query) == [
               %{date: "2025-01-15", value: 2.5}
             ]
    end

    test "session metrics ignore logs without a session" do
      logs = [
        log(session_id: nil, session_page_views: 9),
        log(session_id: "a", session_page_views: 1)
      ]

      assert Aggregate.stat_series(logs, :views_per_visit, @query) == [
               %{date: "2025-01-15", value: 1.0}
             ]
    end

    test "buckets are ordered and limited" do
      logs = [
        log(inserted_at: ~N[2025-01-17 12:00:00]),
        log(inserted_at: ~N[2025-01-15 12:00:00]),
        log(inserted_at: ~N[2025-01-16 12:00:00])
      ]

      query = Query.new(~D[2025-01-15], ~D[2025-01-17], limit: 2)

      assert Aggregate.stat_series(logs, :total_requests, query) == [
               %{date: "2025-01-15", value: 1},
               %{date: "2025-01-16", value: 1}
             ]
    end
  end

  describe "popular/3" do
    test "ties are broken by source so the order is stable" do
      logs = [log(path: "/b", status_code: 200), log(path: "/a", status_code: 200)]

      assert Aggregate.popular(logs, :pages, "example.com") == [
               %{source: "/a", visits: 1},
               %{source: "/b", visits: 1}
             ]
    end

    test "referers from the application domain are excluded" do
      logs = [
        log(referer: "https://example.com/home"),
        log(referer: "https://google.com"),
        log(referer: nil)
      ]

      assert Aggregate.popular(logs, :referers, "example.com") == [
               %{source: "https://google.com", visits: 1}
             ]
    end
  end

  describe "slowest/2" do
    test "pages are averaged per path and ordered by duration" do
      logs = [
        log(path: "/slow", status_code: 200, duration_ms: 300),
        log(path: "/slow", status_code: 200, duration_ms: 100),
        log(path: "/fast", status_code: 200, duration_ms: 50)
      ]

      assert Aggregate.slowest(logs, :pages) == [
               %{path: "/slow", duration: 200.0},
               %{path: "/fast", duration: 50.0}
             ]
    end

    test "resources exclude regular pages" do
      logs = [
        log(path: "/app.js", status_code: 200, duration_ms: 10),
        log(path: "/home", status_code: 200, duration_ms: 10)
      ]

      assert Aggregate.slowest(logs, :resources) == [%{path: "/app.js", duration: 10.0}]
    end
  end

  describe "devices_usage/2" do
    test "counts pages per device type" do
      logs = [
        log(device_type: "desktop", path: "/home"),
        log(device_type: "desktop", path: "/about"),
        log(device_type: "mobile", path: "/home"),
        log(device_type: "mobile", path: "/app.js")
      ]

      assert Aggregate.devices_usage(logs, @query) == [
               %{device: "desktop", count: 2},
               %{device: "mobile", count: 1}
             ]
    end
  end

  @spec log(keyword()) :: RequestLog.t()
  defp log(attrs) do
    defaults = %RequestLog{
      request_id: "req",
      method: "GET",
      path: "/home",
      status_code: 200,
      duration_ms: 10,
      remote_ip: "ip",
      device_type: "desktop",
      session_id: "session",
      session_page_views: 1,
      inserted_at: ~N[2025-01-15 12:00:00]
    }

    struct!(defaults, attrs)
  end
end
