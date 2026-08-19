defmodule PhoenixAnalytics.Web.Live.Components.DeviceChart do
  @moduledoc false

  use PhoenixAnalytics.Web, :live_component

  alias PhoenixAnalytics.Web.Data

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div>
      <.react
        name="DeviceChart"
        dateRange={@date_range}
        chartData={@chart_data.result || []}
        socket={@socket}
      />
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    %{date_range: date_range} = assigns
    refresh? = socket.assigns[:date_range] != date_range
    socket = assign(socket, assigns)

    if refresh? do
      {:ok,
       assign_async(socket, :chart_data, fn ->
         {:ok, %{chart_data: Data.chart(:devices, date_range)}}
       end)}
    else
      {:ok, socket}
    end
  end
end
