defmodule PhoenixAnalytics.Web.Live.Components.SingleStat do
  @moduledoc false

  use PhoenixAnalytics.Web, :live_component

  alias PhoenixAnalytics.Web.Data

  @titles %{
    unique_visitors: "Unique visitors",
    total_pageviews: "Total Pageviews",
    total_requests: "Total Requests",
    views_per_visit: "Views per Visit",
    visit_duration: "Visit Duration",
    bounce_rate: "Bounce Rate"
  }

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div>
      <.react
        name="SingleStat"
        statUnit={@stat_unit}
        statTitle={@stat_title}
        dateRange={@date_range}
        statData={@stat_data.result || 0}
        chartData={@chart_data.result || []}
        socket={@socket}
      />
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    %{source: source, date_range: date_range} = assigns
    refresh? = socket.assigns[:date_range] != date_range

    socket =
      socket
      |> assign(assigns)
      |> assign(:stat_title, Map.fetch!(@titles, source))

    if refresh? do
      {:ok,
       socket
       |> assign_async(:stat_data, fn -> {:ok, %{stat_data: Data.stat(source, date_range)}} end)
       |> assign_async(:chart_data, fn ->
         {:ok, %{chart_data: Data.stat_series(source, date_range)}}
       end)}
    else
      {:ok, socket}
    end
  end
end
