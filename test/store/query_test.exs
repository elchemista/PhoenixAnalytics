defmodule PhoenixAnalytics.Store.QueryTest do
  use ExUnit.Case, async: true

  alias PhoenixAnalytics.Store.Query

  describe "new/3" do
    test "expands dates to the full day" do
      query = Query.new(~D[2025-01-14], ~D[2025-01-15])

      assert query.from == ~N[2025-01-14 00:00:00]
      assert query.to == ~N[2025-01-15 23:59:59]
    end

    test "keeps naive date times untouched" do
      query = Query.new(~N[2025-01-14 08:30:00], ~N[2025-01-14 09:30:00])

      assert query.from == ~N[2025-01-14 08:30:00]
      assert query.to == ~N[2025-01-14 09:30:00]
    end

    test "parses the strings sent by the dashboard" do
      query = Query.new("2025-01-14 00:00:00", "2025-01-15 23:59:59")

      assert query.from == ~N[2025-01-14 00:00:00]
      assert query.to == ~N[2025-01-15 23:59:59]
    end

    test "parses date only strings" do
      query = Query.new("2025-01-14", "2025-01-15")

      assert query.from == ~N[2025-01-14 00:00:00]
      assert query.to == ~N[2025-01-15 23:59:59]
    end

    test "defaults to a daily interval without limit" do
      query = Query.new(~D[2025-01-14], ~D[2025-01-15])

      assert query.interval == :day
      assert query.limit == nil
    end

    test "accepts the interval as a string" do
      assert Query.new(~D[2025-01-14], ~D[2025-01-15], interval: "hour").interval == :hour
      assert Query.new(~D[2025-01-14], ~D[2025-01-15], interval: :month).interval == :month
    end

    test "rejects an unknown interval" do
      assert_raise FunctionClauseError, fn ->
        Query.new(~D[2025-01-14], ~D[2025-01-15], interval: :century)
      end
    end
  end
end
