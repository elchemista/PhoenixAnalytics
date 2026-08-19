defmodule PhoenixAnalytics.Services.BatcherTest do
  use ExUnit.Case, async: false

  alias PhoenixAnalytics.Entities.RequestLog
  alias PhoenixAnalytics.Services.Batcher
  alias PhoenixAnalytics.Store

  @table :phoenix_analytics_batcher_test

  setup do
    start_supervised!(
      {PhoenixAnalytics.Store.ETS, table: @table, prune_interval_ms: :timer.hours(24)}
    )

    previous = Application.get_env(:phoenix_analytics, :store)
    Application.put_env(:phoenix_analytics, :store, {PhoenixAnalytics.Store.ETS, table: @table})
    on_exit(fn -> restore_env(previous) end)

    :ok
  end

  describe "send_batch/1" do
    test "writes the logs to the configured store" do
      assert :ok = Batcher.send_batch([log("a"), log("b")])
      assert %{count: 2} = Store.info()
    end

    test "an empty batch is a no-op" do
      assert :ok = Batcher.send_batch([])
      assert %{count: 0} = Store.info()
    end

    test "a failing store is reported through telemetry and never raises" do
      Application.put_env(
        :phoenix_analytics,
        :store,
        {PhoenixAnalytics.Web.DataTest.BrokenStore, []}
      )

      attach_telemetry([:phoenix_analytics, :error])

      assert :ok = Batcher.send_batch([log("a")])
      assert_receive {:telemetry, _event, _measurements, %{error: :insert_batch}}
    end
  end

  describe "terminate/2" do
    test "flushes the pending batch instead of losing it on shutdown" do
      state = %{
        batch: [log("b"), log("a")],
        batch_size: 100,
        flush_interval_ms: 1_000,
        last_insert_time: 0
      }

      assert :ok = Batcher.terminate(:shutdown, state)

      # Prepended while accumulating, so the flush must restore arrival order.
      assert %{count: 2} = Store.info()
      assert {:ok, logs} = Store.export(query(), &Enum.to_list/1)
      assert Enum.map(logs, & &1.request_id) == ["a", "b"]
    end

    test "an empty pending batch is a no-op" do
      state = %{batch: [], batch_size: 100, flush_interval_ms: 1_000, last_insert_time: 0}

      assert :ok = Batcher.terminate(:shutdown, state)
      assert %{count: 0} = Store.info()
    end
  end

  @spec log(String.t()) :: RequestLog.t()
  defp log(request_id) do
    %RequestLog{
      request_id: request_id,
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
  end

  @spec query() :: PhoenixAnalytics.Store.Query.t()
  defp query, do: PhoenixAnalytics.Store.Query.new(~D[2025-01-15], ~D[2025-01-15])

  @spec restore_env(term()) :: :ok
  defp restore_env(nil), do: Application.delete_env(:phoenix_analytics, :store)
  defp restore_env(previous), do: Application.put_env(:phoenix_analytics, :store, previous)

  @spec attach_telemetry([atom()]) :: :ok
  defp attach_telemetry(event) do
    handler_id = {__MODULE__, event, self()}
    test_process = self()

    :telemetry.attach(
      handler_id,
      event,
      fn name, measurements, metadata, _config ->
        send(test_process, {:telemetry, name, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end
end
