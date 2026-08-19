defmodule PhoenixAnalytics.Store.ETS.TableTest do
  use ExUnit.Case, async: true

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Store.ETS.Table

  setup do
    name = :"table_test_#{System.unique_integer([:positive])}"
    Table.create(name, [])

    %{table: name}
  end

  describe "stream/3" do
    test "both ends of the range are inclusive", %{table: table} do
      Table.insert(table, [
        log("before", ~N[2025-01-13 23:59:59]),
        log("first", ~N[2025-01-14 00:00:00]),
        log("middle", ~N[2025-01-14 12:00:00]),
        log("last", ~N[2025-01-15 23:59:59]),
        log("after", ~N[2025-01-16 00:00:00])
      ])

      assert ids(table, ~N[2025-01-14 00:00:00], ~N[2025-01-15 23:59:59]) ==
               ["first", "middle", "last"]
    end

    test "a single second range keeps the logs of that second", %{table: table} do
      Table.insert(table, [
        log("just_before", ~N[2025-01-14 11:59:59]),
        log("inside", ~N[2025-01-14 12:00:00]),
        log("just_after", ~N[2025-01-14 12:00:01])
      ])

      assert ids(table, ~N[2025-01-14 12:00:00], ~N[2025-01-14 12:00:00]) == ["inside"]
    end

    test "logs sharing a timestamp are all returned", %{table: table} do
      timestamp = ~N[2025-01-14 12:00:00]
      Table.insert(table, [log("a", timestamp), log("b", timestamp), log("c", timestamp)])

      assert ids(table, timestamp, timestamp) == ["a", "b", "c"]
    end

    test "an inverted range is empty", %{table: table} do
      Table.insert(table, [log("a", ~N[2025-01-14 12:00:00])])

      assert ids(table, ~N[2025-01-15 00:00:00], ~N[2025-01-14 00:00:00]) == []
    end

    test "an empty table is empty", %{table: table} do
      assert ids(table, ~N[2020-01-01 00:00:00], ~N[2030-01-01 00:00:00]) == []
    end
  end

  describe "insert/2" do
    test "the same id under a different timestamp is kept twice", %{table: table} do
      # Logs are keyed by timestamp and id, unlike the Ecto store whose primary
      # key is the id alone. Snapshot restore preserves timestamps, so replays
      # stay idempotent; this pins the difference.
      Table.insert(table, [log("a", ~N[2025-01-14 12:00:00])])
      Table.insert(table, [log("a", ~N[2025-01-14 12:00:01])])

      assert :ets.info(table, :size) == 2
    end

    test "re-inserting the same log overwrites it", %{table: table} do
      timestamp = ~N[2025-01-14 12:00:00]
      Table.insert(table, [log("a", timestamp)])
      Table.insert(table, [%{log("a", timestamp) | path: "/updated"}])

      assert [%RequestLog{path: "/updated"}] = Table.range(table, timestamp, timestamp)
      assert :ets.info(table, :size) == 1
    end
  end

  describe "delete_before/2" do
    test "removes only what is older than the cutoff", %{table: table} do
      Table.insert(table, [
        log("old", ~N[2025-01-01 12:00:00]),
        log("edge", ~N[2025-01-10 00:00:00]),
        log("recent", ~N[2025-01-20 12:00:00])
      ])

      assert Table.delete_before(table, ~N[2025-01-10 00:00:00]) == 1
      assert ids(table, ~N[2020-01-01 00:00:00], ~N[2030-01-01 00:00:00]) == ["edge", "recent"]
    end

    test "an empty table deletes nothing", %{table: table} do
      assert Table.delete_before(table, ~N[2025-01-10 00:00:00]) == 0
    end
  end

  describe "trim/2" do
    test "drops the oldest logs down to the limit", %{table: table} do
      logs = for day <- 1..10, do: log("day_#{day}", ~N[2025-01-01 12:00:00] |> add_days(day))
      Table.insert(table, logs)

      assert Table.trim(table, 4) == 6

      assert ids(table, ~N[2020-01-01 00:00:00], ~N[2030-01-01 00:00:00]) ==
               ["day_7", "day_8", "day_9", "day_10"]
    end

    test "does nothing when the table is under the limit", %{table: table} do
      Table.insert(table, [log("a", ~N[2025-01-14 12:00:00])])

      assert Table.trim(table, 10) == 0
      assert :ets.info(table, :size) == 1
    end

    test "empties the table when the limit is smaller than one batch", %{table: table} do
      Table.insert(table, [log("a", ~N[2025-01-14 12:00:00]), log("b", ~N[2025-01-15 12:00:00])])

      assert Table.trim(table, 0) == 2
      assert :ets.info(table, :size) == 0
    end
  end

  describe "info/1" do
    test "reports the span of the stored logs", %{table: table} do
      Table.insert(table, [
        log("a", ~N[2025-01-14 12:00:00]),
        log("b", ~N[2025-01-16 08:30:00])
      ])

      assert %{count: 2, oldest: ~N[2025-01-14 12:00:00], newest: ~N[2025-01-16 08:30:00]} =
               Table.info(table)
    end

    test "an empty table has no span", %{table: table} do
      assert %{count: 0, oldest: nil, newest: nil} = Table.info(table)
    end
  end

  @spec ids(atom(), NaiveDateTime.t(), NaiveDateTime.t()) :: [String.t()]
  defp ids(table, from, to), do: table |> Table.range(from, to) |> Enum.map(& &1.request_id)

  @spec add_days(NaiveDateTime.t(), pos_integer()) :: NaiveDateTime.t()
  defp add_days(timestamp, days), do: NaiveDateTime.add(timestamp, days, :day)

  @spec log(String.t(), NaiveDateTime.t()) :: RequestLog.t()
  defp log(request_id, inserted_at) do
    %RequestLog{
      request_id: request_id,
      method: "GET",
      path: "/home",
      status_code: 200,
      duration_ms: 10,
      inserted_at: inserted_at
    }
  end
end
