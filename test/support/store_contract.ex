defmodule PhoenixAnalytics.StoreContract do
  @moduledoc """
  Shared behavioural contract every `PhoenixAnalytics.Store` adapter must honour.

  Each adapter runs the same assertions over the same fixtures, which is what
  guarantees the dashboard shows identical numbers whichever backend is
  configured.

      use PhoenixAnalytics.StoreContract, store: {PhoenixAnalytics.Store.ETS, table: :my_table}

  The using module is responsible for starting the adapter and for emptying it
  between tests.
  """

  @doc false
  defmacro __using__(store: {module, opts}) do
    quote do
      import PhoenixAnalytics.StoreContract

      alias PhoenixAnalytics.Fixtures
      alias PhoenixAnalytics.Store.Query

      @store unquote(module)
      @store_opts unquote(opts)

      setup do
        :ok = @store.insert_all(Fixtures.request_logs(), @store_opts)
        :ok
      end

      unquote(stats_tests())
      unquote(stat_series_tests())
      unquote(chart_tests())
      unquote(maintenance_tests())
    end
  end

  # The contract is split into sections so each quoted block stays readable and
  # short; they are spliced together by __using__/1 above.
  @spec stats_tests() :: Macro.t()
  defp stats_tests do
    quote do
      describe "stats" do
        test "unique visitors" do
          assert {:ok, 2} = @store.stat(:unique_visitors, day(Fixtures.today()), @store_opts)
          assert {:ok, 1} = @store.stat(:unique_visitors, day(Fixtures.yesterday()), @store_opts)
          assert {:ok, 0} = @store.stat(:unique_visitors, day(Fixtures.empty_day()), @store_opts)
        end

        test "total requests" do
          assert {:ok, 3} = @store.stat(:total_requests, day(Fixtures.today()), @store_opts)
          assert {:ok, 2} = @store.stat(:total_requests, day(Fixtures.yesterday()), @store_opts)
          assert {:ok, 0} = @store.stat(:total_requests, day(Fixtures.empty_day()), @store_opts)
        end

        test "total pageviews counts only successful GET pages" do
          assert {:ok, 3} = @store.stat(:total_pageviews, day(Fixtures.today()), @store_opts)
          assert {:ok, 1} = @store.stat(:total_pageviews, day(Fixtures.yesterday()), @store_opts)
          assert {:ok, 0} = @store.stat(:total_pageviews, day(Fixtures.empty_day()), @store_opts)
        end

        test "views per visit averages page views over requests" do
          {:ok, value} = @store.stat(:views_per_visit, day(Fixtures.today()), @store_opts)
          assert_in_delta value, 4 / 3, 0.001
        end

        test "visit duration averages session spans" do
          {:ok, value} = @store.stat(:visit_duration, day(Fixtures.today()), @store_opts)
          assert_in_delta value, 15_000, 1
        end

        test "bounce rate is the share of single page sessions" do
          {:ok, today} = @store.stat(:bounce_rate, day(Fixtures.today()), @store_opts)
          {:ok, yesterday} = @store.stat(:bounce_rate, day(Fixtures.yesterday()), @store_opts)

          assert_in_delta today, 50.0, 0.001
          assert_in_delta yesterday, 0.0, 0.001
        end
      end
    end
  end

  @spec stat_series_tests() :: Macro.t()
  defp stat_series_tests do
    quote do
      describe "stat series" do
        test "unique visitors per day" do
          {:ok, points} = @store.stat_series(:unique_visitors, range(), @store_opts)
          assert points == [%{date: "2025-01-14", value: 1}, %{date: "2025-01-15", value: 2}]
        end

        test "total requests per day" do
          {:ok, points} = @store.stat_series(:total_requests, range(), @store_opts)
          assert points == [%{date: "2025-01-14", value: 2}, %{date: "2025-01-15", value: 3}]
        end

        test "total pageviews per day" do
          {:ok, points} = @store.stat_series(:total_pageviews, range(), @store_opts)
          assert points == [%{date: "2025-01-14", value: 1}, %{date: "2025-01-15", value: 3}]
        end

        test "views per visit per day averages sessions" do
          {:ok, points} = @store.stat_series(:views_per_visit, range(), @store_opts)

          assert [%{date: "2025-01-14", value: two}, %{date: "2025-01-15", value: one_and_half}] =
                   points

          assert_in_delta two, 2.0, 0.001
          assert_in_delta one_and_half, 1.5, 0.001
        end

        test "bounce rate per day" do
          {:ok, points} = @store.stat_series(:bounce_rate, range(), @store_opts)
          assert [%{date: "2025-01-14", value: none}, %{date: "2025-01-15", value: half}] = points
          assert_in_delta none, 0.0, 0.001
          assert_in_delta half, 50.0, 0.001
        end

        test "visit duration per day" do
          {:ok, points} = @store.stat_series(:visit_duration, range(), @store_opts)

          assert [%{date: "2025-01-14", value: zero}, %{date: "2025-01-15", value: fifteen}] =
                   points

          assert_in_delta zero, 0.0, 1
          assert_in_delta fifteen, 15_000, 1
        end

        test "series are empty without data" do
          {:ok, points} =
            @store.stat_series(:total_requests, day(Fixtures.empty_day()), @store_opts)

          assert points == []
        end
      end
    end
  end

  @spec chart_tests() :: Macro.t()
  defp chart_tests do
    quote do
      describe "charts" do
        test "visits per day" do
          {:ok, rows} = @store.visits_per_period(range(), @store_opts)

          assert rows == [
                   %{date: "2025-01-14", visits: 2, unique_visitors: 1},
                   %{date: "2025-01-15", visits: 3, unique_visitors: 2}
                 ]
        end

        test "visits per month" do
          {:ok, rows} = @store.visits_per_period(wide_range(:month), @store_opts)

          assert rows == [
                   %{date: "2024-01", visits: 1, unique_visitors: 1},
                   %{date: "2024-12", visits: 1, unique_visitors: 1},
                   %{date: "2025-01", visits: 5, unique_visitors: 3}
                 ]
        end

        test "visits per year" do
          {:ok, rows} = @store.visits_per_period(wide_range(:year), @store_opts)

          assert rows == [
                   %{date: "2024", visits: 2, unique_visitors: 2},
                   %{date: "2025", visits: 5, unique_visitors: 3}
                 ]
        end

        test "requests per day" do
          {:ok, rows} = @store.requests_per_period(range(), @store_opts)
          assert rows == [%{date: "2025-01-14", hits: 2}, %{date: "2025-01-15", hits: 3}]
        end

        test "statuses per day" do
          {:ok, rows} = @store.statuses_per_period(range(), @store_opts)

          assert rows == [
                   %{
                     date: "2025-01-14",
                     ok_200s: 1,
                     redirects_300s: 0,
                     errors_400s: 1,
                     fails_500s: 0
                   },
                   %{
                     date: "2025-01-15",
                     ok_200s: 3,
                     redirects_300s: 0,
                     errors_400s: 0,
                     fails_500s: 0
                   }
                 ]
        end

        test "devices usage" do
          {:ok, rows} = @store.devices_usage(range(), @store_opts)
          assert Map.new(rows, &{&1.device, &1.count}) == %{"desktop" => 4, "mobile" => 1}
        end

        test "popular pages" do
          {:ok, rows} = @store.popular(:pages, range(), @store_opts)

          assert Map.new(rows, &{&1.source, &1.visits}) == %{
                   "/home" => 1,
                   "/about" => 1,
                   "/contact" => 1,
                   "/products" => 1
                 }
        end

        test "popular referers exclude internal traffic" do
          {:ok, rows} = @store.popular(:referers, range(), @store_opts)

          assert Map.new(rows, &{&1.source, &1.visits}) == %{
                   "https://google.com" => 2,
                   "https://facebook.com" => 1,
                   "https://twitter.com" => 2
                 }
        end

        test "popular not founds" do
          {:ok, rows} = @store.popular(:not_founds, range(), @store_opts)
          assert Map.new(rows, &{&1.source, &1.visits}) == %{"/services" => 1}
        end

        test "slowest pages are ordered by average duration" do
          {:ok, rows} = @store.slowest(:pages, range(), @store_opts)

          assert Enum.map(rows, & &1.path) == ["/products", "/about", "/contact", "/home"]
          assert Enum.map(rows, &round(&1.duration)) == [200, 150, 120, 100]
        end

        test "charts are empty without data" do
          empty = day(Fixtures.empty_day())

          assert {:ok, []} = @store.visits_per_period(empty, @store_opts)
          assert {:ok, []} = @store.requests_per_period(empty, @store_opts)
          assert {:ok, []} = @store.statuses_per_period(empty, @store_opts)
          assert {:ok, []} = @store.devices_usage(empty, @store_opts)
          assert {:ok, []} = @store.popular(:pages, empty, @store_opts)
          assert {:ok, []} = @store.slowest(:pages, empty, @store_opts)
        end
      end
    end
  end

  @spec maintenance_tests() :: Macro.t()
  defp maintenance_tests do
    quote do
      describe "maintenance" do
        test "export streams the logs of a period" do
          {:ok, logs} = @store.export(range(), &Enum.to_list/1, @store_opts)

          assert length(logs) == 5
          assert Enum.all?(logs, &match?(%PhoenixAnalytics.Entities.RequestLog{}, &1))
        end

        test "import is idempotent" do
          {:ok, logs} = @store.export(range(), &Enum.to_list/1, @store_opts)
          {:ok, _count} = @store.import_all(logs, @store_opts)

          assert {:ok, 3} = @store.stat(:total_requests, day(Fixtures.today()), @store_opts)
        end

        test "prune deletes older logs" do
          {:ok, deleted} = @store.prune(~N[2025-01-15 00:00:00], @store_opts)

          assert deleted == 4
          assert {:ok, 3} = @store.stat(:total_requests, day(Fixtures.today()), @store_opts)
          assert {:ok, 0} = @store.stat(:total_requests, day(Fixtures.yesterday()), @store_opts)
        end

        test "info reports the stored count" do
          assert %{count: 7} = @store.info(@store_opts)
        end
      end
    end
  end

  @doc "Query covering a single day."
  @spec day(Date.t()) :: PhoenixAnalytics.Store.Query.t()
  def day(date), do: PhoenixAnalytics.Store.Query.new(date, date)

  @doc "Query covering the two most recent fixture days."
  @spec range() :: PhoenixAnalytics.Store.Query.t()
  def range do
    PhoenixAnalytics.Store.Query.new(~D[2025-01-14], ~D[2025-01-15], limit: 30)
  end

  @doc "Query covering every fixture, bucketed by the given interval."
  @spec wide_range(PhoenixAnalytics.Store.Query.interval()) :: PhoenixAnalytics.Store.Query.t()
  def wide_range(interval) do
    PhoenixAnalytics.Store.Query.new(~D[2024-01-01], ~D[2025-12-31], interval: interval)
  end
end
