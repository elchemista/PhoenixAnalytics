defmodule PhoenixAnalytics.Store.ETS.RetentionTest do
  use ExUnit.Case, async: false

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Store.ETS

  @table :phoenix_analytics_retention_test

  describe "retention_days" do
    test "drops logs older than the window and keeps the rest" do
      pid = start_store(retention_days: 30)
      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

      :ok =
        ETS.insert_all(
          [
            log("ancient", NaiveDateTime.add(now, -400, :day)),
            log("old", NaiveDateTime.add(now, -31, :day)),
            log("kept", NaiveDateTime.add(now, -29, :day)),
            log("fresh", now)
          ],
          opts()
        )

      prune(pid)

      assert stored() == ["kept", "fresh"]
    end

    test "a log exactly on the boundary is kept" do
      pid = start_store(retention_days: 10)
      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

      # One second inside the window, so clock drift during the test cannot
      # push it over the edge and make this flaky.
      :ok =
        ETS.insert_all([log("edge", NaiveDateTime.add(now, -10 * 86_400 + 1, :second))], opts())

      prune(pid)

      assert stored() == ["edge"]
    end
  end

  describe "max_entries" do
    test "keeps only the newest logs once the cap is exceeded" do
      pid = start_store(retention_days: 3650, max_entries: 3)
      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

      logs = for minute <- 1..6, do: log("m#{minute}", NaiveDateTime.add(now, minute, :minute))
      :ok = ETS.insert_all(logs, opts())
      prune(pid)

      assert stored() == ["m4", "m5", "m6"]
    end

    test "is not applied when unset" do
      pid = start_store(retention_days: 3650)
      now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

      logs = for minute <- 1..6, do: log("m#{minute}", NaiveDateTime.add(now, minute, :minute))
      :ok = ETS.insert_all(logs, opts())
      prune(pid)

      assert length(stored()) == 6
    end
  end

  describe "prune/2" do
    test "reports how many logs it removed" do
      start_store(retention_days: 3650)

      :ok =
        ETS.insert_all(
          [log("a", ~N[2025-01-01 12:00:00]), log("b", ~N[2025-06-01 12:00:00])],
          opts()
        )

      assert {:ok, 1} = ETS.prune(~N[2025-03-01 00:00:00], opts())
      assert {:ok, 0} = ETS.prune(~N[2025-03-01 00:00:00], opts())
    end
  end

  @spec start_store(keyword()) :: pid()
  defp start_store(opts) do
    start_supervised!(
      {ETS, Keyword.merge([table: @table, prune_interval_ms: :timer.hours(24)], opts)}
    )
  end

  # Retention runs on a timer; sending the message and then waiting on the
  # process makes the test deterministic instead of time dependent.
  @spec prune(pid()) :: :ok
  defp prune(pid) do
    send(pid, :prune)
    :sys.get_state(pid)

    :ok
  end

  @spec opts() :: keyword()
  defp opts, do: [table: @table]

  @spec stored() :: [String.t()]
  defp stored do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, _log} -> key end)
    |> Enum.map(fn {_key, log} -> log.request_id end)
  end

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
