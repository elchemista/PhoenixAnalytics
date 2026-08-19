defmodule PhoenixAnalytics.Web.Live.DashboardTest do
  use ExUnit.Case, async: true

  alias Phoenix.LiveView.Socket
  alias PhoenixAnalytics.Web.Live.Dashboard

  describe "mount/3" do
    test "starts on the last 30 days with a daily interval" do
      {:ok, socket} = Dashboard.mount(%{}, %{}, socket())

      today = Date.utc_today()
      assert socket.assigns.interval == "day"
      assert socket.assigns.date_range.to == Date.to_string(today) <> " 23:59:59"
      assert socket.assigns.date_range.from == Date.to_string(Date.add(today, -30)) <> " 00:00:00"
    end
  end

  describe "set_interval" do
    test "accepts the supported intervals" do
      for interval <- ~w(hour day month year) do
        assert set_interval(interval) == interval
      end
    end

    test "keeps the current interval when the client sends something else" do
      # The value arrives over the socket, so an unknown one must not reach the
      # store, where it would raise and leave every chart empty.
      assert set_interval("pwned") == "day"
      assert set_interval("") == "day"
      assert set_interval(nil) == "day"
      assert set_interval(%{"a" => 1}) == "day"
    end
  end

  describe "set_date" do
    test "accepts the ranges the picker sends" do
      assert set_date("2025-01-01 00:00:00", "2025-01-31 23:59:59") ==
               %{from: "2025-01-01 00:00:00", to: "2025-01-31 23:59:59"}

      assert set_date("2025-01-01", "2025-01-31") ==
               %{from: "2025-01-01", to: "2025-01-31"}
    end

    test "keeps the current range when the client sends an unparseable one" do
      current = %{from: "2025-01-01 00:00:00", to: "2025-01-31 23:59:59"}

      assert set_date("yesterday", "today") == current
      assert set_date("2025-13-45", "2025-01-31") == current
      assert set_date(nil, "2025-01-31") == current
      assert set_date("", "") == current
    end
  end

  @spec set_interval(term()) :: String.t()
  defp set_interval(interval) do
    socket = %{socket() | assigns: Map.put(socket().assigns, :interval, "day")}
    params = %{"value" => %{"interval" => interval}}

    {:noreply, socket} = Dashboard.handle_event("set_interval", params, socket)

    socket.assigns.interval
  end

  @spec set_date(term(), term()) :: map()
  defp set_date(from, to) do
    current = %{from: "2025-01-01 00:00:00", to: "2025-01-31 23:59:59"}
    socket = %{socket() | assigns: Map.put(socket().assigns, :date_range, current)}
    params = %{"value" => %{"from" => from, "to" => to}}

    {:noreply, socket} = Dashboard.handle_event("set_date", params, socket)

    socket.assigns.date_range
  end

  @spec socket() :: Socket.t()
  defp socket, do: %Socket{assigns: %{__changed__: %{}}}
end
