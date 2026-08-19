defmodule PhoenixAnalytics.Snapshot.FormatTest do
  use ExUnit.Case, async: true

  alias PhoenixAnalytics.Fixtures
  alias PhoenixAnalytics.Snapshot.Format

  describe "encode/2 and decode/2" do
    test "etf round trips every field" do
      [original | _rest] = logs = Fixtures.request_logs()

      [restored | _rest] = logs |> Format.encode(:etf) |> Format.decode(:etf)

      assert restored.request_id == original.request_id
      assert restored.method == original.method
      assert restored.path == original.path
      assert restored.status_code == original.status_code
      assert restored.duration_ms == original.duration_ms
      assert restored.user_agent == original.user_agent
      assert restored.remote_ip == original.remote_ip
      assert restored.referer == original.referer
      assert restored.device_type == original.device_type
      assert restored.session_id == original.session_id
      assert restored.session_page_views == original.session_page_views
      assert restored.inserted_at == original.inserted_at
      assert length(logs) == 7
    end

    test "jsonl round trips and writes one line per log" do
      logs = Fixtures.request_logs()
      body = logs |> Format.encode(:jsonl) |> IO.iodata_to_binary()

      assert length(String.split(body, "\n", trim: true)) == 7

      assert body |> Format.decode(:jsonl) |> Enum.map(& &1.request_id) ==
               Enum.map(logs, & &1.request_id)
    end

    test "encoded logs carry no Ecto metadata" do
      [encoded | _rest] =
        Fixtures.request_logs() |> Format.encode(:etf) |> :erlang.binary_to_term([:safe])

      refute Map.has_key?(encoded, :__struct__)
      refute Map.has_key?(encoded, :__meta__)
    end
  end

  describe "extension/2" do
    test "reflects the format and compression" do
      assert Format.extension(:etf, true) == "etf.gz"
      assert Format.extension(:etf, false) == "etf"
      assert Format.extension(:jsonl, true) == "jsonl.gz"
    end
  end
end
