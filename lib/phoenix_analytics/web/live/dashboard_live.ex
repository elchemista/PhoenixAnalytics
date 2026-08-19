defmodule PhoenixAnalytics.Web.Live.Dashboard do
  @moduledoc false

  use PhoenixAnalytics.Web, :live_view

  alias PhoenixAnalytics.Store.Query

  @intervals ~w(hour day month year)
  @default_interval "day"
  @default_days 30

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    today = Date.utc_today()

    range = %{
      from: Date.to_string(Date.add(today, -@default_days)) <> " 00:00:00",
      to: Date.to_string(today) <> " 23:59:59"
    }

    {:ok, socket |> assign(:date_range, range) |> assign(:interval, @default_interval)}
  end

  # Both events carry values straight from the client, so anything that would
  # not build a query is discarded in favour of what is already on screen.
  @impl Phoenix.LiveView
  def handle_event("set_date", %{"value" => %{"from" => from, "to" => to}}, socket) do
    {:noreply, assign(socket, :date_range, date_range(from, to, socket.assigns.date_range))}
  end

  def handle_event("set_interval", %{"value" => %{"interval" => interval}}, socket) do
    {:noreply, assign(socket, :interval, interval(interval, socket.assigns.interval))}
  end

  @spec date_range(term(), term(), map()) :: map()
  defp date_range(from, to, current) do
    if Query.valid?(from, to), do: %{from: from, to: to}, else: current
  end

  @spec interval(term(), String.t()) :: String.t()
  defp interval(interval, _current) when interval in @intervals, do: interval
  defp interval(_interval, current), do: current
end
