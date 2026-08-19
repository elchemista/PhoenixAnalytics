defmodule PhoenixAnalytics.Web.Live.Components.ResChart do
  @moduledoc false

  use PhoenixAnalytics.Web, :live_component

  alias PhoenixAnalytics.Web.Data

  @impl Phoenix.LiveComponent
  def render(assigns) do
    ~H"""
    <div>
      <.react
        name="ResChart"
        dateRange={@date_range}
        chartData={@chart_data.result || []}
        chartTitle={@chart_title}
        socket={@socket}
      />
    </div>
    """
  end

  @impl Phoenix.LiveComponent
  def update(assigns, socket) do
    %{source: source, date_range: date_range} = assigns
    refresh? = socket.assigns[:date_range] != date_range
    socket = assign(socket, assigns)

    if refresh? do
      {:ok,
       assign_async(socket, :chart_data, fn ->
         {:ok, %{chart_data: Data.chart({:slowest, source}, date_range)}}
       end)}
    else
      {:ok, socket}
    end
  end
end
