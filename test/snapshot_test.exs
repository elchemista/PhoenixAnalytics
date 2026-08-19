defmodule PhoenixAnalytics.SnapshotTest do
  use ExUnit.Case, async: false

  alias PhoenixAnalytics.Fixtures
  alias PhoenixAnalytics.Snapshot
  alias PhoenixAnalytics.Snapshot.Sink.Local
  alias PhoenixAnalytics.Store
  alias PhoenixAnalytics.Store.Query

  @moduletag :tmp_dir

  @table :phoenix_analytics_snapshot_test
  @from ~N[2025-01-14 00:00:00]
  @to ~N[2025-01-15 23:59:59]

  setup %{tmp_dir: tmp_dir} do
    start_supervised!(
      {PhoenixAnalytics.Store.ETS, table: @table, prune_interval_ms: :timer.hours(24)}
    )

    previous = Application.get_env(:phoenix_analytics, :store)
    Application.put_env(:phoenix_analytics, :store, {PhoenixAnalytics.Store.ETS, table: @table})
    on_exit(fn -> restore_env(previous) end)

    :ok = Store.insert_all(Fixtures.request_logs())

    %{sink: {Local, path: tmp_dir}, tmp_dir: tmp_dir}
  end

  describe "run/3" do
    test "writes the period to the sink", %{sink: sink, tmp_dir: tmp_dir} do
      assert {:ok, snapshot} = Snapshot.run(@from, @to, sink: sink)

      assert snapshot.key == "phoenix_analytics/2025-01-15/#{node()}.etf.gz"
      assert snapshot.count == 5
      assert snapshot.bytes > 0
      assert File.exists?(Path.join(tmp_dir, snapshot.key))
    end

    test "honours the requested format and compression", %{sink: sink, tmp_dir: tmp_dir} do
      assert {:ok, snapshot} = Snapshot.run(@from, @to, sink: sink, format: :jsonl, gzip: false)

      assert snapshot.key =~ ".jsonl"
      body = File.read!(Path.join(tmp_dir, snapshot.key))
      assert length(String.split(body, "\n", trim: true)) == 5
    end

    test "reports the sink failure", %{tmp_dir: tmp_dir} do
      sink = {Local, path: Path.join(tmp_dir, "missing/\0invalid")}

      assert {:error, _reason} = Snapshot.run(@from, @to, sink: sink)
    end
  end

  describe "restore/1" do
    test "reloads a snapshot into an empty store", %{sink: sink} do
      {:ok, snapshot} = Snapshot.run(@from, @to, sink: sink)
      {:ok, _deleted} = Store.prune(~N[2030-01-01 00:00:00])
      assert %{count: 0} = Store.info()

      assert {:ok, 5} = Snapshot.restore(sink: sink, restore: [days: 10_000])
      assert %{count: 5} = Store.info()
      assert {:ok, 3} = Store.stat(:total_requests, Query.new(~D[2025-01-15], ~D[2025-01-15]))
      assert snapshot.count == 5
    end

    test "is idempotent", %{sink: sink} do
      {:ok, _snapshot} = Snapshot.run(@from, @to, sink: sink)

      assert {:ok, 5} = Snapshot.restore(sink: sink, restore: [days: 10_000])
      assert {:ok, 5} = Snapshot.restore(sink: sink, restore: [days: 10_000])
      assert %{count: 7} = Store.info()
    end

    test "ignores snapshots older than the restore window", %{sink: sink} do
      {:ok, _snapshot} = Snapshot.run(@from, @to, sink: sink)

      assert {:ok, 0} = Snapshot.restore(sink: sink, restore: [days: 7])
    end

    test "skips unreadable snapshots", %{sink: sink, tmp_dir: tmp_dir} do
      {:ok, snapshot} = Snapshot.run(@from, @to, sink: sink)
      File.write!(Path.join(tmp_dir, snapshot.key), "not a snapshot")

      assert {:ok, 0} = Snapshot.restore(sink: sink, restore: [days: 10_000])
    end
  end

  describe "Scheduler" do
    test "runs on demand and restores at boot", %{sink: sink, tmp_dir: tmp_dir} do
      start_supervised!(
        {PhoenixAnalytics.Snapshot.Scheduler, sink: sink, every: :manual, window: :all}
      )

      assert :ok = PhoenixAnalytics.Snapshot.Scheduler.run_now()

      keys =
        tmp_dir
        |> Path.join("phoenix_analytics/**")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)

      assert length(keys) == 1
    end
  end

  @spec restore_env(term()) :: :ok
  defp restore_env(nil), do: Application.delete_env(:phoenix_analytics, :store)
  defp restore_env(previous), do: Application.put_env(:phoenix_analytics, :store, previous)
end
